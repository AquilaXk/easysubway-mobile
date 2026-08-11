/// 휴대전화 알림 권한 요청과 현재 상태 조회 경계.
abstract class NotificationPermissionProvider {
  Future<NotificationPermissionStatus> requestNotificationPermission();

  /// 시스템 설정의 현재 알림 권한만 읽고 프롬프트를 띄우지 않는다.
  Future<NotificationPermissionStatus> notificationPermissionStatus();
}

enum NotificationPermissionStatus { granted, denied }
