/// Crashlytics·전역 오류 로그 전송 payload 정화 계층.
///
/// 계약 정본은 `contracts/mobile/crashlytics-secret-injection.json`의 `redaction`
/// 절이며, 실행 결속은 아래 두 test가 담당한다.
/// - `test/core/crashlytics/crash_report_redaction_test.dart`
/// - `test/core/crashlytics/mobile_error_handlers_test.dart`
///
/// ## 방식: allowlist
///
/// 전송 문자열은 원문을 걸러내는 방식이 아니라, 이 파일이 **닫힌 필드 집합으로
/// 새로 조립한다**. 예외의 raw message(`exception.toString()`)는 어떤 경우에도
/// payload에 실리지 않고 폐기하며, 길이 구간만 남긴다. 미지 예외 타입이 들어와도
/// 새 필드가 생길 수 없으므로 "모르는 필드가 새는" 경로 자체가 없다.
///
/// stack trace만 원문 라인을 재사용한다. release 심볼리케이션이 stack 원문에
/// 의존하기 때문이다. 대신 ① URI·filesystem path를 먼저 정규화하고 ② 알려진
/// frame shape allowlist를 통과한 라인만 남기며 나머지는 `<redacted-frame>`으로
/// 치환한다(라인 수는 보존해 프레임 순서를 깨지 않는다).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../network/api_error.dart';

/// 조립된 crash message 상한.
///
/// Crashlytics는 message로 issue를 grouping하므로 짧고 결정적인 문자열이 유리하다.
/// 닫힌 필드 집합의 최대 길이는 약 160자이며, 이후 allowlist 필드가 늘어도 leak
/// 폭이 이 값을 넘지 않도록 상한을 고정한다.
const int maxSanitizedCrashMessageLength = 256;

/// stack trace 유지 라인 수 상한.
///
/// AOT obfuscated trace 헤더(`*** *** ***`~`vm_instructions:`)가 최대 8줄이고
/// Flutter 크래시 stack은 통상 20~40 프레임이다. 96줄은 진단에 충분하면서
/// 비정상적으로 긴 stack이 그대로 전송되는 것을 막는다.
const int maxSanitizedStackLines = 96;

/// stack trace 라인 하나의 상한.
///
/// 정규화된 VM 프레임(`#12  Foo.bar (package:...dart:123:45)`)은 120자 미만이다.
/// 240자는 긴 제네릭 멤버명을 살리면서, 라인 안에 끼어든 비정상 blob을 잘라낸다.
const int maxSanitizedStackLineLength = 240;

/// 예외 타입 토큰 상한. Dart 타입명은 이 길이를 넘지 않는다.
const int maxCrashTypeTokenLength = 64;

/// custom key 값 상한.
///
/// Crashlytics custom key 값 한도는 1024 byte지만, allowlist가 허용하는 값은
/// 짧은 토큰뿐이므로 그보다 훨씬 낮게 묶어 사고 시 노출 폭을 줄인다.
const int maxCrashCustomKeyValueLength = 100;

/// 정화된 message 접두. 로그·payload에서 정화 경로를 식별한다.
const String sanitizedCrashMessagePrefix = 'easysubway-crash';

/// 알 수 없는 예외에 부여하는 stable error code.
const String unknownCrashErrorCode = 'UNKNOWN_ERROR';

/// 전송 details의 `library` 고정값.
///
/// `FlutterErrorDetails.library`는 호출자가 채우는 자유 문자열이고
/// firebase_crashlytics가 전송하지도 않는다. 통과시킬 이유가 없어 상수로 고정한다.
/// 어느 경로에서 온 크래시인지는 `subsystem` 필드가 담는다.
const String sanitizedCrashLibrary = 'easysubway mobile';

/// 타입 토큰 allowlist를 통과하지 못한 예외에 쓰는 대체 토큰.
const String unknownCrashTypeToken = 'UnknownType';

const String _redactedPathToken = '<redacted-path>';
const String _redactedHostToken = '<redacted-host>';
const String _redactedUserInfoToken = '<redacted-userinfo>';
const String _redactedQueryToken = '<redacted-query>';

/// shape allowlist를 통과하지 못한 stack 라인 치환 토큰.
const String redactedStackFrameToken = '<redacted-frame>';

/// 라인 수 상한 초과 시 붙이는 토큰.
const String truncatedStackFramesToken = '<truncated-frames>';

/// 전송이 허용된 subsystem 토큰(닫힌 집합).
enum CrashSubsystem {
  flutterFramework('flutter-framework'),
  platformDispatcher('platform-dispatcher'),
  appReport('app-report'),
  crashReporting('crash-reporting'),
  unknown('unknown');

  const CrashSubsystem(this.wireValue);

  final String wireValue;
}

/// 전송이 허용된 stable error code(닫힌 집합).
const Set<String> crashErrorCodeAllowlist = <String>{
  'API_REQUEST_FAILED',
  'TLS_HANDSHAKE_FAILED',
  'TLS_FAILED',
  'NETWORK_UNAVAILABLE',
  'HTTP_TRANSPORT_FAILED',
  'FILE_SYSTEM_FAILED',
  'TIMEOUT',
  'PLATFORM_PLUGIN_MISSING',
  'PLATFORM_CHANNEL_FAILED',
  'FORMAT_INVALID',
  'RANGE_INVALID',
  'ARGUMENT_INVALID',
  'STATE_INVALID',
  'UNIMPLEMENTED',
  'UNSUPPORTED',
  'TYPE_INVALID',
  'OUT_OF_MEMORY',
  'STACK_OVERFLOW',
  'ASSERTION_FAILED',
  unknownCrashErrorCode,
};

/// custom key별 값 검증기(닫힌 집합).
///
/// key 이름만이 아니라 **값의 형태까지 key마다 못 박는다**. 범용 charset 허용은
/// `ya29.…` 같은 토큰이 통과하는 구멍이 되므로 쓰지 않는다. 새 key를 추가하려면
/// 이 map과 계약 JSON을 함께 바꿔야 하고, `crash_report_redaction_test.dart`의
/// 계약 test가 두 쪽의 일치를 강제한다.
final Map<String, bool Function(String)>
_crashCustomKeyValidators = <String, bool Function(String)>{
  'app_build_variant': const <String>{'debug', 'profile', 'release'}.contains,
  'app_version': RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}(\+\d{1,9})?$').hasMatch,
  'crash_error_code': crashErrorCodeAllowlist.contains,
  'crash_subsystem': (value) =>
      CrashSubsystem.values.any((subsystem) => subsystem.wireValue == value),
  // device class는 유한 열거다. 넓은 slug 정규식은 소문자 토큰형 자격증명을
  // 통과시키므로(finding #2) os_class처럼 닫힌 집합으로 못 박는다.
  'device_class': crashDeviceClassAllowlist.contains,
  'os_class': RegExp(r'^(android|ios)-\d{1,3}$').hasMatch,
};

/// 전송이 허용된 device class 값(닫힌 집합). form factor 열거만 담는다.
const Set<String> crashDeviceClassAllowlist = <String>{
  'phone',
  'tablet',
  'foldable',
  'desktop',
  'tv',
  'wear',
  'automotive',
  'unknown',
};

/// 전송이 허용된 custom key 이름(닫힌 집합).
final Set<String> crashCustomKeyAllowlist = Set<String>.unmodifiable(
  _crashCustomKeyValidators.keys,
);

/// Crashlytics로 나갈 정화된 crash 표현.
@immutable
class SanitizedCrashReport {
  const SanitizedCrashReport({
    required this.errorCode,
    required this.subsystem,
    required this.typeToken,
    required this.fatal,
    required this.message,
    required this.stackTrace,
    this.httpStatus,
  });

  final String errorCode;
  final CrashSubsystem subsystem;
  final String typeToken;
  final bool fatal;

  /// 닫힌 필드 집합으로 조립된 전송 문자열.
  final String message;
  final StackTrace stackTrace;
  final int? httpStatus;

  /// Crashlytics에 넘길 예외 대체 객체. `toString()`이 곧 [message]다.
  Object get exception => SanitizedCrashException(message);

  /// Crashlytics `reason`으로 나갈 문자열. subsystem enum에서만 만들어진다.
  String get reason => 'subsystem=${subsystem.wireValue}';

  /// Flutter 경로 전송용 details. 원본 `informationCollector`는 위젯 트리와
  /// 사용자 입력을 그대로 담을 수 있어 승계하지 않는다.
  FlutterErrorDetails toFlutterErrorDetails({bool silent = false}) {
    return FlutterErrorDetails(
      exception: exception,
      stack: stackTrace,
      library: sanitizedCrashLibrary,
      context: ErrorDescription(reason),
      silent: silent,
    );
  }
}

/// 원본 예외를 대체하는 전송 객체. `toString()`이 정화된 message만 돌려준다.
@immutable
class SanitizedCrashException implements Exception {
  const SanitizedCrashException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 예외를 stable error code로 환산한다. 미지 타입은 [unknownCrashErrorCode].
String stableCrashErrorCode(Object? error) {
  final code = switch (error) {
    ApiException() => 'API_REQUEST_FAILED',
    HandshakeException() => 'TLS_HANDSHAKE_FAILED',
    TlsException() => 'TLS_FAILED',
    SocketException() => 'NETWORK_UNAVAILABLE',
    HttpException() => 'HTTP_TRANSPORT_FAILED',
    FileSystemException() => 'FILE_SYSTEM_FAILED',
    TimeoutException() => 'TIMEOUT',
    MissingPluginException() => 'PLATFORM_PLUGIN_MISSING',
    PlatformException() => 'PLATFORM_CHANNEL_FAILED',
    FormatException() => 'FORMAT_INVALID',
    RangeError() => 'RANGE_INVALID',
    ArgumentError() => 'ARGUMENT_INVALID',
    StateError() => 'STATE_INVALID',
    UnimplementedError() => 'UNIMPLEMENTED',
    UnsupportedError() => 'UNSUPPORTED',
    TypeError() => 'TYPE_INVALID',
    OutOfMemoryError() => 'OUT_OF_MEMORY',
    StackOverflowError() => 'STACK_OVERFLOW',
    AssertionError() => 'ASSERTION_FAILED',
    _ => unknownCrashErrorCode,
  };
  // 등록되지 않은 code가 조립 단계로 새지 않게 마지막에 한 번 더 닫는다.
  return crashErrorCodeAllowlist.contains(code) ? code : unknownCrashErrorCode;
}

/// 예외·stack을 allowlist 필드만으로 재조립한다.
SanitizedCrashReport sanitizeCrashReport(
  Object? error,
  StackTrace? stackTrace, {
  required bool fatal,
  required CrashSubsystem subsystem,
}) {
  final errorCode = stableCrashErrorCode(error);
  final typeToken = _sanitizeTypeToken(error);
  final httpStatus = _httpStatusOf(error);
  final fields = <String, String>{
    'code': errorCode,
    'subsystem': subsystem.wireValue,
    'type': typeToken,
    'fatal': '$fatal',
    if (httpStatus != null) 'status': '$httpStatus',
    // raw message는 폐기하고 길이 구간만 남긴다(내용 없음).
    'msg': 'discarded:len=${_rawMessageLengthBucket(error)}',
  };
  final message = _truncate(
    '$sanitizedCrashMessagePrefix '
    '${fields.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}',
    maxSanitizedCrashMessageLength,
  );

  return SanitizedCrashReport(
    errorCode: errorCode,
    subsystem: subsystem,
    typeToken: typeToken,
    fatal: fatal,
    message: message,
    stackTrace: sanitizeStackTrace(stackTrace),
    httpStatus: httpStatus,
  );
}

/// Flutter 경로 details를 통째로 정화한다.
FlutterErrorDetails sanitizeFlutterErrorDetails(
  FlutterErrorDetails details, {
  required CrashSubsystem subsystem,
}) {
  return sanitizeCrashReport(
    details.exception,
    details.stack,
    fatal: true,
    subsystem: subsystem,
  ).toFlutterErrorDetails(silent: details.silent);
}

/// stack trace를 정규화한다. `null`은 빈 trace로 접는다.
StackTrace sanitizeStackTrace(StackTrace? stackTrace) {
  if (stackTrace == null) {
    return StackTrace.empty;
  }
  return StackTrace.fromString(sanitizeStackTraceText(stackTrace.toString()));
}

/// stack trace 원문 텍스트 정규화(라인 단위).
String sanitizeStackTraceText(String text) {
  final lines = text.split('\n');
  final sanitized = <String>[];
  for (final line in lines) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) {
      continue;
    }
    if (sanitized.length >= maxSanitizedStackLines) {
      sanitized.add(truncatedStackFramesToken);
      break;
    }
    final redacted = redactSensitiveText(trimmed);
    final leading = redacted.substring(
      0,
      redacted.length - redacted.trimLeft().length,
    );
    final safeBody = _sanitizeStackLine(redacted.trimLeft());
    // 라인이 통째로 폐기되면 들여쓰기도 남기지 않는다.
    final safe = safeBody == redactedStackFrameToken
        ? safeBody
        : '$leading$safeBody';
    sanitized.add(_truncate(safe, maxSanitizedStackLineLength));
  }
  return sanitized.join('\n');
}

/// URI query·경로와 filesystem path를 제거한다.
///
/// `package:`·`dart:` scheme URI는 사용자 데이터를 담지 않고 심볼리케이션에
/// 필요하므로 그대로 둔다.
String redactSensitiveText(String text) {
  final withoutUris = text.replaceAllMapped(_uriPattern, _redactUriMatch);
  final withoutPosixPaths = withoutUris.replaceAllMapped(
    _absolutePosixPathPattern,
    (match) => _normalizePathWithLocation(match.group(1)!),
  );
  return withoutPosixPaths.replaceAllMapped(
    _windowsPathPattern,
    (match) => _normalizePathWithLocation(match.group(1)!),
  );
}

/// allowlist를 통과한 custom key 값만 돌려준다. 통과 못 하면 `null`(폐기).
String? sanitizeCrashCustomKeyValue(String key, Object? value) {
  final isValid = _crashCustomKeyValidators[key];
  if (isValid == null) {
    return null;
  }
  if (value is! String && value is! int && value is! bool) {
    return null;
  }
  final candidate = '$value'.trim();
  if (candidate.isEmpty || candidate.length > maxCrashCustomKeyValueLength) {
    return null;
  }
  return isValid(candidate) ? candidate : null;
}

/// 로그에 남겨도 되는 custom key 이름. allowlist 밖 이름은 그대로 찍지 않는다.
String describeCrashCustomKeyName(String key) {
  return crashCustomKeyAllowlist.contains(key) ? key : '<rejected-key>';
}

/// 고엔트로피 blob(hex·base64 계열·점 연결 자격증명) 추정.
///
/// 공백 없는 단일 토큰이라도 `ya29.…` OAuth·3-세그먼트 JWT처럼 **점으로 연결된**
/// 자격증명은 base64 판정을 우회하므로(점이 base64 charset 밖) 별도로 잡는다.
bool looksLikeSecretToken(String value) {
  if (_hexBlobPattern.hasMatch(value)) {
    return true;
  }
  if (_base64BlobPattern.hasMatch(value) &&
      _hasDigit.hasMatch(value) &&
      _hasLetter.hasMatch(value)) {
    return true;
  }
  if (_oauthTokenPattern.hasMatch(value)) {
    return true;
  }
  return _looksLikeJwt(value);
}

/// 3-세그먼트 JWT(`header.payload.signature`) 추정.
///
/// 세그먼트 각각이 충분히 길고 base64url이며, 최소 2개가 숫자를 포함해야 한다.
/// 점 3단 소스 식별자(`Foo.bar.baz`)는 세그먼트가 짧거나 숫자가 없어 걸리지 않는다.
bool _looksLikeJwt(String value) {
  if (value.length < 30) {
    return false;
  }
  final segments = value.split('.');
  if (segments.length < 3) {
    return false;
  }
  var segmentsWithDigit = 0;
  for (final segment in segments) {
    if (segment.length < 6 || !_base64UrlSegmentPattern.hasMatch(segment)) {
      return false;
    }
    if (_hasDigit.hasMatch(segment)) {
      segmentsWithDigit++;
    }
  }
  return segmentsWithDigit >= 2;
}

int? _httpStatusOf(Object? error) {
  if (error is! ApiException) {
    return null;
  }
  final status = error.statusCode;
  if (status == null || status < 100 || status > 599) {
    return null;
  }
  return status;
}

String _rawMessageLengthBucket(Object? error) {
  final int length;
  try {
    length = error?.toString().length ?? 0;
  } catch (_) {
    // toString()이 실패하는 객체도 있다. 길이 정보 없이 넘어간다.
    return 'unknown';
  }
  if (length == 0) return '0';
  if (length <= 16) return '1-16';
  if (length <= 64) return '17-64';
  if (length <= 256) return '65-256';
  if (length <= 1024) return '257-1024';
  return '1024+';
}

String _sanitizeTypeToken(Object? error) {
  if (error == null) {
    return 'Null';
  }
  var token = error.runtimeType.toString().trim();
  final genericIndex = token.indexOf('<');
  if (genericIndex > 0) {
    token = token.substring(0, genericIndex);
  }
  if (token.isEmpty || token.length > maxCrashTypeTokenLength) {
    return unknownCrashTypeToken;
  }
  if (!_typeTokenPattern.hasMatch(token) || looksLikeSecretToken(token)) {
    return unknownCrashTypeToken;
  }
  return token;
}

String _redactUriMatch(Match match) {
  final scheme = match.group(1)!.toLowerCase();
  final rest = match.group(2)!;
  if (scheme == 'file') {
    return 'file://${_normalizePathWithLocation(rest)}';
  }

  final authorityEnd = _firstIndexOfAny(rest, const ['/', '?', '#']);
  final authority = authorityEnd < 0 ? rest : rest.substring(0, authorityEnd);
  final remainder = authorityEnd < 0 ? '' : rest.substring(authorityEnd);
  final buffer = StringBuffer('$scheme://${_sanitizeAuthority(authority)}');
  if (remainder.startsWith('/') && remainder.length > 1) {
    buffer.write('/$_redactedPathToken');
  } else if (remainder.startsWith('/')) {
    buffer.write('/');
  }
  if (remainder.contains('?')) {
    buffer.write('?$_redactedQueryToken');
  }
  return buffer.toString();
}

String _sanitizeAuthority(String authority) {
  // host는 항상 제거한다. crash 심볼리케이션은 stack frame 주소·build_id로
  // 이뤄지고 URL host는 진단에 필요하지 않다. 반대로 host에는 신고 식별자가
  // subdomain으로 박히거나(예: RPT-…-…​.example.com) signed URL·오브젝트
  // 스토리지 host(이 PR denylist 대상)가 남을 수 있어, 문자 형태만 검증하고
  // verbatim 통과시키면 저엔트로피 식별자가 새어 나간다. userinfo 존재 여부만
  // 표식으로 남긴다.
  final hasUserInfo = authority.contains('@');
  final prefix = hasUserInfo ? '$_redactedUserInfoToken@' : '';
  return '$prefix$_redactedHostToken';
}

String _normalizePathWithLocation(String value) {
  final locationMatch = _locationSuffixPattern.firstMatch(value);
  final suffix = locationMatch?.group(0) ?? '';
  final path = suffix.isEmpty
      ? value
      : value.substring(0, value.length - suffix.length);
  return '${_normalizeFilesystemPath(path)}$suffix';
}

/// 개인 식별 가능한 디렉터리(사용자명·앱 샌드박스 UUID 등)를 제거한다.
///
/// 소스 파일명은 심볼리케이션에 필요하므로 확장자 allowlist를 통과할 때만
/// 남기고, 그 밖의 파일명(사진 파일명 등)은 통째로 폐기한다.
String _normalizeFilesystemPath(String rawPath) {
  final path = rawPath.replaceAll(r'\', '/');
  final lastSlash = path.lastIndexOf('/');
  final basename = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
  if (!_sourceFileNamePattern.hasMatch(basename)) {
    return _redactedPathToken;
  }
  for (final anchor in _sourcePathAnchors) {
    final index = path.lastIndexOf(anchor);
    if (index >= 0) {
      return '$_redactedPathToken${path.substring(index)}';
    }
  }
  return '$_redactedPathToken/$basename';
}

/// stack 라인 하나를 정화한다. 통과 문법을 **끝까지** 검증하고, 접두만 맞고
/// 뒤에 임의 문자열이 붙은 라인(예: `#0 abs deadbeef Bearer …`,
/// `os: … Authorization: Bearer …`)은 검증된 토큰만 남기거나 폐기한다.
///
/// 접두 `startsWith`만 보던 이전 구현은 허용 라인 뒤에 붙은 자격증명을 그대로
/// 전송하는 구멍이었다(finding #1). 여기서는 어느 경로도 검증 안 된 접미사를
/// 남기지 않는다.
String _sanitizeStackLine(String line) {
  if (line.isEmpty) {
    return line;
  }
  // stack frame은 컴파일된 심볼과 URI로만 이뤄진다. 비-ASCII가 섞였다면
  // 사용자 입력(역 검색어·제보 설명 등)이 흘러든 것으로 보고 통째로 버린다.
  if (!_asciiOnlyPattern.hasMatch(line)) {
    return redactedStackFrameToken;
  }
  if (_allowedStackLineLiterals.contains(line)) {
    return line;
  }
  if (_separatorLinePattern.hasMatch(line)) {
    return line;
  }

  // AOT obfuscated frame: 주소 헤더(abs·virt)는 심볼리케이션에 필요하므로 보존하고,
  // 인식되지 않은 심볼 꼬리는 잘라낸다. 헤더 자체가 매칭될 때만 통과한다.
  final aotHeader = _aotFrameHeaderPattern.matchAsPrefix(line);
  if (aotHeader != null) {
    final tail = line.substring(aotHeader.end);
    if (tail.isEmpty || _aotFrameSymbolPattern.hasMatch(tail)) {
      return line;
    }
    return line.substring(0, aotHeader.end);
  }

  // JIT/friendly frame: 문법을 끝까지 검증하고, 어느 토큰이라도 비밀 형태면 버린다.
  // frame에는 고엔트로피 hex 주소가 없어 secret-token 판정이 오탐하지 않는다.
  if ((_jitFramePattern.hasMatch(line) ||
          _friendlyFramePattern.hasMatch(line)) &&
      !_lineHasSecretToken(line)) {
    return line;
  }

  // 심볼리케이션에 필요한 VM 헤더(build_id·loading_unit)만 검증된 토큰으로 보존한다.
  // 나머지 헤더(os·pid·dso_base 등)는 Crashlytics가 전송하지 않으므로 폐기한다.
  final buildId = _buildIdPrefixPattern.matchAsPrefix(line);
  if (buildId != null) {
    return line.substring(0, buildId.end);
  }
  final loadingUnit = _loadingUnitPrefixPattern.matchAsPrefix(line);
  if (loadingUnit != null) {
    return line.substring(0, loadingUnit.end);
  }

  return redactedStackFrameToken;
}

bool _lineHasSecretToken(String line) {
  return line.split(_tokenSeparatorPattern).any(looksLikeSecretToken);
}

int _firstIndexOfAny(String value, List<String> needles) {
  var found = -1;
  for (final needle in needles) {
    final index = value.indexOf(needle);
    if (index >= 0 && (found < 0 || index < found)) {
      found = index;
    }
  }
  return found;
}

String _truncate(String value, int limit) {
  if (value.length <= limit) {
    return value;
  }
  const marker = '~trunc';
  if (limit <= marker.length) {
    return value.substring(0, limit);
  }
  return '${value.substring(0, limit - marker.length)}$marker';
}

final RegExp _uriPattern = RegExp(
  r'([a-zA-Z][a-zA-Z0-9+.\-]*)://([^\s"'
  r"'"
  r'\)\]<>]*)',
);

// 절대 POSIX 경로. `package:foo/bar.dart`처럼 앞에 식별자가 붙은 슬래시와
// 이미 치환된 `<redacted-path>/...`는 lookbehind로 제외한다.
final RegExp _absolutePosixPathPattern = RegExp(
  r'(?<![\w:@.\-/>])(/(?:[A-Za-z0-9_.\-+%@~]+/)*[A-Za-z0-9_.\-+%@~]+)',
);

final RegExp _windowsPathPattern = RegExp(
  r'(?<![\w])([A-Za-z]:\\(?:[A-Za-z0-9_.\-+%@~]+\\)*[A-Za-z0-9_.\-+%@~]+)',
);

final RegExp _locationSuffixPattern = RegExp(r'(:\d+)+$');

final RegExp _typeTokenPattern = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

final RegExp _asciiOnlyPattern = RegExp(r'^[\x20-\x7E]*$');

// `===== asynchronous gap ====…`(package:stack_trace)와 AOT 헤더 `*** *** ***`.
// 접두만 보면 뒤 문자열이 검증 없이 통과하므로 라인 전체 형태를 못 박는다.
final RegExp _separatorLinePattern = RegExp(
  r'^(=+( asynchronous gap =+)?|\*\*\*( \*\*\*)+)$',
);

final RegExp _sourceFileNamePattern = RegExp(
  r'^[A-Za-z0-9_.\-]{1,64}\.(dart|kt|java|swift|m|mm|c|cc|cpp|h|hpp|js)$',
);

final RegExp _hexBlobPattern = RegExp(r'^[0-9a-fA-F]{16,}$');

final RegExp _base64BlobPattern = RegExp(r'^[A-Za-z0-9_\-+/=]{24,}$');

// 알려진 자격증명 접두(OAuth·API key·PAT). 점·하이픈·언더스코어 body를 허용해
// `ya29.…`처럼 점 연결된 토큰도 단일 토큰으로 잡는다.
final RegExp _oauthTokenPattern = RegExp(
  r'^(ya29|1//|AIza|AKIA|ASIA|ghp_|gho_|xox[baprs]|sk_|sk-)[A-Za-z0-9_.\-]{8,}$',
);

final RegExp _base64UrlSegmentPattern = RegExp(r'^[A-Za-z0-9_\-]+$');

final RegExp _hasDigit = RegExp(r'[0-9]');

final RegExp _hasLetter = RegExp(r'[A-Za-z]');

final RegExp _tokenSeparatorPattern = RegExp(r'[\s,]+');

// AOT obfuscated frame 헤더: `#00 abs <hex> [virt <hex>]`. `$`로 끝을 못 박지
// 않는다(꼬리는 심볼로 별도 검증). matchAsPrefix로 헤더 길이를 잰다.
final RegExp _aotFrameHeaderPattern = RegExp(
  r'^#\d+\s+abs\s+[0-9a-fA-F]{1,20}(\s+virt\s+[0-9a-fA-F]{1,20})?',
);

// AOT frame 심볼 꼬리: ` _kDart…+0x<hex>` 형태만 허용(끝 앵커). 그 밖의 꼬리는
// 헤더만 남기고 잘라낸다.
final RegExp _aotFrameSymbolPattern = RegExp(
  r'^\s+[A-Za-z0-9_$.]+\+0x[0-9a-fA-F]+$',
);

// 실제 Dart VM frame member 문법(allowlist 재구축). `(new )?`로 시작할 수 있고
// 점으로 연결된 세그먼트다. 각 세그먼트는 식별자(+선택 generic)·generic/closure
// 토큰·소수 operator 이름뿐이다. **좌표(숫자로 시작)·쉼표·공백·콜론·URL은 정상
// member에 없으므로** member 위치에 넣어도 이 문법에서 구조적으로 탈락한다.
// 검증만 하고 원본을 forward하지 않고, 이 문법에 맞는 라인만 통과시킨다.
const String _memberSegmentPattern =
    r'(?:'
    r'[A-Za-z_$][A-Za-z0-9_$]*(?:<[A-Za-z0-9_$,<> ]{0,80}>)?'
    r'|<[A-Za-z0-9_$,<> ]{0,80}>'
    r'|==|\[\]=?|unary-'
    r')';

final String _memberChainSource =
    '(?:new )?$_memberSegmentPattern(?:\\.$_memberSegmentPattern)*';

// JIT frame: 멤버는 위 문법으로 좁히고, 괄호 안 위치는 allowlist된 URI 접두로
// 시작해 `)`로 끝나야 한다(끝 앵커).
final RegExp _jitFramePattern = RegExp(
  '^#\\d+\\s+$_memberChainSource\\s+'
  r'\((package:|dart:|file://|<redacted-path>|<redacted-host>|https?://)'
  r'[^()\s]*\)$',
);

// friendly frame(괄호 없는 `package:… line:col member` 형태): 멤버는 위 VM 문법과
// 동일하게 좁힌다.
final RegExp _friendlyFramePattern = RegExp(
  r'^(package:|dart:|<redacted-path>)\S+\s+\d+(:\d+)?\s+'
  '$_memberChainSource\$',
);

// 심볼리케이션 필수 VM 헤더 추출기. 검증된 토큰까지만 남기고 접미는 버린다.
final RegExp _buildIdPrefixPattern = RegExp(r"^build_id: '[0-9a-fA-F]{1,64}'");

final RegExp _loadingUnitPrefixPattern = RegExp(r'^loading_unit: \d{1,9}');

const List<String> _sourcePathAnchors = <String>[
  '/lib/',
  '/test/',
  '/packages/',
  '/bin/',
  '/tool/',
];

const Set<String> _allowedStackLineLiterals = <String>{
  '<asynchronous suspension>',
  '...',
  redactedStackFrameToken,
  truncatedStackFramesToken,
};
