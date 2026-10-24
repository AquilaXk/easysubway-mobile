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
  Offset sourceToViewport(Offset viewBoxPoint) {
    final vc = camera.viewportSize.center(Offset.zero);
    return vc + (viewBoxPoint - sourceOrigin - camera.center) * camera.scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final basemap = picture;
    if (basemap != null) {
      canvas.save();
      final vc = camera.viewportSize.center(Offset.zero);
      // viewport = vc + (viewBox − sourceOrigin − camera.center)·scale.
      // vec는 viewBox=source 좌표라 designScale 배율이 없다.
      canvas.translate(
        vc.dx - (camera.center.dx + sourceOrigin.dx) * camera.scale,
        vc.dy - (camera.center.dy + sourceOrigin.dy) * camera.scale,
      );
      canvas.scale(camera.scale);
      canvas.drawPicture(basemap);
      canvas.restore();
    }
    _paintAttribution(canvas, size); // 화면 고정.
  }

  void _paintAttribution(Canvas canvas, Size size) {
    final text = attributionText;
    final painter = attributionPainter;
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

  @override
  bool shouldRepaint(RouteMapBasemapPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        !identical(oldDelegate.picture, picture) ||
        oldDelegate.sourceOrigin != sourceOrigin ||
        oldDelegate.attributionText != attributionText ||
        !identical(oldDelegate.attributionPainter, attributionPainter);
  }
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
  static final Map<String, ui.Picture> _globalPictureCache = {};
  static final Map<String, Future<ui.Picture>> _globalPendingLoads = {};
  static Future<RouteMapLineOverlayIndex>? _overlayIndexLoad;
  static RouteMapLineOverlayIndex? _overlayIndex;

  @visibleForTesting
  static void clearPictureCacheForTest() {
    for (final picture in _globalPictureCache.values) {
      picture.dispose();
    }
    _globalPictureCache.clear();
    _globalPendingLoads.clear();
    _overlayIndexLoad = null;
    _overlayIndex = null;
  }

  ui.Picture? _picture;
  String? _loadedAsset;
  // 진행 중 로드 토큰. region이 로드 완료 전에 바뀌면 stale 결과를 버린다.
  Object? _loadToken;
  ui.Picture? _overlay;
  Object? _overlayToken;
  TextPainter? _attributionPainter;
  String? _attributionPainterText;

  @visibleForTesting
  Map<String, ui.Picture> get debugPictureCache => _globalPictureCache;

  @visibleForTesting
  Map<String, Future<ui.Picture>> get debugPendingLoads => _globalPendingLoads;

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
      if (_picture != null) {
        setState(() {
          _picture = null;
        });
      }
      return;
    }

    if (_loadedAsset == asset && _picture != null) {
      return;
    }

    final cached = _globalPictureCache[asset];
    if (cached != null) {
      _loadToken = null;
      _loadedAsset = asset;
      if (_picture != cached) {
        setState(() {
          _picture = cached;
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
  static Future<ui.Picture> _decodePicture(String asset) {
    final pending = _globalPendingLoads[asset];
    if (pending != null) {
      return pending;
    }
    final load = vg
        .loadPicture(AssetBytesLoader(asset), null)
        .then((info) => _globalPictureCache[asset] = info.picture)
        .whenComplete(() => unawaited(_globalPendingLoads.remove(asset)));
    _globalPendingLoads[asset] = load;
    return load;
  }

  Future<void> _loadBasemapAsset(String asset, Object token) async {
    try {
      final picture = await _decodePicture(asset);
      if (!mounted || !identical(_loadToken, token)) {
        return;
      }
      setState(() {
        _picture = picture;
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
      )];
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
      final picture = await _decodePicture(
        index.overlayAssetFor(regionId: regionId, lineId: lineId),
      );
      if (mounted && identical(_overlayToken, token)) {
        _showOverlay(picture);
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

  @override
  void dispose() {
    _loadToken = null;
    _picture = null;
    _overlayToken = null;
    _overlay = null;
    _attributionPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAttributionPainter();
    final highlight = _picture == null ? null : _overlay;
    final basemap = _layerPaint(_picture, attributed: highlight == null);
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

  // isComplex=true는 이 레이어가 값비싼 그리기임을(래스터 캐시 가치 있음),
  // willChange=true는 다음 프레임에 다시 바뀔 것임을(래스터 캐시를 유지하지
  // 말라는 힌트 — isComplex 캐싱을 억제) 엔진에 알린다. 이 바탕은 카메라
  // 팬/줌마다 매 프레임 repaint되는 레이어라 willChange가 적절하다.
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
