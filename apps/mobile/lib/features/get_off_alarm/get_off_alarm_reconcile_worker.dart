import 'dart:io';

import 'package:workmanager_android/workmanager_android.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'application/get_off_alarm_reconcile_runtime.dart';

/// GetOffAlarm이 공개하는 typed background command의 task identity다.
const getOffAlarmReconcileTask = 'getOffAlarmReconcile';
const getOffAlarmReconcileUniqueName = 'get-off-alarm-reconcile';
const getOffAlarmReconcileFrequency = Duration(minutes: 15);

/// 활성 구독 저장/재예약 시 unique periodic reconcile work를 등록/update한다.
/// WorkManager initialize는 app bootstrap의 단일 dispatcher가 소유한다.
Future<void> registerGetOffAlarmReconcile() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().registerPeriodicTask(
    getOffAlarmReconcileUniqueName,
    getOffAlarmReconcileTask,
    frequency: getOffAlarmReconcileFrequency,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}

/// off·만료·알림 권한 거부 정리 시 하차 알림 unique work만 취소한다.
Future<void> cancelGetOffAlarmReconcile() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().cancelByUniqueName(getOffAlarmReconcileUniqueName);
}

/// 다른 feature가 사용할 수 있는 작은 typed application command다.
/// DB·controller·plugin 조립은 GetOffAlarm 내부 runtime에만 남긴다.
Future<bool> runGetOffAlarmReconcileTask({
  required void Function(Object error, StackTrace stackTrace) reportError,
}) {
  return runGetOffAlarmReconcileRuntime(
    reportError: reportError,
    onActivateReconcileWork: registerGetOffAlarmReconcile,
    onDeactivateReconcileWork: cancelGetOffAlarmReconcile,
  );
}
