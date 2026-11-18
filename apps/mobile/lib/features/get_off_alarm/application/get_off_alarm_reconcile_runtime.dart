import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/user/user_database.dart';
import '../../../core/database/user/user_database_opener.dart';
import '../../notifications/notification_settings.dart';
import '../data/get_off_alarm_recovery_notice_store.dart';
import '../data/get_off_alarm_state_repository.dart';
import '../exact_alarm_permission.dart';
import '../get_off_alarm_controller.dart';
import '../get_off_alarm_notifier.dart';

/// Headless reconcile의 순수 오케스트레이션이다. 성공·예외와 무관하게
/// [close]를 실행하고, reconcile 예외는 fail-closed false로 바꾼다.
Future<bool> reconcileGetOffAlarmHeadless({
  required Future<void> Function() reconcile,
  required Future<void> Function() close,
  required void Function(Object error, StackTrace stackTrace) reportError,
}) async {
  try {
    await reconcile();
    return true;
  } on Object catch (error, stackTrace) {
    reportError(error, stackTrace);
    return false;
  } finally {
    await close();
  }
}

/// GetOffAlarm 내부의 프로덕션 DB·controller 조립 진입점이다.
/// 테스트 seam도 이 내부 경계에만 둔다.
Future<bool> runGetOffAlarmReconcileRuntime({
  required void Function(Object error, StackTrace stackTrace) reportError,
  required Future<void> Function() onActivateReconcileWork,
  required Future<void> Function() onDeactivateReconcileWork,
  Future<UserDatabase> Function() openUserDatabase = _openUserDatabase,
  GetOffAlarmController Function(UserDatabase userDatabase)? createController,
}) async {
  final userDatabase = await openUserDatabase();
  final controller =
      createController?.call(userDatabase) ??
      _createReconcileController(
        userDatabase,
        onActivateReconcileWork: onActivateReconcileWork,
        onDeactivateReconcileWork: onDeactivateReconcileWork,
      );
  return reconcileGetOffAlarmHeadless(
    reconcile: controller.reconcile,
    close: () async {
      controller.dispose();
      await userDatabase.close();
    },
    reportError: reportError,
  );
}

GetOffAlarmController _createReconcileController(
  UserDatabase userDatabase, {
  required Future<void> Function() onActivateReconcileWork,
  required Future<void> Function() onDeactivateReconcileWork,
}) {
  return GetOffAlarmController(
    notifier: LocalGetOffAlarmNotifier(FlutterLocalNotificationsPlugin()),
    permissionGate: PluginExactAlarmPermissionGate(
      FlutterLocalNotificationsPlugin(),
    ),
    notificationPermissionProvider:
        MethodChannelNotificationPermissionProvider(),
    repository: DriftGetOffAlarmStateRepository(userDatabase: userDatabase),
    recoveryNoticeStore: DriftGetOffAlarmRecoveryNoticeStore(
      userDatabase: userDatabase,
    ),
    onActivateReconcileWork: onActivateReconcileWork,
    onDeactivateReconcileWork: onDeactivateReconcileWork,
  );
}

Future<UserDatabase> _openUserDatabase() async {
  final supportDirectory = await getApplicationSupportDirectory();
  return UserDatabaseOpener(
    databaseDirectory: Directory(p.join(supportDirectory.path, 'user')),
  ).open();
}
