import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 상단바와 알림 바가 지도 위를 덮는 영역의 아래 끝(화면 좌표).
double networkMapOverlayBottomOf(WidgetTester tester) {
  final noticeBar = find.byKey(const Key('newNotificationBar'));
  return noticeBar.evaluate().isEmpty
      ? tester.getRect(find.byKey(const Key('networkMapTopBar'))).bottom
      : tester.getRect(noticeBar).bottom;
}

/// 지도 본문 위쪽이 상단바·알림 바에 가려지는 실제 높이(화면에 그려진 사각형 기준).
double networkMapObscuredTopOf(WidgetTester tester) {
  final surface = tester.getRect(find.byKey(const Key('networkMapSurface')));
  return (networkMapOverlayBottomOf(tester) - surface.top).clamp(
    0.0,
    double.infinity,
  );
}

/// 지도 본문 중 오버레이에 가려지지 않는 영역의 세로 중앙(화면 좌표).
double networkMapVisibleCenterYOf(WidgetTester tester) {
  final surface = tester.getRect(find.byKey(const Key('networkMapSurface')));
  return (networkMapOverlayBottomOf(tester) + surface.bottom) / 2;
}

/// [sourcePoint]가 [camera] 화면에서 상단 오버레이에 가려지지 않는 영역의 중앙에 온다.
void expectAtVisibleCenter(
  WidgetTester tester,
  MapCameraState camera,
  Offset sourcePoint,
) {
  final obscuredTop = networkMapObscuredTopOf(tester);
  final onScreen = camera.sourceToViewportPoint(sourcePoint);
  expect(onScreen.dx, closeTo(camera.viewportSize.width / 2, 0.5));
  expect(
    onScreen.dy,
    closeTo(obscuredTop + (camera.viewportSize.height - obscuredTop) / 2, 0.5),
    reason: '가려진 높이 $obscuredTop 아래 보이는 영역의 중앙이어야 한다',
  );
}
