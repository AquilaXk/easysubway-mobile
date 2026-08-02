import 'package:easysubway_mobile/core/crashlytics/crash_report_redaction.dart';
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'crashlytics_contract_fixture.dart';

void main() {
  group('계약 결속', () {
    late Map<String, Object?> contract;

    setUp(() {
      contract = crashlyticsRedactionContract();
    });

    test('error code·subsystem·custom key allowlist가 계약과 일치한다', () {
      expect(contract['approach'], 'allowlist');
      expect(contract['rawMessageDisposition'], 'discard');
      expect(
        (contract['errorCodeAllowlist']! as List).cast<String>().toSet(),
        crashErrorCodeAllowlist,
      );
      expect(
        (contract['subsystemAllowlist']! as List).cast<String>().toSet(),
        CrashSubsystem.values.map((value) => value.wireValue).toSet(),
      );
      expect(
        (contract['customKeyAllowlist']! as List).cast<String>().toSet(),
        crashCustomKeyAllowlist,
      );
    });

    test('길이·폐기 기준 수치가 계약과 일치한다', () {
      final limits = contract['limits']! as Map<String, Object?>;
      expect(
        limits['maxSanitizedCrashMessageLength'],
        maxSanitizedCrashMessageLength,
      );
      expect(limits['maxSanitizedStackLines'], maxSanitizedStackLines);
      expect(
        limits['maxSanitizedStackLineLength'],
        maxSanitizedStackLineLength,
      );
      expect(limits['maxCrashTypeTokenLength'], maxCrashTypeTokenLength);
      expect(
        limits['maxCrashCustomKeyValueLength'],
        maxCrashCustomKeyValueLength,
      );
    });

    test('synthetic secret은 20종이고 id가 중복되지 않는다', () {
      final samples = (contract['syntheticSecrets']! as List)
          .cast<Map<String, Object?>>();
      expect(samples, hasLength(20));
      final ids = samples.map((sample) => sample['id']! as String).toList();
      expect(ids.toSet(), hasLength(20));
      for (final sample in samples) {
        expect((sample['category']! as String), isNotEmpty);
        expect((sample['value']! as String), isNotEmpty);
      }
    });
  });

  group('crash message 조립', () {
    test('raw message는 폐기하고 닫힌 필드만 남긴다', () {
      final report = sanitizeCrashReport(
        StateError('업로드 실패 token=Bearer SYNTHETIC-abcdefghijklmnop'),
        StackTrace.fromString(
          '#0      main (package:easysubway_mobile/x.dart:1:2)',
        ),
        fatal: false,
        subsystem: CrashSubsystem.appReport,
      );

      expect(
        report.message,
        'easysubway-crash code=STATE_INVALID subsystem=app-report '
        'type=StateError fatal=false msg=discarded:len=17-64',
      );
      expect(report.message, isNot(contains('SYNTHETIC')));
      expect(report.message, isNot(contains('Bearer')));
      expect(report.exception.toString(), report.message);
      expect(report.reason, 'subsystem=app-report');
    });

    test('known-safe 예외는 structured field로 환산한다', () {
      final report = sanitizeCrashReport(
        const ApiException(
          '요청을 완료하지 못했어요.',
          statusCode: 503,
          path: '/v1/reports/RPT-2026-000123-SYNTHETIC/photo',
        ),
        StackTrace.empty,
        fatal: false,
        subsystem: CrashSubsystem.appReport,
      );

      expect(report.errorCode, 'API_REQUEST_FAILED');
      expect(report.httpStatus, 503);
      expect(report.message, contains('status=503'));
      // path는 신고 식별자를 담을 수 있어 allowlist 밖이다.
      expect(report.message, isNot(contains('RPT-2026')));
      expect(report.message, isNot(contains('/v1/reports')));
    });

    test('message 길이 상한을 넘지 않는다', () {
      final report = sanitizeCrashReport(
        StateError(List.filled(100000, 'x').join()),
        StackTrace.empty,
        fatal: true,
        subsystem: CrashSubsystem.unknown,
      );
      expect(
        report.message.length,
        lessThanOrEqualTo(maxSanitizedCrashMessageLength),
      );
      expect(report.message, contains('msg=discarded:len=1024+'));
    });

    test('타입 토큰은 식별자 shape만 통과한다', () {
      final stringThrow = sanitizeCrashReport(
        'Authorization: Bearer SYNTHETIC-raw-string-throw',
        StackTrace.empty,
        fatal: false,
        subsystem: CrashSubsystem.appReport,
      );
      expect(stringThrow.typeToken, 'String');
      expect(stringThrow.errorCode, unknownCrashErrorCode);
      expect(stringThrow.message, isNot(contains('SYNTHETIC')));
    });

    test('library는 상수로 고정하고 context·informationCollector는 버린다', () {
      final details = FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.empty,
        library: '/Users/synthetic-person/secret.txt',
        context: ErrorDescription('사용자 입력 강남역 SYNTHETIC'),
        informationCollector: () => <DiagnosticsNode>[
          ErrorDescription('SYNTHETIC-information-leak'),
        ],
      );

      final sanitized = sanitizeFlutterErrorDetails(
        details,
        subsystem: CrashSubsystem.flutterFramework,
      );

      expect(sanitized.library, sanitizedCrashLibrary);
      expect(sanitized.informationCollector, isNull);
      expect(sanitized.context?.toDescription(), 'subsystem=flutter-framework');
      expect(sanitized.exceptionAsString(), isNot(contains('SYNTHETIC')));
    });
  });

  group('URL redaction', () {
    test('signed URL의 path와 query를 제거한다', () {
      const url =
          'https://storage.example.com/easysubway-reports/RPT-SYNTHETIC.jpg'
          '?X-Amz-Signature=synthetic0123456789abcdef&X-Amz-Expires=900';
      expect(
        redactSensitiveText(url),
        'https://storage.example.com/<redacted-path>?<redacted-query>',
      );
    });

    test('userinfo를 제거하고 host만 남긴다', () {
      expect(
        redactSensitiveText('https://admin:s3cret@api.example.com/v1/reports'),
        'https://<redacted-userinfo>@api.example.com/<redacted-path>',
      );
    });

    test('host만 있는 URL과 비-http scheme도 동일 규칙을 받는다', () {
      expect(
        redactSensitiveText('https://api.example.com'),
        'https://api.example.com',
      );
      expect(
        redactSensitiveText('gs://easysubway-bucket/2026/08/photo.jpg?sig=abc'),
        'gs://easysubway-bucket/<redacted-path>?<redacted-query>',
      );
    });

    test('package:·dart: URI는 심볼리케이션을 위해 보존한다', () {
      const frame = '#0      main (package:easysubway_mobile/main.dart:20:5)';
      expect(redactSensitiveText(frame), frame);
      const core = '#1      _rootRun (dart:async/zone.dart:1354:13)';
      expect(redactSensitiveText(core), core);
    });
  });

  group('filesystem path 정규화', () {
    test('개인 홈 경로를 지우고 소스 anchor 이후만 남긴다', () {
      expect(
        redactSensitiveText(
          'file:///Users/synthetic-person/dev/easysubway/apps/mobile/lib/'
          'facility_report.dart:12:3',
        ),
        'file://<redacted-path>/lib/facility_report.dart:12:3',
      );
      expect(
        redactSensitiveText(
          '/home/synthetic-person/work/app/lib/main.dart:1:1',
        ),
        '<redacted-path>/lib/main.dart:1:1',
      );
    });

    test('소스 파일이 아닌 경로·파일명은 통째로 폐기한다', () {
      expect(
        redactSensitiveText(
          '/Users/synthetic-person/Library/Containers/com.easysubway.app/Data/'
          'Documents/report-draft.txt',
        ),
        '<redacted-path>',
      );
      expect(
        redactSensitiveText(
          '/data/user/0/com.easysubway.app/cache/IMG_20260801_SYNTHETIC.jpg',
        ),
        '<redacted-path>',
      );
      expect(
        redactSensitiveText(
          '/var/mobile/Containers/Data/Application/2B7C-SYNTHETIC/Documents/x.txt',
        ),
        '<redacted-path>',
      );
      expect(
        redactSensitiveText(
          r'C:\Users\synthetic-person\AppData\Local\report.txt',
        ),
        '<redacted-path>',
      );
    });
  });

  group('stack trace shape allowlist', () {
    test('frame이 아닌 라인은 <redacted-frame>으로 치환한다', () {
      final sanitized = sanitizeStackTraceText(
        '#0      upload (package:easysubway_mobile/facility_report.dart:12:3)\n'
        'Authorization: Bearer SYNTHETIC-token-value\n'
        '#1      request (X-Amz-Signature=synthetic0123456789)\n'
        '<asynchronous suspension>',
      );

      expect(sanitized.split('\n'), <String>[
        '#0      upload (package:easysubway_mobile/facility_report.dart:12:3)',
        '<redacted-frame>',
        '<redacted-frame>',
        '<asynchronous suspension>',
      ]);
    });

    test('비-ASCII가 섞인 라인은 사용자 입력으로 보고 버린다', () {
      expect(
        sanitizeStackTraceText('#0      search (강남역 3번출구 검색어)'),
        '<redacted-frame>',
      );
    });

    test('심볼리케이션 필수 헤더(build_id·loading_unit)와 frame은 보존한다', () {
      const trace =
          '*** *** ***\n'
          "build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'\n"
          'isolate_dso_base: 7f1234, vm_dso_base: 7f1234\n'
          'loading_unit: 1\n'
          '    #00 abs 000000724d3a3f9b virt 00000000002f4f9b '
          '_kDartIsolateSnapshotInstructions+0x1e2f9b';
      expect(sanitizeStackTraceText(trace).split('\n'), <String>[
        '*** *** ***',
        "build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'",
        // dso_base는 Crashlytics 전송 대상이 아니라 폐기한다(비필수 헤더).
        '<redacted-frame>',
        'loading_unit: 1',
        '    #00 abs 000000724d3a3f9b virt 00000000002f4f9b '
            '_kDartIsolateSnapshotInstructions+0x1e2f9b',
      ]);
    });

    test('허용 라인 shape 뒤에 붙은 자격증명은 통과하지 못한다(finding #1)', () {
      const bearer =
          'Bearer eyJhbGciOiJIUzI1NiJ9.SYNTHETICpayload9f3a.SYNTHETICsig8b21';
      final shapes = <String, String>{
        'aot':
            '    #00 abs 000000724d3a3f9b virt 00000000002f4f9b '
            '_kDartIsolateSnapshotInstructions+0x1e2f9b',
        'jit':
            '#0      upload (package:easysubway_mobile/facility_report.dart:12:3)',
        'friendly': 'package:easysubway_mobile/main.dart 20:5 main',
        'os_header': 'os: android arch: arm64 comp: no sim: no',
        'build_id': "build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'",
        'loading_unit': 'loading_unit: 1',
      };
      shapes.forEach((name, shape) {
        final out = sanitizeStackTraceText('$shape $bearer');
        expect(out, isNot(contains('Bearer')), reason: name);
        expect(out, isNot(contains('eyJhbGci')), reason: name);
        expect(out, isNot(contains('SYNTHETIC')), reason: name);
      });
    });

    test('JIT frame member의 점 연결 자격증명(ya29·JWT)은 통과하지 못한다(finding #2)', () {
      // 실제 provider 형식과 어긋나게 만든 합성 더미. member 위치에 점 연결
      // 토큰을 심어 `_lineHasSecretToken`이 공백·쉼표로만 쪼개던 우회를 막는지 본다.
      const oauth = 'ya29.SYNTHETIC0oauth0access0token0not0real0000';
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJTWU5USEVUSUMifQ.SYNTHETICsig9f3a8b21';
      final lines = <String>[
        '#0      $oauth (package:easysubway_mobile/main.dart:1:1)',
        '#1      Authorization: Bearer $oauth '
            '(package:easysubway_mobile/main.dart:1:1)',
        '#2      $jwt (package:easysubway_mobile/main.dart:1:1)',
        '#3      Bearer $jwt (package:easysubway_mobile/main.dart:1:1)',
      ];
      for (final line in lines) {
        final out = sanitizeStackTraceText(line);
        expect(out, isNot(contains('ya29')), reason: line);
        expect(out, isNot(contains('eyJ')), reason: line);
        expect(out, isNot(contains('SYNTHETIC')), reason: line);
      }
    });

    test('AOT 헤더는 보존하되 인식 못 한 심볼 꼬리는 잘라낸다', () {
      // 주소(abs·virt)는 심볼리케이션에 필요하므로 남기고, 뒤에 붙은 임의
      // 문자열은 버린다.
      expect(
        sanitizeStackTraceText(
          '#00 abs 000000724d3a3f9b virt 00000000002f4f9b '
          'Authorization: Bearer SYNTHETICtoken12345',
        ),
        '#00 abs 000000724d3a3f9b virt 00000000002f4f9b',
      );
    });

    test('append 없는 정상 frame·필수 헤더는 그대로 보존한다', () {
      for (final line in <String>[
        '#0      main (package:easysubway_mobile/main.dart:20:5)',
        'package:easysubway_mobile/main.dart 20:5 main',
        "build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'",
        'loading_unit: 2',
      ]) {
        expect(sanitizeStackTraceText(line), line, reason: line);
      }
    });

    test('라인 수·라인 길이 상한을 적용한다', () {
      final many = List<String>.generate(
        200,
        (index) =>
            '#$index      main (package:easysubway_mobile/main.dart:1:1)',
      ).join('\n');
      final lines = sanitizeStackTraceText(many).split('\n');
      expect(lines, hasLength(maxSanitizedStackLines + 1));
      expect(lines.last, truncatedStackFramesToken);

      // 길이는 긴 package 경로에서 만든다(멤버를 길게 하면 hex/secret 판정에
      // 걸려 정상 truncation 경로를 검증하지 못한다).
      final longLine = sanitizeStackTraceText(
        '#0      main '
        '(package:easysubway_mobile/${List.filled(40, 'sub_dir/').join()}'
        'main.dart:1:1)',
      );
      expect(longLine.length, maxSanitizedStackLineLength);
      expect(longLine, endsWith('~trunc'));
    });

    test('멤버명이 비정상적으로 긴 frame은 shape allowlist에서 탈락한다', () {
      expect(
        sanitizeStackTraceText(
          '#0      ${List.filled(500, 'a').join()} '
          '(package:easysubway_mobile/main.dart:1:1)',
        ),
        redactedStackFrameToken,
      );
    });

    test('null stack은 빈 trace로 접는다', () {
      expect(sanitizeStackTrace(null).toString(), StackTrace.empty.toString());
    });
  });

  group('custom key allowlist', () {
    test('key마다 정해진 값 shape만 통과한다', () {
      expect(
        sanitizeCrashCustomKeyValue('app_version', '1.0.5+10006'),
        '1.0.5+10006',
      );
      expect(
        sanitizeCrashCustomKeyValue('crash_subsystem', 'app-report'),
        'app-report',
      );
      expect(
        sanitizeCrashCustomKeyValue('crash_error_code', 'API_REQUEST_FAILED'),
        'API_REQUEST_FAILED',
      );
      expect(
        sanitizeCrashCustomKeyValue('app_build_variant', 'release'),
        'release',
      );
      expect(sanitizeCrashCustomKeyValue('device_class', 'phone'), 'phone');
      expect(
        sanitizeCrashCustomKeyValue('os_class', 'android-34'),
        'android-34',
      );
    });

    test('allowlist 밖 key는 폐기한다', () {
      expect(sanitizeCrashCustomKeyValue('user_id', 'u-123'), isNull);
      expect(sanitizeCrashCustomKeyValue('latitude', '37.5665123'), isNull);
      expect(
        sanitizeCrashCustomKeyValue('report_receipt_token', 'rrt_x'),
        isNull,
      );
      expect(describeCrashCustomKeyName('user_id'), '<rejected-key>');
      expect(describeCrashCustomKeyName('app_version'), 'app_version');
    });

    test('allowlist key라도 값 shape·길이 기준을 어기면 폐기한다', () {
      expect(
        sanitizeCrashCustomKeyValue(
          'app_version',
          'Bearer eyJhbGciOi SYNTHETIC',
        ),
        isNull,
      );
      // 범용 charset 허용이었다면 통과했을 토큰 형태를 명시적으로 막는다.
      expect(
        sanitizeCrashCustomKeyValue(
          'crash_subsystem',
          'ya29.SYNTHETIC-oauth-access-token-not-real-0000',
        ),
        isNull,
      );
      expect(
        sanitizeCrashCustomKeyValue(
          'device_class',
          List.filled(maxCrashCustomKeyValueLength + 1, 'a').join(),
        ),
        isNull,
      );
      expect(
        sanitizeCrashCustomKeyValue(
          'crash_error_code',
          '4f8c9b21ae7d43f0ba62c15e8d37904a',
        ),
        isNull,
      );
      expect(sanitizeCrashCustomKeyValue('app_version', '강남역'), isNull);
      expect(
        sanitizeCrashCustomKeyValue('device_class', <String>['x']),
        isNull,
      );
    });

    test('device_class는 닫힌 집합만 통과하고 토큰형 자격증명은 거부한다(finding #2)', () {
      // 유한 열거만 허용.
      for (final value in crashDeviceClassAllowlist) {
        expect(sanitizeCrashCustomKeyValue('device_class', value), value);
      }
      // 이전 slug 정규식(^[a-z][a-z0-9-]{0,31}$)이었다면 통과했을 소문자 토큰들.
      expect(
        sanitizeCrashCustomKeyValue('device_class', 'akiaiosfodnn7example'),
        isNull,
      );
      expect(
        sanitizeCrashCustomKeyValue('device_class', 'ya29synthetictoken00'),
        isNull,
      );
      expect(sanitizeCrashCustomKeyValue('device_class', 'pixel8pro'), isNull);
    });
  });
}
