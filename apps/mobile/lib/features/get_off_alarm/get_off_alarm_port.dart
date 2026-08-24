import 'package:flutter/foundation.dart';

import 'get_off_alarm_schedule_mode.dart';
import 'get_off_alarm_scheduler.dart';
import 'get_off_alarm_subscription.dart';

/// 휴대전화 알림 권한 요청과 현재 상태 조회 경계.
abstract interface class NotificationPermissionProvider {
  Future<NotificationPermissionStatus> requestNotificationPermission();

  /// 시스템 설정의 현재 알림 권한만 읽고 프롬프트를 띄우지 않는다.
  Future<NotificationPermissionStatus> notificationPermissionStatus();
}

enum NotificationPermissionStatus { granted, denied }

/// 하차 알림의 현재 상태(화면 표시용).
@immutable
class GetOffAlarmState {
  const GetOffAlarmState({
    this.enabled = false,
    this.activeRouteId,
    this.activeJourneyIdentity,
    this.scheduleMode,
    this.inexactNotice,
    this.permissionNotice,
    this.scheduledCount = 0,
  });

  final bool enabled;
  final String? activeRouteId;
  final JourneyAlarmSubscriptionIdentity? activeJourneyIdentity;
  final GetOffAlarmScheduleMode? scheduleMode;
  final String? inexactNotice;
  final String? permissionNotice;
  final int scheduledCount;

  static const GetOffAlarmState off = GetOffAlarmState();
}

/// Journey가 선택 경로의 하차 알림을 제어하고 상태를 관찰하는 공개 경계.
abstract interface class GetOffAlarmPort implements Listenable {
  GetOffAlarmState get state;

  Future<void> enableJourney({
    required JourneyAlarmSubscriptionIdentity identity,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
  });

  Future<void> disable();

  Future<void> disableJourneyIfActive(
    JourneyAlarmSubscriptionIdentity identity,
  );
}
