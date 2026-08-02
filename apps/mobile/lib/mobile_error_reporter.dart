import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/crashlytics/crash_report_redaction.dart';
import 'core/crashlytics/mobile_crash_reporting.dart';
import 'core/logging/app_logger.dart';

typedef MobileErrorReporter = void Function(FlutterErrorDetails details);

const _mobileErrorReporterZoneKey = #easysubwayMobileErrorReporter;

void reportMobileError(
  Object error,
  StackTrace stackTrace, {
  required String context,
}) {
  final details = FlutterErrorDetails(
    exception: error,
    stack: stackTrace,
    library: 'easysubway mobile',
    context: ErrorDescription(context),
  );

  final zoneReporter = Zone.current[_mobileErrorReporterZoneKey];
  if (zoneReporter is MobileErrorReporter) {
    zoneReporter(details);
    return;
  }

  FlutterError.reportError(details);
}

Future<T> runWithMobileErrorReporter<T>(
  MobileErrorReporter reporter,
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_mobileErrorReporterZoneKey: reporter});
}

/// 전역 핸들러 3면 배선. 기존 `runWithMobileErrorReporter` zone 계약은 유지한다.
void installMobileErrorHandlers() {
  FlutterError.onError = (details) {
    final zoneReporter = Zone.current[_mobileErrorReporterZoneKey];
    if (zoneReporter is MobileErrorReporter) {
      zoneReporter(details);
      return;
    }

    // 로그 채널도 denylist 대상이라 원문 예외·stack을 그대로 넘기지 않는다.
    // debug 원문은 아래 `FlutterError.presentError`가 그대로 콘솔에 남긴다.
    final logReport = sanitizeCrashReport(
      details.exception,
      details.stack,
      fatal: true,
      subsystem: CrashSubsystem.flutterFramework,
    );
    appLog.e(logReport.message, stackTrace: logReport.stackTrace);
    // 미초기화·테스트 환경에서도 예외를 던지지 않는다.
    // Crashlytics Future 실패가 PlatformDispatcher.onError로 재진입하지 않게 흡수한다.
    unawaited(_recordCrashlyticsSafely(recordFatalFlutterError(details)));
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    final zoneReporter = Zone.current[_mobileErrorReporterZoneKey];
    if (zoneReporter is MobileErrorReporter) {
      zoneReporter(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'easysubway mobile',
          context: ErrorDescription('PlatformDispatcher.onError'),
        ),
      );
      return true;
    }

    final logReport = sanitizeCrashReport(
      error,
      stack,
      fatal: true,
      subsystem: CrashSubsystem.platformDispatcher,
    );
    appLog.e(logReport.message, stackTrace: logReport.stackTrace);
    unawaited(
      _recordCrashlyticsSafely(
        recordFatalError(
          error,
          stack,
          subsystem: CrashSubsystem.platformDispatcher,
        ),
      ),
    );
    return true;
  };
}

Future<void> _recordCrashlyticsSafely(Future<void> recording) async {
  try {
    await recording;
  } catch (error, stackTrace) {
    // 기록 경로 자체 실패는 전역 핸들러 루프를 만들지 않는다.
    appLog.w(
      'Crashlytics record failed; swallowed to avoid handler re-entry',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
