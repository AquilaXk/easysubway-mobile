import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'crash_report_redaction.dart';
import 'crashlytics_gateway.dart';

/// Firebase Crashlytics 초기화. 키 파일·플랫폼 미구성 시 예외 없이 no-op.
Future<bool> initializeMobileCrashReporting({
  bool isReleaseMode = kReleaseMode,
  Future<void> Function()? ensureFirebaseReady,
  CrashlyticsGateway Function()? createGateway,
}) async {
  try {
    if (ensureFirebaseReady != null) {
      await ensureFirebaseReady();
    } else {
      await Firebase.initializeApp();
    }
    final gateway = createGateway?.call() ?? FirebaseCrashlyticsGateway();
    crashlyticsGateway = gateway;
    // debug/profile에서는 전송 비활성. release만 수집.
    await gateway.setCollectionEnabled(isReleaseMode);
    appLog.i(
      'Crashlytics collection enabled=${gateway.isCollectionEnabled} '
      '(release=$isReleaseMode)',
    );
    return true;
  } catch (error, stackTrace) {
    crashlyticsGateway = const NoopCrashlyticsGateway();
    // 초기화 실패 원문에도 키 파일 경로·구성값이 섞일 수 있어 정화해 남긴다.
    final report = sanitizeCrashReport(
      error,
      stackTrace,
      fatal: false,
      subsystem: CrashSubsystem.crashReporting,
    );
    appLog.w(
      'Crashlytics unavailable; continuing without crash reporting. '
      '${report.message}',
      stackTrace: report.stackTrace,
    );
    return false;
  }
}

/// Flutter framework 경로(fatal). details 전체를 정화해 전송한다.
Future<void> recordFatalFlutterError(
  FlutterErrorDetails details, {
  CrashSubsystem subsystem = CrashSubsystem.flutterFramework,
}) {
  return crashlyticsGateway.recordFlutterFatalError(
    sanitizeFlutterErrorDetails(details, subsystem: subsystem),
  );
}

/// platform/async 경로(fatal).
Future<void> recordFatalError(
  Object error,
  StackTrace stackTrace, {
  CrashSubsystem subsystem = CrashSubsystem.unknown,
}) {
  return _recordSanitizedError(
    error,
    stackTrace,
    fatal: true,
    subsystem: subsystem,
  );
}

/// 앱이 자체 처리한 오류(nonfatal). fatal 경로와 동일한 정화를 거친다.
Future<void> recordNonFatalError(
  Object error,
  StackTrace stackTrace, {
  CrashSubsystem subsystem = CrashSubsystem.appReport,
}) {
  return _recordSanitizedError(
    error,
    stackTrace,
    fatal: false,
    subsystem: subsystem,
  );
}

/// custom key 전송. allowlist 밖 key·값은 전송하지 않고 폐기한다(fail-closed).
Future<void> setCrashCustomKey(String key, Object value) async {
  final sanitized = sanitizeCrashCustomKeyValue(key, value);
  if (sanitized == null) {
    appLog.w(
      'Crashlytics custom key rejected by allowlist: '
      '${describeCrashCustomKeyName(key)}',
    );
    return;
  }
  await crashlyticsGateway.setCustomKey(key, sanitized);
}

Future<void> _recordSanitizedError(
  Object error,
  StackTrace stackTrace, {
  required bool fatal,
  required CrashSubsystem subsystem,
}) {
  final report = sanitizeCrashReport(
    error,
    stackTrace,
    fatal: fatal,
    subsystem: subsystem,
  );
  return crashlyticsGateway.recordError(
    report.exception,
    report.stackTrace,
    fatal: fatal,
    reason: report.reason,
  );
}
