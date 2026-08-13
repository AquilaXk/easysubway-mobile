import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Colors;

import '../../route_draft/domain/route_draft.dart';
import '../domain/route_map_design_space.dart';
import 'route_map_transfer_marker.dart';
import 'station_fan_menu_geometry.dart';

/// #2109 팬 메뉴 배치 결과. build 경로(라벨·메뉴 Positioned)와 카메라 최소
/// 패닝이 같은 규칙을 소비하도록 단일 함수로 계산한다.
/// 두 경로가 배치식을 각각 하드코딩하면 한쪽만 바뀌었을 때 패닝 bbox와 실제
/// 렌더 위치가 어긋난다.
/// 팬 메뉴가 지도 소스 경계 등으로 카메라 패닝만으로 다 드러나지 않을 때, 배치
/// 함수가 화면 안으로 클램프할 여백. 카메라 최소 패닝의 margin과 동일 값이라
/// 두 경로가 같은 여백을 본다.
const double kFanMenuViewportMargin = 12.0;

class FanMenuPlacement {
  const FanMenuPlacement({
    required this.left,
    required this.top,
    required this.menuWidth,
    required this.menuHeight,
    required this.revealBounds,
  });

  /// 팬 메뉴 Positioned의 left/top.
  final double left;
  final double top;
  final double menuWidth;
  final double menuHeight;

  /// 화면 안에 들여야 하는 팬 메뉴 뷰포트 bbox(카메라 패닝 대상).
  final Rect revealBounds;
}

/// 팬 메뉴의 이상적 배치가 viewport를 벗어났을 때 화면 안으로 옮길 최소 offset.
/// Canvas camera는 이 값을 반대 방향의 source 이동으로 변환한다.
Offset fanMenuRevealOffset({required Rect menuRect, required Size viewport}) {
  final viewportRect = Offset.zero & viewport;
  const margin = kFanMenuViewportMargin;
  var dx = 0.0;
  var dy = 0.0;
  if (menuRect.left < viewportRect.left + margin) {
    dx = (viewportRect.left + margin) - menuRect.left;
  } else if (menuRect.right > viewportRect.right - margin) {
    dx = (viewportRect.right - margin) - menuRect.right;
  }
  if (menuRect.top < viewportRect.top + margin) {
    dy = (viewportRect.top + margin) - menuRect.top;
  } else if (menuRect.bottom > viewportRect.bottom - margin) {
    dy = (viewportRect.bottom - margin) - menuRect.bottom;
  }
  return Offset(dx, dy);
}

/// 역 노드 앵커의 뷰포트 좌표([stationPoint])로 팬 메뉴 배치를 계산한다(#2192 v3).
/// 항상 노드 위쪽에 배치하되, 말풍선 꼬리 팁([kFanMenuTailTip])이 넘겨받은
/// 앵커점에 닿도록 정렬한다(노드 위 8px 갭·flip 제거). 앵커점 자체는
/// [fanMenuTailAnchorPoint]가 정한다(#2068 QA: 노드 높이 2/3 지점). 지도 최상단
/// 역에서도 성립하도록 root canvas의 카메라 최소 패닝이 메뉴 높이만큼 상단
/// 헤드룸을 열어 노출한다.
///
/// 렌더와 카메라 패닝이 같은 viewport 기반 메뉴 크기를 사용한다. 렌더 경로는
/// [clampPosition]을 켜 극단 경계에서도 메뉴를 화면 안에 두고, 카메라 경로는
/// 끈 이상적 배치의 [FanMenuPlacement.revealBounds]를 노출 대상으로 사용한다.
@visibleForTesting
double fanMenuWidthForViewport(double viewportWidth) => math.min(
  220.0,
  math.max(0.0, viewportWidth - (kFanMenuViewportMargin * 2)),
);

FanMenuPlacement fanMenuPlacement({
  required Offset stationPoint,
  required Size viewport,
  required bool clampPosition,
}) {
  final menuWidth = fanMenuWidthForViewport(viewport.width);
  final menuHeight =
      menuWidth * (kFanMenuDesignSize.height / kFanMenuDesignSize.width);
  // 꼬리 팁(design 좌표 kFanMenuTailTip)이 앵커점에 오도록 배치.
  // 팁 x=350/700=중앙, 팁 y=375/380이므로 top은 노드에서 팁 높이만큼 위로 민다.
  var left =
      stationPoint.dx -
      menuWidth * (kFanMenuTailTip.dx / kFanMenuDesignSize.width);
  var top =
      stationPoint.dy -
      menuHeight * (kFanMenuTailTip.dy / kFanMenuDesignSize.height);
  if (clampPosition) {
    const margin = kFanMenuViewportMargin;
    final maxLeft = viewport.width - margin - menuWidth;
    if (maxLeft >= margin) {
      left = left.clamp(margin, maxLeft).toDouble();
    }
    final maxTop = viewport.height - margin - menuHeight;
    if (maxTop >= margin) {
      top = top.clamp(margin, maxTop).toDouble();
    }
  }
  return FanMenuPlacement(
    left: left,
    top: top,
    menuWidth: menuWidth,
    menuHeight: menuHeight,
    revealBounds: Rect.fromLTWH(left, top, menuWidth, menuHeight),
  );
}

/// 환승 캡슐의 시각 중심(source 좌표)을 렌더러와 동일 규칙으로 유도한다(#2192).
/// 팬 메뉴 앵커가 실제로 그려지는 캡슐 중심과 어긋나지 않도록
/// [routeMapTransferMarkers]를 그대로 재사용한다(모드 판정 독립 재유도 금지):
/// 스택·강등 스택은 평균, 스팬은 bounds 중심, separate는 탭한 멤버의 캡슐 중심.
///
/// [memberPositions]는 환승 그룹의 노선별 노드 좌표(source), [tappedPosition]은
/// 탭한 멤버의 좌표(source). 멤버가 2개 미만이면 일반역으로 보고 그대로 반환한다.
/// [designScale]은 렌더러가 모드 임계를 판정할 때 쓰는 값(source→design 배율)과
/// 동일해야 한다.
Offset fanMenuTransferAnchor({
  required List<Offset> memberPositions,
  required Offset tappedPosition,
  required double designScale,
}) {
  if (memberPositions.length < 2) {
    return tappedPosition;
  }
  final markers = routeMapTransferMarkers(
    memberCenters: memberPositions,
    // 캡슐 기하(중심)는 색과 무관하나 함수 계약상 길이가 멤버 수와 같아야 한다.
    colors: List<Color>.filled(memberPositions.length, Colors.transparent),
    designSpread: offsetsMaxPairwiseDistance(memberPositions) * designScale,
    dotRadius: kRouteMapTransferDotRadiusPx,
    dotGap: kRouteMapTransferDotGapPx,
    padding: kRouteMapTransferDotPaddingPx,
  );
  // 스택·강등 스택·스팬 모드는 단일 캡슐 → 그 중심. horizontalDots는 캡슐 중심에
  // 영향을 주지 않으므로 corridor 방향 계산 없이도 렌더 중심과 일치한다.
  if (markers.length == 1) {
    return markers.first.capsule.center;
  }
  // separate 모드: 멤버별 캡슐 → 탭한 멤버의 캡슐 중심(=탭 좌표).
  return tappedPosition;
}

/// 팬 메뉴 꼬리 팁이 닿을 앵커점(#2068 QA). 가로는 노드 정중앙 그대로, 세로는
/// **노드 바닥에서 높이의 2/3 위** 지점이다(= 노드 중심에서 위로 높이의 1/6).
/// 정중앙 접촉(#2192 v3)은 메뉴가 노드보다 살짝 위에 떠 보인다는 실기기 QA
/// 반려에 따라 이 지점으로 옮겼다.
///
/// 좌표계는 [nodeCenter]와 같은 단위를 쓴다. 호출부는 source 좌표를 넘기고
/// `MapCameraState.sourceToViewportPoint`가 카메라 배율을 적용한다. 드래프트 핀
/// (출발·경유·도착)은 이 이동을 쓰지 않고 노드 정중앙을 그대로 앵커로 둔다.
Offset fanMenuTailAnchorPoint({
  required Offset nodeCenter,
  required double nodeHeight,
}) => Offset(
  nodeCenter.dx,
  // 노드 바닥(중심 + 높이/2)에서 높이의 2/3만큼 위로 올라간 지점.
  nodeCenter.dy + nodeHeight / 2 - nodeHeight * 2 / 3,
);

/// [fanMenuTailAnchorPoint]가 쓰는 "노드"의 세로 크기(source 단위, #2068 QA).
///
/// 화면에 실제로 그려지는 바탕층(오너 SVG) 심벌의 실측 상수를 기준으로 한다
/// (구조화 심벌은 basemap 모드에서 렌더되지 않는다):
/// - 일반역: 심벌 지름 `2 × [kRouteMapBasemapStationNodeRadiusPx]`.
/// - 환승역 단일 캡슐(스택·스팬·강등 스택): 멤버 design bbox를 캡슐 반폭만큼
///   부풀린 rect의 height. 반폭은 캡슐 **장축이 세로일 때만**(bbox 세로 ≥ 가로)
///   멤버 수 기반 장축 하한([routeMapBasemapTransferCapsuleHalfWidthFor], 라벨
///   장애물과 같은 정본)을 쓰고, 가로 캡슐이면 두께
///   ([kRouteMapBasemapTransferCapsuleHalfWidthPx])를 쓴다 — 가로 캡슐에 장축
///   하한을 세로로 적용하면 세로 크기를 2배 가까이 과대평가한다.
/// - separate(대이격) 모드: 앵커가 탭한 배지 하나에 붙으므로 전체 bbox가 아니라
///   배지 두께(2×반폭)가 노드 높이다.
///
/// 모드 판정은 [fanMenuTransferAnchor]와 같이 [routeMapTransferMarkers] 결과
/// (마커 수)를 그대로 소비한다 — 임계를 독립 재유도하면 앵커 중심과 노드 높이가
/// 서로 다른 모드를 보게 된다. design px → source 환산은 [designScale]로 나눈다.
///
/// **권역 캘리브레이션(2026-07-26 오너 SVG 실측).** 위 상수들은 수도권 기준으로
/// 유도됐지만, 노드 크기는 source가 아니라 **design px에서** 권역 간 거의 일정해
/// (오너 SVG station-symbols-layer 지배 원 반경 × 권역 designScale: 수도권 3.10 ·
/// 부산 3.07 · 대구 3.57 · 대전 2.40 · 광주 2.70 design px) design px 상수를
/// 권역 designScale로 나누는 이 식이 전 권역에서 성립한다. 환승 캡슐 두께도
/// 같은 실측에서 8.3~11.0 design px 반폭으로 권역 간 일정하다(shell stroke-width
/// × designScale). 상수(노드 반경 4.5 · 캡슐 반폭 13)는 실측보다 보수적으로 크지만
/// 이동량이 `height/6`이라 팁은 전 권역에서 실제 노드 안에 머문다(최악 대전
/// 일반역: 이동 1.5 vs 실측 반높이 2.40 design px). 회귀 가드는
/// `network_map_fan_menu_wiring_test.dart`의 권역 실측 표 테스트다.
double fanMenuAnchorNodeHeight({
  required List<Offset> memberPositions,
  required double designScale,
}) {
  if (designScale <= 0) {
    return 0;
  }
  if (memberPositions.length < 2) {
    return (2 * kRouteMapBasemapStationNodeRadiusPx) / designScale;
  }
  final markers = routeMapTransferMarkers(
    memberCenters: memberPositions,
    // 캡슐 모드 판정은 색과 무관하나 함수 계약상 길이가 멤버 수와 같아야 한다.
    colors: List<Color>.filled(memberPositions.length, Colors.transparent),
    designSpread: offsetsMaxPairwiseDistance(memberPositions) * designScale,
    dotRadius: kRouteMapTransferDotRadiusPx,
    dotGap: kRouteMapTransferDotGapPx,
    padding: kRouteMapTransferDotPaddingPx,
  );
  if (markers.length != 1) {
    // separate: 배지 하나 → 장축이 없으므로 두께가 곧 높이.
    return (2 * kRouteMapBasemapTransferCapsuleHalfWidthPx) / designScale;
  }
  var bounds = Rect.fromCenter(
    center: memberPositions.first * designScale,
    width: 0,
    height: 0,
  );
  for (final position in memberPositions.skip(1)) {
    bounds = bounds.expandToInclude(
      Rect.fromCenter(center: position * designScale, width: 0, height: 0),
    );
  }
  // 캡슐 장축이 세로면(bbox 세로 ≥ 가로) 멤버 수 기반 장축 하한을, 가로면 두께를
  // 세로 반폭으로 쓴다 — 라벨 장애물은 방향 정보가 없어 장축 하한을 균등 inflate
  // 하지만(과대가 안전), 앵커는 과대가 곧 팁을 노드 밖으로 밀어내는 방향이다.
  final verticalHalfWidth = bounds.height >= bounds.width
      ? routeMapBasemapTransferCapsuleHalfWidthFor(memberPositions.length)
      : kRouteMapBasemapTransferCapsuleHalfWidthPx;
  return bounds.inflate(verticalHalfWidth).height / designScale;
}

/// 팬 메뉴 배선용: 탭한 역이 이미 배정된 슬롯 집합(진한 채움 selected).
Set<RouteDraftSlot> fanMenuSelectedSlots({
  required String stationId,
  required String? originStationId,
  required String? waypointStationId,
  required String? destinationStationId,
}) {
  return {
    if (stationId == originStationId) RouteDraftSlot.origin,
    if (stationId == waypointStationId) RouteDraftSlot.waypoint,
    if (stationId == destinationStationId) RouteDraftSlot.destination,
  };
}

/// 팬 메뉴 배선용: 탭한 섹터의 슬롯을 재탭(해제)할지 신규 배정할지 판정.
/// 탭한 역이 이미 그 슬롯에 배정돼 있으면([selectedSlots]에 포함) 재탭으로
/// 간주해 true(해제)를, 아니면 false(신규 배정)를 반환한다.
bool fanMenuShouldClear(
  RouteDraftSlot slot,
  Set<RouteDraftSlot> selectedSlots,
) {
  return selectedSlots.contains(slot);
}

/// 팬 메뉴 배선용: 같은 역이 다른 슬롯에 이미 있어 dim할 슬롯 집합.
/// 구 액션 오버레이의 originEnabled/waypointEnabled/destinationEnabled 규칙을
/// 그대로 이식(자기 슬롯 재지정은 dim 아님).
Set<RouteDraftSlot> fanMenuDisabledSlots({
  required String stationId,
  required String? originStationId,
  required String? waypointStationId,
  required String? destinationStationId,
}) {
  final originEnabled =
      stationId != waypointStationId && stationId != destinationStationId;
  final waypointEnabled =
      stationId != originStationId && stationId != destinationStationId;
  final destinationEnabled =
      stationId != originStationId && stationId != waypointStationId;
  return {
    if (!originEnabled) RouteDraftSlot.origin,
    if (!waypointEnabled) RouteDraftSlot.waypoint,
    if (!destinationEnabled) RouteDraftSlot.destination,
  };
}
