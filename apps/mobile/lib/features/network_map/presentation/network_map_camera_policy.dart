import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../domain/map_camera.dart';
import '../domain/route_map_design_space.dart';
import '../domain/route_map_min_scale.dart';
import '../domain/route_map_owner_labels.dart';
import 'network_map_draft_pin.dart';

const _fallbackMinMapScale = 0.08;
const _maxMapScale = 4.8;
const _stationFocusInitialBoundsFraction = 0.72;
const double _initialCameraReadableLabelScreenPx = kRouteMapDesignLabelFontPx;

/// 카메라 center가 source 경계 밖으로 나갈 수 있는 화면 여유(dp). 제스처와
/// 프로그램 패닝이 같은 여유를 써야 한쪽이 옮긴 카메라를 다른 쪽이 되돌리지 않는다.
const kNetworkMapCameraViewportMargin = 220.0;

/// Gesture 중 새 renderer frame을 요청하는 최대 대기 간격.
const kNetworkMapRendererCommitInterval = Duration(milliseconds: 1100);

const _routeMapGestureMaxTranslationDriftFraction = 1.35;
const _routeMapGestureMaxScaleRatio = 3.4;
const _routeMapGestureRendererOverscanFactor = 3.25;
const _smallRegionStationCountThreshold = 40;

/// 카메라 center가 source 경계 밖으로 나갈 수 있는 여유(dp)의 유일한 출처.
/// 초기·포커스·제스처·reveal이 모두 이 값을 써야 한 경로가 옮긴 카메라를 다른 경로의
/// clamp가 되돌려 핀과 대상을 다시 가리지 않는다. 오버레이가 높을수록 중심을 위로
/// 올리거나 핀을 내려야 하므로 가려진 높이와 핀 높이만큼 여유를 더 준다.
double networkMapCameraClampMargin(double obscuredTop) => math.max(
  kNetworkMapCameraViewportMargin,
  obscuredTop + NetworkMapDraftPin.extentAboveAnchor,
);

/// 카메라 계산에 쓸 수 있는 가려진 높이.
///
/// 오버레이가 뷰포트 전체 이상을 덮으면(낮은 가로 화면 + 3줄 상단바 + 알림 바)
/// 가시 영역이 없어 가림 보정이 의미가 없다. 이때는 보정을 생략하고 전체 뷰포트를
/// 기준으로 fit한다. 지도가 보여야 한다는 것이 불변식이고, 높이를 추정해 덮는 값이
/// 아니라 "보정하지 않음"이다. 빈 카메라를 만들면 layoutKey가 높이를 담지 않아 오버레이가
/// 줄어든 뒤에도 지도가 계속 빈다.
double networkMapUsableObscuredTop(double obscuredTop, double viewportHeight) =>
    obscuredTop < viewportHeight ? obscuredTop : 0;

/// 상단 오버레이가 [obscuredTop]만큼 덮을 때, 가려지지 않는 영역의 중앙에
/// [target]이 오도록 하는 카메라 중심. 카메라 중심은 뷰포트 전체의 중앙이므로
/// 가시 영역 중앙(전체 중앙보다 [obscuredTop]/2 아래)에 맞추려면 그만큼 위로 둔다.
Offset networkMapCameraCenterForVisibleCenter(
  Offset target, {
  required double scale,
  required double obscuredTop,
}) => target - Offset(0, obscuredTop / 2 / scale);

/// [obscuredTop]은 뷰포트 위쪽이 상단 오버레이에 덮이는 높이다([networkMapUsableObscuredTop]
/// 규칙 적용). fit과 중심은 덮이지 않는 영역을 기준으로 계산하고, [MapCameraState.viewportSize]는 뷰포트
/// 전체로 둔다.
MapCameraState networkMapCameraForBounds(
  Rect bounds,
  BoxConstraints constraints, {
  required Rect sourceBounds,
  bool contain = false,
  double minScale = _fallbackMinMapScale,
  int revision = 0,
  double? initialScaleOverride,
  double obscuredTop = 0,
}) {
  final viewportWidth = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : 0.0;
  final viewportHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : 0.0;
  final usableObscuredTop = networkMapUsableObscuredTop(
    obscuredTop,
    viewportHeight,
  );
  final visibleHeight = viewportHeight - usableObscuredTop;
  if (viewportWidth <= 0 || viewportHeight <= 0) {
    return MapCameraState(
      sourceBounds: sourceBounds,
      viewportSize: Size.zero,
      center: sourceBounds.center,
      scale: minScale,
      minScale: minScale,
      maxScale: _maxMapScale,
      revision: revision,
      initialScale: initialScaleOverride ?? minScale,
    );
  }
  final widthScale = viewportWidth / bounds.width;
  final heightScale = visibleHeight / bounds.height;
  final computedScale = contain
      ? math.min(widthScale, heightScale)
      : math.max(widthScale, heightScale);
  final fitScale = computedScale.clamp(minScale, _maxMapScale).toDouble();
  return MapCameraState(
    sourceBounds: sourceBounds,
    viewportSize: Size(viewportWidth, viewportHeight),
    center: networkMapCameraCenterForVisibleCenter(
      bounds.center,
      scale: fitScale,
      obscuredTop: usableObscuredTop,
    ),
    scale: fitScale,
    minScale: minScale,
    maxScale: _maxMapScale,
    revision: revision,
    initialScale: initialScaleOverride ?? fitScale,
  ).clamped(viewportMargin: networkMapCameraClampMargin(usableObscuredTop));
}

/// 지역 초기 화면 카메라의 contain-fit과 baseline scale을 함께 고정한다.
@visibleForTesting
MapCameraState networkMapInitialCameraForRegion({
  required Rect regionBounds,
  required Rect fullBounds,
  required Size viewport,
  double? minScale,
}) {
  return networkMapCameraForBounds(
    regionBounds,
    BoxConstraints.tightFor(width: viewport.width, height: viewport.height),
    sourceBounds: fullBounds,
    contain: true,
    minScale: minScale ?? _fallbackMinMapScale,
  );
}

/// 역 focus를 지역 초기 화면보다 1/0.72배(약 1.39배) 확대하되 max scale을 보존한다.
@visibleForTesting
MapCameraState networkMapStationFocusCameraForRegion({
  required Rect initialBounds,
  required Offset stationCenter,
  required Rect fullBounds,
  required Size viewport,
  double? initialScaleOverride,
  double? minScale,
}) {
  return networkMapCameraForBounds(
    networkMapStationFocusBounds(
      initialBounds: initialBounds,
      center: stationCenter,
      sourceWidth: fullBounds.width,
      sourceHeight: fullBounds.height,
    ),
    BoxConstraints.tightFor(width: viewport.width, height: viewport.height),
    sourceBounds: fullBounds,
    contain: true,
    minScale: minScale ?? _fallbackMinMapScale,
    initialScaleOverride: initialScaleOverride,
  );
}

/// 저장형·표시형 권역명에 같은 오너 실측 축소 하한을 적용한다.
double networkMapMinimumScaleForRegion(
  String region, {
  double? initialFitScale,
}) {
  return routeMapMinimumScale(
    region: region,
    maxScale: _maxMapScale,
    initialFitScale: initialFitScale,
  );
}

/// [bounds]를 [constraints]에 contain-fit할 때의 유효한 양수 배율.
double? networkMapContainFitScale(Rect bounds, BoxConstraints constraints) {
  final viewportWidth = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : 0.0;
  final viewportHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : 0.0;
  if (viewportWidth <= 0 ||
      viewportHeight <= 0 ||
      bounds.width <= 0 ||
      bounds.height <= 0) {
    return null;
  }
  final fitScale = math.min(
    viewportWidth / bounds.width,
    viewportHeight / bounds.height,
  );
  return fitScale.isFinite && fitScale > 0 ? fitScale : null;
}

MapCameraState networkMapCameraWithMonotonicRevision({
  required MapCameraState current,
  required MapCameraState next,
}) {
  if (next.revision > current.revision) {
    return next;
  }
  return next.copyWith(revision: current.revision + 1);
}

bool networkMapShouldCommitRendererCamera({
  required MapCameraState committed,
  required MapCameraState candidate,
  required Duration elapsedSinceLastCommit,
}) {
  if (elapsedSinceLastCommit >= kNetworkMapRendererCommitInterval) {
    return true;
  }
  final scaleRatio = candidate.scale / committed.scale;
  if (scaleRatio >= _routeMapGestureMaxScaleRatio ||
      scaleRatio <= 1 / _routeMapGestureMaxScaleRatio) {
    return true;
  }
  final viewportCenter = candidate.viewportSize.center(Offset.zero);
  final committedCandidateCenter = committed.sourceToViewportPoint(
    candidate.center,
  );
  final drift = committedCandidateCenter - viewportCenter;
  return drift.dx.abs() >=
          candidate.viewportSize.width *
              _routeMapGestureMaxTranslationDriftFraction ||
      drift.dy.abs() >=
          candidate.viewportSize.height *
              _routeMapGestureMaxTranslationDriftFraction;
}

MapCameraState networkMapOverscannedRendererCamera(MapCameraState camera) {
  final overscanScale = math.max(
    camera.minScale,
    camera.scale / _routeMapGestureRendererOverscanFactor,
  );
  return camera.copyWith(scale: overscanScale).clamped(viewportMargin: 220);
}

bool networkMapRendererCameraCoversVisual({
  required MapCameraState rendererCamera,
  required MapCameraState visualCamera,
}) {
  const tolerance = 0.001;
  final rendererRect = rendererCamera.visibleSourceRect;
  final visualRect = visualCamera.visibleSourceRect;
  return rendererRect.left <= visualRect.left + tolerance &&
      rendererRect.top <= visualRect.top + tolerance &&
      rendererRect.right >= visualRect.right - tolerance &&
      rendererRect.bottom >= visualRect.bottom - tolerance;
}

MapCameraState? networkMapRendererCommitBasisCamera({
  required MapCameraState? presentedCamera,
  required MapCameraState? requestedCamera,
  required MapCameraState visualCamera,
}) {
  if (requestedCamera != null &&
      networkMapRendererCameraCoversVisual(
        rendererCamera: requestedCamera,
        visualCamera: visualCamera,
      )) {
    return requestedCamera;
  }
  return presentedCamera ?? requestedCamera;
}

MapCameraState networkMapRendererCameraForSkippedCommit({
  required MapCameraState? requestedCamera,
  required MapCameraState candidateCamera,
  required MapCameraState visualCamera,
}) {
  if (requestedCamera != null &&
      networkMapRendererCameraCoversVisual(
        rendererCamera: requestedCamera,
        visualCamera: visualCamera,
      )) {
    return requestedCamera;
  }
  return candidateCamera;
}

@visibleForTesting
bool networkMapShouldAcceptPresentedRendererRevision({
  required int revision,
  required MapCameraState? presentedCamera,
  required MapCameraState? requestedCamera,
}) {
  final presentedRevision = presentedCamera?.revision;
  if (presentedRevision != null && revision < presentedRevision) {
    return false;
  }
  final requestedRevision = requestedCamera?.revision;
  if (requestedRevision != null && revision < requestedRevision) {
    return false;
  }
  return true;
}

MapCameraState networkMapRendererTransformVisualCamera({
  required MapCameraState rendererCamera,
  required MapCameraState visualCamera,
}) {
  return networkMapRendererCameraCoversVisual(
        rendererCamera: rendererCamera,
        visualCamera: visualCamera,
      )
      ? visualCamera
      : rendererCamera;
}

Matrix4 networkMapRendererFrameTransform({
  required MapCameraState rendererCamera,
  required MapCameraState visualCamera,
}) {
  return visualCamera.sourceToViewport
    ..multiply(rendererCamera.viewportToSource);
}

/// 역 수 40 이하 지역은 초기 bounds 기준선을 지역 전체로 둔다.
bool networkMapUsesWholeRegionInitialView(int stationCount) =>
    stationCount <= _smallRegionStationCountThreshold;

/// 실제 역과 매칭되는 오너 라벨 중앙값으로 읽기 가능한 초기 배율을 구한다.
double? networkMapReadableInitialMapScale({
  required Map<String, List<RouteMapOwnerLabelEntry>> ownerLabelsByStationName,
  required Set<String> stationNames,
}) {
  final matched = <double>[
    for (final entry in ownerLabelsByStationName.entries)
      if (stationNames.contains(entry.key))
        for (final label in entry.value)
          if (label.fontSizePx > 0) label.fontSizePx,
  ];
  final sizes =
      (matched.isNotEmpty
            ? matched
            : <double>[
                for (final entries in ownerLabelsByStationName.values)
                  for (final label in entries)
                    if (label.fontSizePx > 0) label.fontSizePx,
              ])
        ..sort();
  if (sizes.isEmpty) {
    return null;
  }
  return _initialCameraReadableLabelScreenPx / sizes[sizes.length ~/ 2];
}

/// 기존 contain-fit보다 축소하지 않으면서 콘텐츠 중앙을 읽기 배율로 맞춘다.
Rect networkMapInitialCameraBounds({
  required Rect fullBounds,
  required Rect regionInitialBounds,
  required Size viewport,
  required double? readableScale,
}) {
  if (viewport.width <= 0 ||
      viewport.height <= 0 ||
      regionInitialBounds.width <= 0 ||
      regionInitialBounds.height <= 0) {
    return regionInitialBounds;
  }
  final containFitScale = math.min(
    viewport.width / regionInitialBounds.width,
    viewport.height / regionInitialBounds.height,
  );
  if (!containFitScale.isFinite || containFitScale <= 0) {
    return regionInitialBounds;
  }
  final targetScale = math.max(
    containFitScale,
    math.min(readableScale ?? 0.0, _maxMapScale),
  );
  return Rect.fromCenter(
    center: fullBounds.center,
    width: viewport.width / targetScale,
    height: viewport.height / targetScale,
  );
}

@visibleForTesting
Rect networkMapInitialOriginalAssetBounds({
  required double sourceWidth,
  required double sourceHeight,
}) {
  final width = sourceWidth * 0.58;
  final height = sourceHeight * 0.58;
  return _sourceCenteredBounds(
    center: Offset(sourceWidth / 2, sourceHeight / 2),
    width: width,
    height: height,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );
}

/// 초기 bounds를 두 축 모두 0.72배로 줄이고 지도 내부로 이동한다.
Rect networkMapStationFocusBounds({
  required Rect initialBounds,
  required Offset center,
  required double sourceWidth,
  required double sourceHeight,
}) {
  final width = math.min(
    sourceWidth,
    initialBounds.width * _stationFocusInitialBoundsFraction,
  );
  final height = math.min(
    sourceHeight,
    initialBounds.height * _stationFocusInitialBoundsFraction,
  );
  return _sourceCenteredBounds(
    center: center,
    width: width,
    height: height,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );
}

Rect _sourceCenteredBounds({
  required Offset center,
  required double width,
  required double height,
  required double sourceWidth,
  required double sourceHeight,
}) {
  final clampedWidth = width.clamp(1.0, sourceWidth).toDouble();
  final clampedHeight = height.clamp(1.0, sourceHeight).toDouble();
  final maxLeft = math.max(0.0, sourceWidth - clampedWidth);
  final maxTop = math.max(0.0, sourceHeight - clampedHeight);
  final left = (center.dx - clampedWidth / 2).clamp(0.0, maxLeft).toDouble();
  final top = (center.dy - clampedHeight / 2).clamp(0.0, maxTop).toDouble();
  return Rect.fromLTWH(left, top, clampedWidth, clampedHeight);
}

/// 지도 위쪽 [obscuredTop]만큼을 덮는 오버레이(상단바·알림 바) 아래로 [anchorPoints]
/// 위젯이 모두 들어오도록, 화면 내용을 아래로 밀어야 하는 거리(dp, 0 이상)를 구한다.
///
/// 앵커는 뷰포트 좌표이고 위젯은 앵커에서 위로 [extentAboveAnchor]만큼 뻗는다.
/// 가려진 위젯이 없으면 0이다. 한쪽으로 몰린 위젯이 아래 경계를 넘지 않도록 가장
/// 아래 앵커가 [viewportHeight]에 닿는 만큼까지만 민다.
double networkMapRevealOffsetBelowObscuredTop({
  required Iterable<Offset> anchorPoints,
  required double extentAboveAnchor,
  required double viewportHeight,
  required double obscuredTop,
}) {
  if (anchorPoints.isEmpty) {
    return 0;
  }
  final topmostEdge =
      anchorPoints.map((point) => point.dy).reduce(math.min) -
      extentAboveAnchor;
  final needed = obscuredTop - topmostEdge;
  if (needed <= 0) {
    return 0;
  }
  final lowestAnchor = anchorPoints.map((point) => point.dy).reduce(math.max);
  return math.min(needed, math.max(0.0, viewportHeight - lowestAnchor));
}
