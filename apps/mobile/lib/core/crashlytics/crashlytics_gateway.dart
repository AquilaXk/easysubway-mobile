import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics 전송 게이트웨이. 테스트·미초기화 환경은 no-op.
///
/// 이 인터페이스로 들어오는 값은 이미 정화된 payload여야 한다. 정화는
/// `mobile_crash_reporting.dart`가 단일 choke point로 수행한다.
abstract class CrashlyticsGateway {
  bool get isCollectionEnabled;

  Future<void> setCollectionEnabled(bool enabled);

  Future<void> recordFlutterFatalError(FlutterErrorDetails details);

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  });

  /// custom key 전송. allowlist 검증은 `setCrashCustomKey`가 선행한다.
  Future<void> setCustomKey(String key, String value);
}

class NoopCrashlyticsGateway implements CrashlyticsGateway {
  const NoopCrashlyticsGateway();

  @override
  bool get isCollectionEnabled => false;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {}

  @override
  Future<void> setCustomKey(String key, String value) async {}
}

class FirebaseCrashlyticsGateway implements CrashlyticsGateway {
  FirebaseCrashlyticsGateway({FirebaseCrashlytics? crashlytics})
    : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  @override
  bool get isCollectionEnabled => _crashlytics.isCrashlyticsCollectionEnabled;

  @override
  Future<void> setCollectionEnabled(bool enabled) {
    return _crashlytics.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) {
    return _crashlytics.recordFlutterFatalError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) {
    return _crashlytics.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
    );
  }

  @override
  Future<void> setCustomKey(String key, String value) {
    return _crashlytics.setCustomKey(key, value);
  }
}

CrashlyticsGateway crashlyticsGateway = const NoopCrashlyticsGateway();

@visibleForTesting
void replaceCrashlyticsGatewayForTest(CrashlyticsGateway gateway) {
  crashlyticsGateway = gateway;
}

@visibleForTesting
void resetCrashlyticsGateway() {
  crashlyticsGateway = const NoopCrashlyticsGateway();
}
