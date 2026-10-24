import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../domain/map_camera.dart';
import '../domain/route_map_line_overlay_index.dart';

// 하이브리드 노선도 바탕층(#2068 트랙 2번째 PR).
//
// 오너 자작 SVG를 build-time 컴파일한 .vec(vector_graphics 바이너리)를 런타임
// 디코드해 바탕 [ui.Picture]를 얻고, 매 프레임은 카메라 transform + drawPicture만
// 재생한다. .vec의 좌표계는 원본 SVG viewBox(예: sma-v2 `0 0 2400 1800`)를 그대로
// 유지하므로, 인터랙션 좌표(station.position = route_map_positions)와 동일 원점·
// 동일 스케일이다 → designScale 곱셈/나눗셈 없이 카메라 변환만으로 1:1 정렬한다.
//
// [설계 결정: 병존] 이 위젯은 노선 형상과 오너 SVG의 기존 역·환승 심벌을 그리고,
// 구조화 painter는 충돌 회피 역명·뱃지를 같은 카메라 좌표계에 그린다.
// SVG의 제목·범례·역명·미개통 형상은 컴파일 입력에서 제외한다.

/// `widget.data.selectedRegion`(한글) → manifest map id. .vec 자산 파일명 결정.
/// 매핑에 없는 region은 basemap 미표시(빈 화면)로 안전 폴백한다(크래시 금지).
const Map<String, String> kRouteMapBasemapRegionToId = {
  '수도권': 'seoul',
  '부산': 'busan',
  '광주': 'gwangju',
  '대구': 'daegu',
  '대전': 'daejeon',
};

/// region → .vec 자산 경로. 매핑에 없으면 null(바탕 미표시 폴백).
String? routeMapBasemapAssetForRegion(String region) {
  final id = kRouteMapBasemapRegionToId[region];
  return id == null ? null : '$kRouteMapBasemapAssetDir/$id.vec';
}

/// 노선을 고른 동안 바탕을 그리는 불투명도. 상용 지하철 서비스 노선 선택 화면
/// 캡처(2026-10-24)에서 흐린 1·4·6호선 칸 색을 흰 바탕과 노선색 사이 비율로 역산한
/// 값이다. 9개 채널 중앙값 0.22, 범위 0.165~0.28.
const double kRouteMapFadedBasemapOpacity = 0.22;

/// 바탕을 이미지로 구울 때 한 변의 최대 픽셀 수. Vulkan이 모든 기기에 보장하는
/// maxImageDimension2D 최솟값(4096)이다. 이보다 크게 확대하면 화면에 드는 그리기
/// 명령이 적어 벡터로 그린다(#517).
const int kRouteMapBasemapRasterMaxSide = 4096;

/// 배율이 이만큼 그대로이면 바탕을 이미지로 굽는다. 엔진 래스터 캐시가 같은 그림을
/// 3프레임 본 뒤에 굽는 규칙(flow/raster_cache.h access_threshold 3)을 60 Hz 프레임
/// 시간으로 옮긴 값이다. 핀치 중에는 매 프레임 배율이 바뀌어 굽지 않는다.
const Duration kRouteMapBasemapRasterSettleDelay = Duration(milliseconds: 50);

/// 화면에 보이는 바탕 영역에서 상하좌우로 화면 크기의 이 비율만큼 더 굽는다. 굽는 면적은
/// 화면의 (1 + 2 × 0.5)² = 4배다. 지도 전체를 구우면 넓게 본 수도권에서 이미지가
/// 54 MB라(#517 실측 PSS +59 MB) 출시 메모리 예산을 넘기므로 화면 주변만 굽는다.
const double kRouteMapBasemapRasterMargin = 0.5;

/// 바탕 이미지를 결정하는 입력(#517). 같은 배율에서 [sourceRect] 안을 오가는 팬은 한
/// 장을 다시 쓴다. 엔진 래스터 캐시 키가 변환에서 이동을 빼는 것과 같다
/// (flow/raster_cache_util.h GetIntegralTransCTM).
@immutable
class RouteMapBasemapRasterInput {
  const RouteMapBasemapRasterInput({
    required this.basemap,
    required this.overlay,
    required this.scale,
    required this.devicePixelRatio,
    required this.sourceRect,
  });

  /// [visibleViewBox] 둘레로 [kRouteMapBasemapRasterMargin]만큼 넓힌 영역을 굽는 입력.
  /// 영역 모서리를 지금 카메라에서 화면 픽셀 경계에 오도록 맞춘다. 그래서 굽는 순간의
  /// 카메라에서는 이미지 픽셀이 벡터로 그릴 때와 같은 화면 픽셀에 놓이고, 거기서 팬하면
  /// 가장 가까운 픽셀로 옮겨 그려 최대 0.5픽셀 어긋난다.
  factory RouteMapBasemapRasterInput.around({
    required PictureInfo basemap,
    required ui.Picture? overlay,
    required double scale,
    required double devicePixelRatio,
    required Rect visibleViewBox,
    required Offset viewBoxOriginInViewport,
  }) {
    final pixelScale = scale * devicePixelRatio;
    final originPixels = viewBoxOriginInViewport * devicePixelRatio;
    final marginX = visibleViewBox.width * kRouteMapBasemapRasterMargin;
    final marginY = visibleViewBox.height * kRouteMapBasemapRasterMargin;
    final region = Rect.fromLTRB(
      visibleViewBox.left - marginX,
      visibleViewBox.top - marginY,
      visibleViewBox.right + marginX,
      visibleViewBox.bottom + marginY,
    ).intersect(Offset.zero & basemap.size);
    double snapDown(double value, double origin) =>
        ((value * pixelScale + origin).floorToDouble() - origin) / pixelScale;
    double snapUp(double value, double origin) =>
        ((value * pixelScale + origin).ceilToDouble() - origin) / pixelScale;
    return RouteMapBasemapRasterInput(
      basemap: basemap,
      overlay: overlay,
      scale: scale,
      devicePixelRatio: devicePixelRatio,
      sourceRect: Rect.fromLTRB(
        snapDown(region.left, originPixels.dx),
        snapDown(region.top, originPixels.dy),
        snapUp(region.right, originPixels.dx),
        snapUp(region.bottom, originPixels.dy),
      ),
    );
  }

  final PictureInfo basemap;

  /// 고른 노선 레이어. 있으면 바탕을 [kRouteMapFadedBasemapOpacity]로 흐려 굽는다.
  final ui.Picture? overlay;
  final double scale;
  final double devicePixelRatio;

  /// 구울 바탕 영역(viewBox 좌표).
  final Rect sourceRect;

  double get _pixelScale => scale * devicePixelRatio;
  int get pixelWidth => (sourceRect.width * _pixelScale).round();
  int get pixelHeight => (sourceRect.height * _pixelScale).round();

  bool get canRasterize =>
      pixelWidth > 0 &&
      pixelHeight > 0 &&
      pixelWidth <= kRouteMapBasemapRasterMaxSide &&
      pixelHeight <= kRouteMapBasemapRasterMaxSide;

  /// 같은 그림을 같은 배율·화면 밀도로 그리는 입력인지. 영역만 다르면 같은 내용이다.
  bool hasSameContent(RouteMapBasemapRasterInput other) =>
      identical(other.basemap, basemap) &&
      identical(other.overlay, overlay) &&
      other.scale == scale &&
      other.devicePixelRatio == devicePixelRatio;

  /// 화면에 보이는 바탕(viewBox 밖은 그림이 없어 빼고 본다)이 모두 이 이미지 안인지.
  bool covers(Rect visibleViewBox) {
    final visibleBasemap = visibleViewBox.intersect(Offset.zero & basemap.size);
    return visibleBasemap.isEmpty ||
        (sourceRect.left <= visibleBasemap.left &&
            sourceRect.top <= visibleBasemap.top &&
            sourceRect.right >= visibleBasemap.right &&
            sourceRect.bottom >= visibleBasemap.bottom);
  }

  /// 화면 픽셀 1개가 이미지 픽셀 1개가 되게 [sourceRect]를 굽는다. 흐림은 [Opacity]
  /// 위젯과 같은 엔진 불투명도 레이어(같은 정수 알파)로 만든다.
  ui.Image rasterize() {
    final builder = ui.SceneBuilder()
      ..pushTransform(
        (Matrix4.diagonal3Values(
          _pixelScale,
          _pixelScale,
          1,
        )..translateByDouble(-sourceRect.left, -sourceRect.top, 0, 1)).storage,
      );
    final highlight = overlay;
    if (highlight == null) {
      builder.addPicture(Offset.zero, basemap.picture);
    } else {
      builder
        ..pushOpacity(Color.getAlphaFromOpacity(kRouteMapFadedBasemapOpacity))
        ..addPicture(Offset.zero, basemap.picture)
        ..pop()
        ..addPicture(Offset.zero, highlight);
    }
    final scene = (builder..pop()).build();
    try {
      return scene.toImageSync(pixelWidth, pixelHeight);
    } finally {
      scene.dispose();
    }
  }

  /// 같은 내용을 같은 영역으로 굽는 입력인지.
  bool isSameRaster(RouteMapBasemapRasterInput other) =>
      hasSameContent(other) && other.sourceRect == sourceRect;
}

const TextStyle _attributionStyle = TextStyle(
  color: Color(0xFF466467),
  fontSize: 10,
);

/// 바탕 .vec [picture]를 카메라 transform으로 재생한다(재생 전용).
/// vec는 viewBox=source 좌표라 structured painter와 달리 designScale로 나누지
/// 않는다 — translate 동일 + `canvas.scale(camera.scale)` + drawPicture.
class RouteMapBasemapPainter extends CustomPainter {
  RouteMapBasemapPainter({
    required this.picture,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.attributionPainter,
  });

  /// 디코드된 바탕 Picture. 로드 완료 전에는 null이라 바탕을 그리지 않는다.
  final ui.Picture? picture;
  final MapCameraState camera;

  /// 오버레이·카메라의 geometry origin(#1970). Picture 재생을 origin-뺀 공간으로
  /// 맞춰 캔버스와 오버레이 좌표계를 일치시킨다.
  final Offset sourceOrigin;

  final String? attributionText;
  final TextPainter? attributionPainter;

  /// viewBox 점 P를 카메라 재생 후 화면(viewport) 좌표로 변환한다. paint()의
  /// 재생 변환과 동일한 단일 수식이며, `camera.sourceToViewportPoint(P −
  /// sourceOrigin)`와 항등이다(#2068 정렬 회귀 방지).
  @visibleForTesting
  Offset sourceToViewport(Offset viewBoxPoint) =>
      _viewBoxOriginInViewport(camera, sourceOrigin) +
      viewBoxPoint * camera.scale;

  @override
  void paint(Canvas canvas, Size size) {
    final basemap = picture;
    if (basemap != null) {
      canvas.save();
      // vec는 viewBox=source 좌표라 designScale 배율이 없다.
      final origin = _viewBoxOriginInViewport(camera, sourceOrigin);
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(camera.scale);
      canvas.drawPicture(basemap);
      canvas.restore();
    }
    _paintAttribution(canvas, size, attributionText, attributionPainter);
  }

  @override
  bool shouldRepaint(RouteMapBasemapPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        !identical(oldDelegate.picture, picture) ||
        oldDelegate.sourceOrigin != sourceOrigin ||
        oldDelegate.attributionText != attributionText ||
        !identical(oldDelegate.attributionPainter, attributionPainter);
  }
}

/// [RouteMapBasemapRasterInput.rasterize]로 구운 바탕을 카메라 위치에 그린다(#517).
/// 이미지 픽셀 하나가 화면 픽셀 하나라 확대·축소 없이 옮기기만 한다.
class RouteMapBasemapRasterPainter extends CustomPainter {
  RouteMapBasemapRasterPainter({
    required this.image,
    required this.sourceRect,
    required this.devicePixelRatio,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.attributionPainter,
  });

  final ui.Image image;

  /// [image]가 담은 바탕 영역(viewBox 좌표).
  final Rect sourceRect;
  final double devicePixelRatio;
  final MapCameraState camera;
  final Offset sourceOrigin;
  final String? attributionText;
  final TextPainter? attributionPainter;

  @override
  void paint(Canvas canvas, Size size) {
    final origin =
        _viewBoxOriginInViewport(camera, sourceOrigin) +
        sourceRect.topLeft * camera.scale;
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(1 / devicePixelRatio)
      ..drawImage(image, Offset.zero, Paint())
      ..restore();
    _paintAttribution(canvas, size, attributionText, attributionPainter);
  }

  @override
  bool shouldRepaint(RouteMapBasemapRasterPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        !identical(oldDelegate.image, image) ||
        oldDelegate.sourceRect != sourceRect ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.sourceOrigin != sourceOrigin ||
        oldDelegate.attributionText != attributionText ||
        !identical(oldDelegate.attributionPainter, attributionPainter);
  }
}

/// viewBox 원점이 놓이는 화면 좌표.
/// viewport = vc + (viewBox − sourceOrigin − camera.center)·scale.
Offset _viewBoxOriginInViewport(MapCameraState camera, Offset sourceOrigin) =>
    camera.viewportSize.center(Offset.zero) -
    (camera.center + sourceOrigin) * camera.scale;

/// 화면 왼쪽 아래에 고정한 출처 표기.
void _paintAttribution(
  Canvas canvas,
  Size size,
  String? text,
  TextPainter? painter,
) {
  // painter는 State가 소유·재사용하는 캐시라 여기서 dispose하지 않는다(#1973).
  if (text == null || text.isEmpty || painter == null) {
    return;
  }
  const padding = 4.0;
  final origin = Offset(
    padding + 2,
    math.max(padding, size.height - painter.height - padding - 2),
  );
  final background = Rect.fromLTWH(
    origin.dx - 3,
    origin.dy - 2,
    painter.width + 6,
    painter.height + 4,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(background, const Radius.circular(3)),
    Paint()..color = const Color(0xCCFFFFFF),
  );
  painter.paint(canvas, origin);
}

/// 하이브리드 노선도 바탕층 뷰. [region]에 매핑된 .vec를 런타임 디코드해
/// [ui.Picture]를 State에 캐시하고(region 변경 시에만 재로드), 카메라 변경 시
/// transform만 재생한다.
class RouteMapBasemapView extends StatefulWidget {
  const RouteMapBasemapView({
    required this.region,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.highlightedLineId,
    super.key,
  });

  /// 앱 region(한글). 매핑에 없으면 바탕 미표시(빈 화면).
  final String region;
  final MapCameraState camera;

  /// 노선 줄·노선 선택 시트에서 고른 데이터팩 노선 id. null이면 전체 노선이다.
  final String? highlightedLineId;

  /// 오버레이·카메라의 geometry origin(#1970).
  final Offset sourceOrigin;

  final String? attributionText;

  @override
  State<RouteMapBasemapView> createState() => RouteMapBasemapViewState();
}

class RouteMapBasemapViewState extends State<RouteMapBasemapView> {
  static final Map<String, PictureInfo> _globalPictureCache = {};
  static final Map<String, Future<PictureInfo>> _globalPendingLoads = {};
  static Future<RouteMapLineOverlayIndex>? _overlayIndexLoad;
  static RouteMapLineOverlayIndex? _overlayIndex;

  @visibleForTesting
  static void clearPictureCacheForTest() {
    for (final info in _globalPictureCache.values) {
      info.picture.dispose();
    }
    _globalPictureCache.clear();
    _globalPendingLoads.clear();
    _overlayIndexLoad = null;
    _overlayIndex = null;
  }

  PictureInfo? _basemap;
  String? _loadedAsset;
  // 진행 중 로드 토큰. region이 로드 완료 전에 바뀌면 stale 결과를 버린다.
  Object? _loadToken;
  ui.Picture? _overlay;
  Object? _overlayToken;
  TextPainter? _attributionPainter;
  String? _attributionPainterText;
  // 지금 입력으로 구운 바탕 이미지와, 배율이 머물기를 기다리는 다음 입력(#517).
  ({RouteMapBasemapRasterInput input, ui.Image image})? _raster;
  ({RouteMapBasemapRasterInput input, Timer timer})? _pendingRaster;

  @visibleForTesting
  Map<String, PictureInfo> get debugPictureCache => _globalPictureCache;

  @visibleForTesting
  Map<String, Future<PictureInfo>> get debugPendingLoads => _globalPendingLoads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // initState가 아닌 여기서 로드한다(로드가 inherited widget에 의존할 수 있으므로).
    // region 미변경 시 _ensureBasemap이 조기 반환해 중복 로드가 없다.
    _ensureBasemap();
    _ensureOverlay();
  }

  @override
  void didUpdateWidget(RouteMapBasemapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region != widget.region) {
      _ensureBasemap();
    }
    if (oldWidget.region != widget.region ||
        oldWidget.highlightedLineId != widget.highlightedLineId) {
      _ensureOverlay();
    }
  }

  void _ensureBasemap() {
    final asset = routeMapBasemapAssetForRegion(widget.region);
    // 매핑에 없는 region: 바탕 미표시로 안전 폴백(크래시 금지).
    if (asset == null) {
      _loadToken = null;
      _loadedAsset = null;
      if (_basemap != null) {
        setState(() {
          _basemap = null;
        });
      }
      return;
    }

    if (_loadedAsset == asset && _basemap != null) {
      return;
    }

    final cached = _globalPictureCache[asset];
    if (cached != null) {
      _loadToken = null;
      _loadedAsset = asset;
      if (_basemap != cached) {
        setState(() {
          _basemap = cached;
        });
      }
      return;
    }

    final token = Object();
    _loadToken = token;
    _loadedAsset = asset;

    unawaited(_loadBasemapAsset(asset, token));
  }

  /// [asset]을 한 번만 디코드한다. 같은 자산을 읽는 중이면 그 로드를 함께 기다린다.
  static Future<PictureInfo> _decodePicture(String asset) {
    final pending = _globalPendingLoads[asset];
    if (pending != null) {
      return pending;
    }
    final load = vg
        .loadPicture(AssetBytesLoader(asset), null)
        .then((info) => _globalPictureCache[asset] = info)
        .whenComplete(() => unawaited(_globalPendingLoads.remove(asset)));
    _globalPendingLoads[asset] = load;
    return load;
  }

  Future<void> _loadBasemapAsset(String asset, Object token) async {
    try {
      final basemap = await _decodePicture(asset);
      if (!mounted || !identical(_loadToken, token)) {
        return;
      }
      setState(() {
        _basemap = basemap;
      });
    } catch (error, stack) {
      if (!mounted || !identical(_loadToken, token)) {
        return;
      }
      _reportLoadFailure(error, stack, '노선도 바탕 .vec 로드 실패($asset)');
    }
  }

  /// 고른 노선 레이어를 맞춘다. 레이어가 준비되기 전에는 바탕을 흐리지 않는다.
  void _ensureOverlay() {
    final regionId = kRouteMapBasemapRegionToId[widget.region];
    final lineId = widget.highlightedLineId;
    _overlayToken = null;
    if (regionId == null || lineId == null) {
      _showOverlay(null);
      return;
    }
    final cached = _cachedOverlay(regionId, lineId);
    _showOverlay(cached);
    if (cached == null) {
      final token = _overlayToken = Object();
      unawaited(_loadOverlay(regionId, lineId, token));
    }
  }

  static ui.Picture? _cachedOverlay(String regionId, String lineId) {
    final index = _overlayIndex;
    if (index == null) {
      return null;
    }
    try {
      return _globalPictureCache[index.overlayAssetFor(
            regionId: regionId,
            lineId: lineId,
          )]
          ?.picture;
    } on RouteMapLineOverlayMissing {
      return null;
    }
  }

  static Future<RouteMapLineOverlayIndex> _loadOverlayIndex() =>
      _overlayIndexLoad ??= rootBundle
          .loadString(kRouteMapLineOverlayIndexAssetPath, cache: false)
          .then((json) => _overlayIndex = RouteMapLineOverlayIndex.parse(json));

  Future<void> _loadOverlay(
    String regionId,
    String lineId,
    Object token,
  ) async {
    try {
      final index = await _loadOverlayIndex();
      final overlay = await _decodePicture(
        index.overlayAssetFor(regionId: regionId, lineId: lineId),
      );
      if (mounted && identical(_overlayToken, token)) {
        _showOverlay(overlay.picture);
      }
    } catch (error, stack) {
      if (mounted && identical(_overlayToken, token)) {
        _reportLoadFailure(error, stack, '노선 강조 레이어 로드 실패($regionId/$lineId)');
      }
    }
  }

  void _showOverlay(ui.Picture? overlay) {
    if (!identical(_overlay, overlay)) {
      setState(() {
        _overlay = overlay;
      });
    }
  }

  void _reportLoadFailure(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'network_map',
        context: ErrorDescription(context),
      ),
    );
  }

  void _ensureAttributionPainter() {
    final text = widget.attributionText;
    if (text == null || text.isEmpty) {
      if (_attributionPainter != null) {
        _attributionPainter!.dispose();
        _attributionPainter = null;
        _attributionPainterText = null;
      }
      return;
    }
    if (_attributionPainterText == text && _attributionPainter != null) {
      return;
    }
    _attributionPainter?.dispose();
    _attributionPainter = TextPainter(
      text: TextSpan(text: text, style: _attributionStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _attributionPainterText = text;
  }

  /// 지금 그릴 수 있는 바탕 이미지를 돌려준다. 화면이 이미지 밖으로 나가면 벡터로
  /// 그리고, [desired]가 [kRouteMapBasemapRasterSettleDelay] 동안 그대로이면(카메라가
  /// 멈추면) 그 영역을 새로 굽는다. 내용이 바뀐 이미지는 바로 버린다.
  ({RouteMapBasemapRasterInput input, ui.Image image})? _usableRaster(
    RouteMapBasemapRasterInput? desired,
    Rect visibleViewBox,
  ) {
    final raster = _raster;
    if (raster != null &&
        desired != null &&
        raster.input.hasSameContent(desired) &&
        raster.input.covers(visibleViewBox)) {
      _pendingRaster?.timer.cancel();
      _pendingRaster = null;
      return raster;
    }
    if (raster != null &&
        (desired == null || !raster.input.hasSameContent(desired))) {
      raster.image.dispose();
      _raster = null;
    }
    _scheduleRaster(desired);
    return null;
  }

  void _scheduleRaster(RouteMapBasemapRasterInput? input) {
    final pending = _pendingRaster;
    if (pending != null && input != null && pending.input.isSameRaster(input)) {
      return;
    }
    pending?.timer.cancel();
    _pendingRaster = null;
    if (input == null || !input.canRasterize) {
      return;
    }
    _pendingRaster = (
      input: input,
      timer: Timer(kRouteMapBasemapRasterSettleDelay, () {
        if (!mounted || !identical(_pendingRaster?.input, input)) {
          return;
        }
        setState(() {
          _raster?.image.dispose();
          _pendingRaster = null;
          _raster = (input: input, image: input.rasterize());
        });
      }),
    );
  }

  @override
  void dispose() {
    _pendingRaster?.timer.cancel();
    _raster?.image.dispose();
    _loadToken = null;
    _basemap = null;
    _overlayToken = null;
    _overlay = null;
    _attributionPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAttributionPainter();
    final basemapInfo = _basemap;
    final highlight = basemapInfo == null ? null : _overlay;
    final devicePixelRatio = View.of(context).devicePixelRatio;
    final visibleViewBox = widget.camera.visibleSourceRect.shift(
      widget.sourceOrigin,
    );
    final raster = _usableRaster(
      basemapInfo == null
          ? null
          : RouteMapBasemapRasterInput.around(
              basemap: basemapInfo,
              overlay: highlight,
              scale: widget.camera.scale,
              devicePixelRatio: devicePixelRatio,
              visibleViewBox: visibleViewBox,
              viewBoxOriginInViewport: _viewBoxOriginInViewport(
                widget.camera,
                widget.sourceOrigin,
              ),
            ),
      visibleViewBox,
    );
    if (raster != null) {
      return RepaintBoundary(
        child: CustomPaint(
          size: widget.camera.viewportSize,
          painter: RouteMapBasemapRasterPainter(
            image: raster.image,
            sourceRect: raster.input.sourceRect,
            devicePixelRatio: devicePixelRatio,
            camera: widget.camera,
            sourceOrigin: widget.sourceOrigin,
            attributionText: widget.attributionText,
            attributionPainter: _attributionPainter,
          ),
        ),
      );
    }
    final basemap = _layerPaint(
      basemapInfo?.picture,
      attributed: highlight == null,
    );
    // RepaintBoundary로 바탕 레이어를 형제 오버레이 rebuild와 분리한다.
    // 노선을 고르면 바탕 전체를 Opacity 한 겹으로 흐려 겹친 선이 더 진해지지 않게
    // 하고, 그 위에 고른 노선 레이어와 출처 표기를 원래 진하기로 그린다.
    return RepaintBoundary(
      child: highlight == null
          ? basemap
          : Stack(
              children: [
                Opacity(opacity: kRouteMapFadedBasemapOpacity, child: basemap),
                _layerPaint(highlight, attributed: true),
              ],
            ),
    );
  }

  // isComplex·willChange는 엔진 래스터 캐시 힌트라 Skia에서만 쓰인다. Impeller
  // Vulkan 표면은 래스터 캐시를 끈다(shell/gpu/gpu_surface_vulkan_impeller.cc
  // EnableRasterCache). 같은 배율의 팬은 위 바탕 이미지가 대신 맡는다(#517).
  CustomPaint _layerPaint(ui.Picture? picture, {required bool attributed}) {
    return CustomPaint(
      size: widget.camera.viewportSize,
      isComplex: true,
      willChange: true,
      painter: RouteMapBasemapPainter(
        picture: picture,
        camera: widget.camera,
        sourceOrigin: widget.sourceOrigin,
        attributionText: attributed ? widget.attributionText : null,
        attributionPainter: attributed ? _attributionPainter : null,
      ),
    );
  }
}
