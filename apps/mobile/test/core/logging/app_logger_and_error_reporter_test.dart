import 'package:easysubway_mobile/core/crashlytics/crashlytics_gateway.dart';
import 'package:easysubway_mobile/core/logging/app_logger.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _CapturedOutput extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}

class _UnprintableError {
  @override
  String toString() => throw StateError('cannot stringify');
}

class _NoopGateway extends NoopCrashlyticsGateway {}

void main() {
  tearDown(() {
    AppLogger.reset();
    replaceCrashlyticsGatewayForTest(const NoopCrashlyticsGateway());
  });

  group('AppLogger release console suppression & redaction', () {
    test('release 모드에서는 raw error·stackTrace 및 debugPrint 콘솔 출력을 차단한다', () {
      final originalDebugPrint = debugPrint;
      final printed = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          printed.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final releaseLogger = AppLogger.forTest(isReleaseMode: true);
      releaseLogger.d('debug secret Bearer synthetic-d');
      releaseLogger.i('info secret Bearer synthetic-i');
      releaseLogger.w(
        'warn Bearer synthetic-w',
        error: StateError('raw-release-error Bearer synthetic-err'),
        stackTrace: StackTrace.current,
        cause: 'cause /data/user/0/com.easysubway.app/secret.db',
      );
      releaseLogger.e(
        'error x-admin-token: synthetic-e',
        error: StateError('raw-release-fatal'),
        stackTrace: StackTrace.current,
      );

      expect(printed, isEmpty);

      final inspected = _CapturedOutput();
      final releaseWithHook = AppLogger.forTest(
        isReleaseMode: true,
        output: inspected,
      );
      releaseWithHook.e(
        'failed Bearer synthetic-tok /data/user/0/com.app/file.db',
        error: StateError('raw-error-must-not-appear'),
        stackTrace: StackTrace.fromString(
          '#0 boom (/Users/synthetic-person/secret.dart:1:1)',
        ),
      );
      final joined = inspected.lines.join('\n');
      expect(joined, isNot(contains('synthetic-tok')));
      expect(joined, isNot(contains('/data/user/0/')));
      expect(joined, isNot(contains('raw-error-must-not-appear')));
      expect(joined, isNot(contains('synthetic-person')));
      expect(joined, contains('<redacted-token>'));
      expect(joined, contains('<redacted-path>'));
    });

    test('debug 모드에서도 토큰·Authorization·query·내부 경로를 마스킹한다', () {
      final originalDebugPrint = debugPrint;
      final printed = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          printed.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final logger = AppLogger.forTest(isReleaseMode: false);
      AppLogger.replaceForTest(logger);
      appLog.d(
        'dbg Authorization: Bearer synthetic-bearer-1',
        cause: 'http://localhost:8080/v1?token=synthetic-q1',
        causeStackTrace: StackTrace.fromString(
          '#0 a (/Users/synthetic-person/app/secret.txt:10:2)',
        ),
      );
      appLog.i('info x-admin-token: synthetic-adm', error: _UnprintableError());
      appLog.w(
        'warn /data/user/0/com.easysubway.app/files/user.sqlite',
        error:
            'api_key=synthetic-k1 https://api.example.com/a?token=synthetic-t2',
        stackTrace: StackTrace.fromString(
          '#0 b (/data/user/0/com.easysubway.app/files/bad.txt:5:1)',
        ),
      );
      appLog.e(
        'err AIzaSy-SYNTHETIC-not-a-real-key',
        error: StateError('Bearer synthetic-err-bearer'),
        cause: '/Users/synthetic-person/Desktop/db.sqlite',
        causeStackTrace: StackTrace.fromString(
          '#0 c (/Users/synthetic-person/dev/foo.txt:1:1)',
        ),
      );

      final joined = printed.join('\n');
      expect(joined, isNot(contains('synthetic-bearer-1')));
      expect(joined, isNot(contains('synthetic-q1')));
      expect(joined, isNot(contains('synthetic-adm')));
      expect(joined, isNot(contains('synthetic-k1')));
      expect(joined, isNot(contains('synthetic-t2')));
      expect(joined, isNot(contains('synthetic-err-bearer')));
      expect(joined, isNot(contains('AIzaSy-SYNTHETIC-not-a-real-key')));
      expect(joined, isNot(contains('/data/user/0/')));
      expect(joined, isNot(contains('/Users/synthetic-person/')));
      expect(joined, contains('<redacted-token>'));
      expect(joined, contains('<redacted-path>'));
      expect(joined, contains('<unprintable>'));
    });
  });

  group('installMobileErrorHandlers release vs debug presentError', () {
    test('release 모드에서는 FlutterError.presentError와 콘솔 raw 출력이 차단된다', () async {
      final originalOnError = FlutterError.onError;
      final originalPlatformOnError = PlatformDispatcher.instance.onError;
      final originalPresentError = FlutterError.presentError;
      final originalDebugPrint = debugPrint;
      addTearDown(() {
        FlutterError.onError = originalOnError;
        PlatformDispatcher.instance.onError = originalPlatformOnError;
        FlutterError.presentError = originalPresentError;
        debugPrint = originalDebugPrint;
      });

      final presented = <FlutterErrorDetails>[];
      final printed = <String>[];
      FlutterError.presentError = presented.add;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          printed.add(message);
        }
      };

      replaceCrashlyticsGatewayForTest(_NoopGateway());
      AppLogger.replaceForTest(AppLogger.forTest(isReleaseMode: true));
      installMobileErrorHandlers(isReleaseMode: true);

      FlutterError.onError?.call(
        FlutterErrorDetails(
          exception: StateError('secret Bearer synthetic-release-token'),
          stack: StackTrace.fromString(
            '#0 main (/data/user/0/com.app/secret.txt:1:1)',
          ),
        ),
      );
      await pumpEventQueue();

      expect(presented, isEmpty);
      expect(printed, isEmpty);
    });

    test('debug 모드에서는 FlutterError.presentError가 유지된다', () async {
      final originalOnError = FlutterError.onError;
      final originalPlatformOnError = PlatformDispatcher.instance.onError;
      final originalPresentError = FlutterError.presentError;
      addTearDown(() {
        FlutterError.onError = originalOnError;
        PlatformDispatcher.instance.onError = originalPlatformOnError;
        FlutterError.presentError = originalPresentError;
      });

      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;
      replaceCrashlyticsGatewayForTest(_NoopGateway());
      installMobileErrorHandlers(isReleaseMode: false);

      FlutterError.onError?.call(
        FlutterErrorDetails(
          exception: StateError('debug-visible'),
          stack: StackTrace.current,
        ),
      );
      await pumpEventQueue();

      expect(presented, hasLength(1));
    });
  });
}
