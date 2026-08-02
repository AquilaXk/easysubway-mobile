import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/crashlytics/crash_report_redaction.dart';
import 'package:easysubway_mobile/core/crashlytics/crashlytics_gateway.dart';
import 'package:easysubway_mobile/core/crashlytics/mobile_crash_reporting.dart';
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// firebase_crashlytics 5.2.6이 실제로 전송하는 필드만 모아 payload로 본다.
///
/// `recordFlutterError`는 `exceptionAsString()`·`stack`·`context.toStringDeep()`
/// ·`informationCollector()`를, `recordError`는 `exception.toString()`·`stack`
/// ·`reason`을 전송한다. 여기에 custom key까지 더해 한 문자열로 합친다.
class _RecordingCrashlytics implements CrashlyticsGateway {
  bool collectionEnabled = false;
  final flutterFatals = <FlutterErrorDetails>[];
  final errors = <Object>[];
  final fatalFlags = <bool>[];
  final customKeys = <String, String>{};
  final payloadLines = <String>[];

  String get payloadText => payloadLines.join('\n');

  @override
  bool get isCollectionEnabled => collectionEnabled;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    flutterFatals.add(details);
    fatalFlags.add(true);
    payloadLines.addAll(<String>[
      details.exceptionAsString(),
      details.stack?.toString() ?? '',
      details.context?.toStringDeep(minLevel: DiagnosticLevel.info).trim() ??
          '',
      (details.informationCollector?.call() ?? const <DiagnosticsNode>[])
          .map((node) => node.toStringDeep())
          .join('\n'),
      details.library ?? '',
    ]);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    errors.add(error);
    fatalFlags.add(fatal);
    payloadLines.addAll(<String>[
      error.toString(),
      stackTrace.toString(),
      reason ?? '',
    ]);
  }

  @override
  Future<void> setCustomKey(String key, String value) async {
    customKeys[key] = value;
    payloadLines.addAll(<String>[key, value]);
  }
}

class _SyntheticSecret {
  const _SyntheticSecret(this.id, this.category, this.value);

  final String id;
  final String category;
  final String value;
}

Map<String, Object?> _crashlyticsContract() {
  final file = File('../../contracts/mobile/crashlytics-secret-injection.json');
  expect(file.existsSync(), isTrue, reason: '계약 파일 없음: ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

List<_SyntheticSecret> _syntheticSecrets() {
  final redaction =
      _crashlyticsContract()['redaction']! as Map<String, Object?>;
  return (redaction['syntheticSecrets']! as List)
      .cast<Map<String, Object?>>()
      .map(
        (sample) => _SyntheticSecret(
          sample['id']! as String,
          sample['category']! as String,
          sample['value']! as String,
        ),
      )
      .toList();
}

/// 합성 비밀값을 stack trace의 여러 위치(파일 경로·frame 위치·비-frame 라인)에
/// 심는다. 실제 유출 경로를 모사한다.
StackTrace _syntheticStack(String secret) {
  return StackTrace.fromString(
    '#0      uploadPhoto '
    '(file:///Users/$secret/dev/easysubway/apps/mobile/lib/'
    'facility_report.dart:12:3)\n'
    '#1      main (package:easysubway_mobile/main.dart:20:5)\n'
    '#2      request ($secret)\n'
    '$secret\n'
    '<asynchronous suspension>',
  );
}

final RegExp _sanitizedMessagePattern = RegExp(
  r'^easysubway-crash code=[A-Z_]+ subsystem=[a-z\-]+ '
  r'type=[A-Za-z_$][A-Za-z0-9_$]* fatal=(true|false)'
  r'( status=[1-5]\d{2})? msg=discarded:len=[0-9a-z+\-]+$',
);

final RegExp _sanitizedFramePattern = RegExp(
  r'^#\d+\s+[^()]{0,200}'
  r'\((package:|dart:|file://<redacted-path>|<redacted-path>|https?://)'
  r'[^()\s]*\)$',
);

final RegExp _sanitizedReasonPattern = RegExp(
  r'^subsystem=(flutter-framework|platform-dispatcher|app-report'
  r'|crash-reporting|unknown)$',
);

/// payload의 **모든** 라인이 allowlist shape 중 하나여야 한다.
/// "비밀값이 안 보인다"가 아니라 "허용된 것만 있다"를 단언한다.
void expectPayloadIsAllowlisted(String payloadText, {required String reason}) {
  for (final line in payloadText.split('\n')) {
    final allowed =
        line.isEmpty ||
        line == sanitizedCrashLibrary ||
        line == redactedStackFrameToken ||
        line == truncatedStackFramesToken ||
        line == '<asynchronous suspension>' ||
        _sanitizedMessagePattern.hasMatch(line) ||
        _sanitizedReasonPattern.hasMatch(line) ||
        _sanitizedFramePattern.hasMatch(line);
    expect(allowed, isTrue, reason: 'allowlist 밖 payload 라인($reason): $line');
  }
}

void main() {
  late FlutterExceptionHandler? originalOnError;
  late bool Function(Object error, StackTrace stack)? originalPlatformOnError;

  setUp(() {
    originalOnError = FlutterError.onError;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
    resetCrashlyticsGateway();
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
    resetCrashlyticsGateway();
  });

  test('release enables Crashlytics collection; debug disables it', () async {
    final releaseGateway = _RecordingCrashlytics();
    final releaseReady = await initializeMobileCrashReporting(
      isReleaseMode: true,
      ensureFirebaseReady: () async {},
      createGateway: () => releaseGateway,
    );
    expect(releaseReady, isTrue);
    expect(releaseGateway.collectionEnabled, isTrue);

    final debugGateway = _RecordingCrashlytics();
    final debugReady = await initializeMobileCrashReporting(
      isReleaseMode: false,
      ensureFirebaseReady: () async {},
      createGateway: () => debugGateway,
    );
    expect(debugReady, isTrue);
    expect(debugGateway.collectionEnabled, isFalse);

    // 계약(runtime.debugCollectionEnabled=false)과 동작을 묶어 둔다.
    final runtime = _crashlyticsContract()['runtime']! as Map<String, Object?>;
    expect(runtime['debugCollectionEnabled'], isFalse);
    expect(runtime['releaseCollectionEnabled'], isTrue);
    expect(debugGateway.collectionEnabled, runtime['debugCollectionEnabled']);
    expect(
      releaseGateway.collectionEnabled,
      runtime['releaseCollectionEnabled'],
    );
  });

  test('initializeMobileCrashReporting soft-fails without throwing', () async {
    final ready = await initializeMobileCrashReporting(
      isReleaseMode: true,
      ensureFirebaseReady: () async {
        throw StateError('missing google-services.json');
      },
    );
    expect(ready, isFalse);
    expect(crashlyticsGateway, isA<NoopCrashlyticsGateway>());
  });

  test(
    'FlutterError.onError records via Crashlytics when no zone reporter',
    () async {
      final gateway = _RecordingCrashlytics();
      replaceCrashlyticsGatewayForTest(gateway);
      final originalPresent = FlutterError.presentError;
      FlutterError.presentError = (_) {};
      addTearDown(() {
        FlutterError.presentError = originalPresent;
      });
      installMobileErrorHandlers();

      final details = FlutterErrorDetails(
        exception: StateError('sync-boom'),
        stack: StackTrace.current,
        library: 'test',
      );
      FlutterError.onError?.call(details);
      await pumpEventQueue();

      expect(gateway.flutterFatals, hasLength(1));
      // 원본 예외 대신 정화된 표현이 나간다.
      expect(
        gateway.flutterFatals.single.exception,
        isA<SanitizedCrashException>(),
      );
      expect(
        gateway.flutterFatals.single.exceptionAsString(),
        contains('code=STATE_INVALID subsystem=flutter-framework'),
      );
      expect(gateway.payloadText, isNot(contains('sync-boom')));
    },
  );

  test('PlatformDispatcher.onError records fatal errors', () async {
    final gateway = _RecordingCrashlytics();
    replaceCrashlyticsGatewayForTest(gateway);
    installMobileErrorHandlers();

    final handled = PlatformDispatcher.instance.onError?.call(
      StateError('async-boom'),
      StackTrace.current,
    );
    await pumpEventQueue();

    expect(handled, isTrue);
    expect(gateway.errors, hasLength(1));
    expect(gateway.errors.single, isA<SanitizedCrashException>());
    expect(
      gateway.errors.single.toString(),
      contains('subsystem=platform-dispatcher'),
    );
    expect(gateway.payloadText, isNot(contains('async-boom')));
  });

  test('runWithMobileErrorReporter keeps zone injection contract', () async {
    final reported = <FlutterErrorDetails>[];
    await runWithMobileErrorReporter(reported.add, () async {
      reportMobileError(
        StateError('zoned'),
        StackTrace.current,
        context: 'zone test',
      );
    });
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
  });

  test(
    'zone reporter short-circuits Crashlytics on FlutterError.onError',
    () async {
      final gateway = _RecordingCrashlytics();
      replaceCrashlyticsGatewayForTest(gateway);
      installMobileErrorHandlers();

      final reported = <FlutterErrorDetails>[];
      await runWithMobileErrorReporter(reported.add, () async {
        FlutterError.onError?.call(
          FlutterErrorDetails(
            exception: StateError('zoned-flutter'),
            stack: StackTrace.current,
          ),
        );
      });
      await pumpEventQueue();

      expect(reported, hasLength(1));
      expect(gateway.flutterFatals, isEmpty);
    },
  );

  test('fatal·nonfatal 경로 모두 같은 정화를 거치고 fatal 플래그만 다르다', () async {
    final gateway = _RecordingCrashlytics();
    replaceCrashlyticsGatewayForTest(gateway);

    await recordFatalError(
      StateError('fatal-boom'),
      StackTrace.current,
      subsystem: CrashSubsystem.appReport,
    );
    await recordNonFatalError(StateError('nonfatal-boom'), StackTrace.current);

    expect(gateway.fatalFlags, <bool>[true, false]);
    expect(gateway.errors.first.toString(), contains('fatal=true'));
    expect(gateway.errors.last.toString(), contains('fatal=false'));
    expect(gateway.payloadText, isNot(contains('boom')));
    expectPayloadIsAllowlisted(gateway.payloadText, reason: 'fatal/nonfatal');
  });

  test('custom key는 allowlist를 통과한 것만 전송한다', () async {
    final gateway = _RecordingCrashlytics();
    replaceCrashlyticsGatewayForTest(gateway);

    await setCrashCustomKey('app_version', '1.0.5+10006');
    await setCrashCustomKey('crash_subsystem', 'app-report');
    // allowlist 밖 key
    await setCrashCustomKey('user_id', 'user-0001');
    await setCrashCustomKey('latitude', '37.5665123');
    // allowlist key지만 값 shape 위반
    await setCrashCustomKey('app_version', 'Bearer SYNTHETIC token');

    expect(gateway.customKeys, <String, String>{
      'app_version': '1.0.5+10006',
      'crash_subsystem': 'app-report',
    });
    expect(gateway.payloadText, isNot(contains('user-0001')));
    expect(gateway.payloadText, isNot(contains('37.5665123')));
    expect(gateway.payloadText, isNot(contains('SYNTHETIC')));
  });

  test('synthetic secret 20종을 fatal·nonfatal·Flutter·platform 4경로에 주입해도 '
      'payload match 0', () async {
    final samples = _syntheticSecrets();
    expect(samples, hasLength(20));

    final originalPresent = FlutterError.presentError;
    FlutterError.presentError = (_) {};
    addTearDown(() {
      FlutterError.presentError = originalPresent;
    });

    for (final sample in samples) {
      final gateway = _RecordingCrashlytics();
      replaceCrashlyticsGatewayForTest(gateway);
      installMobileErrorHandlers();
      final secret = sample.value;
      final label = '${sample.id}(${sample.category})';

      // ① Flutter framework 경로: 예외 message·stack·library·context·
      //    informationCollector 전부에 비밀값을 심는다.
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('제보 업로드 실패 payload=$secret'),
          stack: _syntheticStack(secret),
          library: secret,
          context: ErrorDescription(secret),
          informationCollector: () => <DiagnosticsNode>[
            ErrorDescription(secret),
          ],
        ),
      );

      // ② platform/async 경로
      PlatformDispatcher.instance.onError!(
        StateError(secret),
        _syntheticStack(secret),
      );

      // ③ fatal 직접 기록
      await recordFatalError(
        StateError('fatal $secret'),
        _syntheticStack(secret),
        subsystem: CrashSubsystem.appReport,
      );

      // ④ nonfatal 직접 기록(known-safe 예외 + 경로에 신고 식별자 포함)
      await recordNonFatalError(
        ApiException(
          '요청 실패 $secret',
          statusCode: 502,
          path: '/v1/reports/$secret/photo',
        ),
        _syntheticStack(secret),
      );

      // custom key로도 흘려본다.
      await setCrashCustomKey('crash_subsystem', secret);
      await setCrashCustomKey(secret, secret);

      await pumpEventQueue();

      expect(gateway.flutterFatals, hasLength(1), reason: label);
      expect(gateway.errors, hasLength(3), reason: label);
      expect(gateway.fatalFlags, <bool>[
        true,
        true,
        true,
        false,
      ], reason: label);
      expect(gateway.customKeys, isEmpty, reason: label);
      // allowlist 단언이 빈 payload로 공허하게 통과하지 않도록 못 박는다.
      expect(gateway.payloadText.trim(), isNotEmpty, reason: label);
      expect(
        gateway.payloadText,
        contains('easysubway-crash code='),
        reason: label,
      );
      expect(
        gateway.payloadText,
        isNot(contains(secret)),
        reason: 'payload에 합성 비밀값이 남았습니다: $label',
      );
      expectPayloadIsAllowlisted(gateway.payloadText, reason: label);
    }
  });
}
