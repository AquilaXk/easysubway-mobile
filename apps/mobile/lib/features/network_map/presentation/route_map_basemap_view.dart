import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../domain/map_camera.dart';
import '../domain/route_map_line_overlay_index.dart';
import 'route_map_basemap_assets.dart';
import 'route_map_basemap_tiles.dart';

export 'route_map_basemap_tiles.dart' show kRouteMapFadedBasemapOpacity;

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

/// 배율이 이만큼 그대로이면 바탕 타일 격자를 만든다. 엔진 래스터 캐시가 같은 그림을
/// 3프레임 본 뒤에 굽는 규칙(flow/raster_cache.h access_threshold 3)을 60 Hz 프레임
/// 시간으로 옮긴 값이다. 핀치 중에는 매 프레임 배율이 바뀌어 굽지 않는다. 같은 배율의
/// 팬은 격자를 그대로 쓰고 새로 드러난 타일을 바로 굽는다(#517).
const Duration kRouteMapBasemapRasterSettleDelay = Duration(milliseconds: 50);

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

/// 하이브리드 노선도 바탕층 뷰. [region]의 바탕 .vec와 고른 노선 레이어를 [assets]의 변형에서
/// 골라 디코드한 [ui.Picture]를 카메라 변경 시 transform만 바꿔 재생한다.
///
/// 상태를 쥐는 [RouteMapBasemapLayers]를 권역과 바탕 자료로 key를 걸어 만든다. 권역이나
/// 바탕 자료가 바뀌면 이전 State와 그림이 버려지고 새로 만들어져, 이전 권역의 바탕이
/// 남는 일이 구조상 없다.
class RouteMapBasemapView extends StatelessWidget {
  const RouteMapBasemapView({
    required this.region,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.highlightedLineId,
    this.assets,
    super.key,
  });

  /// 앱 region(한글). 매핑에 없으면 바탕을 그리지 않고 한 번 보고한다.
  final String region;
  final MapCameraState camera;

  /// 노선 줄·노선 선택 시트에서 고른 데이터팩 노선 id. null이면 전체 노선이다.
  final String? highlightedLineId;

  /// 오버레이·카메라의 geometry origin(#1970).
  final Offset sourceOrigin;

  final String? attributionText;

  /// 바탕 색인과 그림을 읽는 곳. null이면 [RouteMapBasemapAssets.shared]다.
  final RouteMapBasemapAssets? assets;

  @override
  Widget build(BuildContext context) {
    final source = assets ?? RouteMapBasemapAssets.shared;
    return RouteMapBasemapLayers(
      key: ValueKey((region, source)),
      region: region,
      camera: camera,
      sourceOrigin: sourceOrigin,
      attributionText: attributionText,
      highlightedLineId: highlightedLineId,
      assets: source,
    );
  }
}

/// [RouteMapBasemapView]가 권역마다 만드는 바탕 그림 상태. 그릴 자산과 타일 격자는 이
/// State의 [region]과 [assets]에서만 정해진다.
class RouteMapBasemapLayers extends StatefulWidget {
  const RouteMapBasemapLayers({
    required this.region,
    required this.camera,
    required this.sourceOrigin,
    required this.attributionText,
    required this.highlightedLineId,
    required this.assets,
    super.key,
  });

  final String region;
  final MapCameraState camera;
  final Offset sourceOrigin;
  final String? attributionText;
  final String? highlightedLineId;
  final RouteMapBasemapAssets assets;

  @override
  State<RouteMapBasemapLayers> createState() => RouteMapBasemapLayersState();
}

class RouteMapBasemapLayersState extends State<RouteMapBasemapLayers> {
  late final RouteMapBasemapAssets _assets = widget.assets;
  late final String? _regionId = kRouteMapBasemapRegionToId[widget.region];
  // 색인을 기다리는 중인지. 기다리는 동안 노선을 몇 번 바꿔도 이어 실행은 하나다.
  bool _awaitingFiles = false;
  // 지금 그리려는 바탕과 노선 레이어 자산. 그림은 [_assets]에서 꺼내므로 이 자산의 그림만
  // 그려지고, 늦게 끝난 다른 자산의 디코드는 화면을 바꾸지 않는다.
  String? _baseAsset;
  String? _overlayAsset;
  TextPainter? _attributionPainter;
  String? _attributionPainterText;
  // 지금 바탕 타일 격자와 구운 타일, 배율이 머물기를 기다리는 다음 내용(#517).
  RouteMapBasemapTileGrid? _tileGrid;
  final RouteMapBasemapTileCache _tiles = RouteMapBasemapTileCache();
  ({RouteMapBasemapTileContent content, Timer timer})? _pendingTileGrid;
  bool _bakeFrameScheduled = false;

  @visibleForTesting
  RouteMapBasemapTileCache get debugTiles => _tiles;

  @override
  void initState() {
    super.initState();
    if (_regionId == null) {
      reportRouteMapBasemapFailure(
        ArgumentError.value(widget.region, 'region', '바탕 색인에 없는 권역'),
        StackTrace.current,
        '노선도 바탕 권역 매핑 실패(${widget.region})',
      );
    }
    _syncLayers();
  }

  @override
  void didUpdateWidget(RouteMapBasemapLayers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedLineId != widget.highlightedLineId) {
      _syncLayers();
    }
  }

  /// 권역과 고른 노선에서 그릴 바탕·노선 레이어 자산을 정하고 아직 없는 그림을 디코드한다.
  /// 색인을 아직 읽지 않았으면 읽은 뒤 다시 정한다. 레이어가 준비되기 전에는 바탕을
  /// 흐리지 않는다.
  void _syncLayers() {
    _baseAsset = null;
    _overlayAsset = null;
    final regionId = _regionId;
    if (regionId == null) {
      return;
    }
    final files = _assets.files;
    if (files == null) {
      _syncWhenFilesLoad();
      return;
    }
    final baseAsset = files.baseAssetFor(regionId);
    _baseAsset = baseAsset;
    _decodeIfMissing(baseAsset);
    final lineId = widget.highlightedLineId;
    if (lineId == null) {
      return;
    }
    try {
      final overlayAsset = files.overlayAssetFor(
        regionId: regionId,
        lineId: lineId,
      );
      _overlayAsset = overlayAsset;
      _decodeIfMissing(overlayAsset);
    } on RouteMapLineOverlayMissing catch (error, stack) {
      reportRouteMapBasemapFailure(
        error,
        stack,
        '노선 강조 레이어 조회 실패($regionId/$lineId)',
      );
    }
  }

  void _syncWhenFilesLoad() {
    if (_awaitingFiles) {
      return;
    }
    _awaitingFiles = true;
    unawaited(
      _assets.loadFiles().then((files) {
        _awaitingFiles = false;
        if (files != null && mounted) {
          setState(_syncLayers);
        }
      }),
    );
  }

  /// [asset]을 아직 디코드하지 않았으면 디코드하고, 끝났을 때 이 뷰가 아직 [asset]을
  /// 그리려 하면 다시 그린다. 실패는 [_assets]가 보고한다.
  void _decodeIfMissing(String asset) {
    if (_assets.picture(asset) != null) {
      return;
    }
    unawaited(
      _assets.decode(asset).then((info) {
        if (info != null &&
            mounted &&
            (asset == _baseAsset || asset == _overlayAsset)) {
          setState(() {});
        }
      }),
    );
  }

  PictureInfo? _pictureOf(String? asset) =>
      asset == null ? null : _assets.picture(asset);

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

  /// [content]를 그리는 타일 격자. 내용이 바뀌면 타일을 모두 버리고, 새 내용이
  /// [kRouteMapBasemapRasterSettleDelay] 동안 그대로이면 그때 카메라에서 격자를 만든다.
  RouteMapBasemapTileGrid? _syncTileGrid(RouteMapBasemapTileContent? content) {
    final grid = _tileGrid;
    if (grid != null && content != null && grid.content.isSameAs(content)) {
      return grid;
    }
    if (grid != null) {
      _tiles.retainWithin(null);
      _tileGrid = null;
    }
    _scheduleTileGrid(content);
    return null;
  }

  void _scheduleTileGrid(RouteMapBasemapTileContent? content) {
    final pending = _pendingTileGrid;
    if (pending != null &&
        content != null &&
        pending.content.isSameAs(content)) {
      return;
    }
    pending?.timer.cancel();
    _pendingTileGrid = null;
    if (content == null) {
      return;
    }
    _pendingTileGrid = (
      content: content,
      timer: Timer(kRouteMapBasemapRasterSettleDelay, () {
        if (!mounted || !identical(_pendingTileGrid?.content, content)) {
          return;
        }
        final devicePixelRatio = content.devicePixelRatio;
        setState(() {
          _pendingTileGrid = null;
          _tileGrid = RouteMapBasemapTileGrid.at(
            content,
            _viewBoxOriginPixels(
              _viewportPixels(devicePixelRatio),
              devicePixelRatio,
            ),
          );
        });
      }),
    );
  }

  /// 이 위젯이 차지한 화면 영역(화면 픽셀, 지난 레이아웃 기준). 타일 경계를 화면 픽셀
  /// 경계에 맞추려면 위젯이 화면에 놓인 위치까지 넣어야 한다. 논리 픽셀 정수 위치도
  /// 2.8125배 같은 밀도에서는 화면 픽셀 사이에 놓인다.
  Rect _viewportPixels(double devicePixelRatio) {
    final screenOrigin = (context.findRenderObject()! as RenderBox)
        .localToGlobal(Offset.zero);
    return (screenOrigin * devicePixelRatio) &
        (widget.camera.viewportSize * devicePixelRatio);
  }

  Offset _viewBoxOriginPixels(Rect viewportPixels, double devicePixelRatio) =>
      viewportPixels.topLeft +
      _viewBoxOriginInViewport(widget.camera, widget.sourceOrigin) *
          devicePixelRatio;

  /// 이번 프레임에 그릴 타일과, 타일이 아직 없어 벡터로 그릴 화면 영역(논리 좌표).
  ({List<({ui.Image image, Rect pixels})> tiles, Offset gridOrigin, Path? gaps})
  _tileFrame(RouteMapBasemapTileGrid grid) {
    final devicePixelRatio = grid.content.devicePixelRatio;
    final viewportPixels = _viewportPixels(devicePixelRatio);
    final originPixels = _viewBoxOriginPixels(viewportPixels, devicePixelRatio);
    final gridOrigin =
        grid.gridOriginOnScreen(originPixels) - viewportPixels.topLeft;
    final visible = grid.visibleRange(originPixels, viewportPixels);
    if (visible == null) {
      _tiles.retainWithin(null);
      return (tiles: const [], gridOrigin: gridOrigin, gaps: null);
    }
    _tiles.retainWithin(visible);
    final visibleKeys = visible.keysFromCenter();
    _bakeTiles(grid, visibleKeys);
    final tiles = <({ui.Image image, Rect pixels})>[];
    Path? gaps;
    for (final key in visibleKeys) {
      final pixels = grid.tilePixels(key);
      final image = _tiles[key];
      if (image != null) {
        tiles.add((image: image, pixels: pixels));
      } else {
        (gaps ??= Path()).addRect(
          Rect.fromLTRB(
            (gridOrigin.dx + pixels.left) / devicePixelRatio,
            (gridOrigin.dy + pixels.top) / devicePixelRatio,
            (gridOrigin.dx + pixels.right) / devicePixelRatio,
            (gridOrigin.dy + pixels.bottom) / devicePixelRatio,
          ),
        );
      }
    }
    return (tiles: tiles, gridOrigin: gridOrigin, gaps: gaps);
  }

  /// 보이는 타일 중 없는 것을 화면 가운데에서 가까운 순서로 이번 프레임에
  /// [kRouteMapBasemapTilesPerFrame]장까지 굽고, 남으면 다음 프레임에 이어 굽는다.
  /// 상한이 차면 더 굽지 않고 나머지는 벡터로 그린다.
  void _bakeTiles(
    RouteMapBasemapTileGrid grid,
    List<RouteMapBasemapTileKey> visibleKeys,
  ) {
    var baked = 0;
    for (final key in visibleKeys.where((key) => _tiles[key] == null)) {
      if (baked == kRouteMapBasemapTilesPerFrame) {
        _scheduleBakeFrame();
        return;
      }
      final pixels = grid.tilePixels(key);
      final bytes = routeMapTileBytes(
        pixels.width.toInt(),
        pixels.height.toInt(),
      );
      if (!_tiles.fits(bytes)) {
        return;
      }
      _tiles.add(key, grid.rasterize(key), bytes);
      baked++;
    }
  }

  void _scheduleBakeFrame() {
    if (_bakeFrameScheduled) {
      return;
    }
    _bakeFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _bakeFrameScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pendingTileGrid?.timer.cancel();
    _tiles.retainWithin(null);
    _attributionPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAttributionPainter();
    final basemapInfo = _pictureOf(_baseAsset);
    final highlight = basemapInfo == null
        ? null
        : _pictureOf(_overlayAsset)?.picture;
    final grid = _syncTileGrid(
      basemapInfo == null
          ? null
          : RouteMapBasemapTileContent(
              basemap: basemapInfo.picture,
              basemapSize: basemapInfo.size,
              overlay: highlight,
              scale: widget.camera.scale,
              devicePixelRatio: View.of(context).devicePixelRatio,
            ),
    );
    // RepaintBoundary로 바탕 레이어를 형제 오버레이 rebuild와 분리한다.
    if (grid == null) {
      return RepaintBoundary(
        child: _vectorLayers(basemapInfo?.picture, highlight, attributed: true),
      );
    }
    final frame = _tileFrame(grid);
    final gaps = frame.gaps;
    return RepaintBoundary(
      child: Stack(
        children: [
          // 아직 굽지 않은 타일 자리만 벡터로 그린다.
          if (gaps != null)
            ClipPath(
              clipper: _TileGapClipper(gaps),
              clipBehavior: Clip.hardEdge,
              child: _vectorLayers(
                basemapInfo!.picture,
                highlight,
                attributed: false,
              ),
            ),
          CustomPaint(
            size: widget.camera.viewportSize,
            painter: RouteMapBasemapTilePainter(
              tiles: frame.tiles,
              gridOrigin: frame.gridOrigin,
              devicePixelRatio: grid.content.devicePixelRatio,
            ),
          ),
          if (_attributionPainter != null) _layerPaint(null, attributed: true),
        ],
      ),
    );
  }

  /// 바탕을 벡터로 그리는 레이어. 노선을 고르면 바탕 전체를 Opacity 한 겹으로 흐려 겹친
  /// 선이 더 진해지지 않게 하고, 그 위에 고른 노선 레이어를 원래 진하기로 그린다.
  Widget _vectorLayers(
    ui.Picture? basemap,
    ui.Picture? highlight, {
    required bool attributed,
  }) {
    if (highlight == null) {
      return _layerPaint(basemap, attributed: attributed);
    }
    return Stack(
      children: [
        Opacity(
          opacity: kRouteMapFadedBasemapOpacity,
          child: _layerPaint(basemap, attributed: false),
        ),
        _layerPaint(highlight, attributed: attributed),
      ],
    );
  }

  // isComplex·willChange는 엔진 래스터 캐시 힌트라 Skia에서만 쓰인다. Impeller
  // Vulkan 표면은 래스터 캐시를 끈다(shell/gpu/gpu_surface_vulkan_impeller.cc
  // EnableRasterCache). 같은 배율의 팬은 위 바탕 타일이 대신 맡는다(#517).
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

/// 굽지 않은 타일 자리로 자른다. 타일 경계는 화면 픽셀 경계라 안티앨리어싱 없이 잘라도
/// 걸치는 픽셀이 없다.
class _TileGapClipper extends CustomClipper<Path> {
  _TileGapClipper(this.gaps);

  final Path gaps;

  @override
  Path getClip(Size size) => gaps;

  @override
  bool shouldReclip(_TileGapClipper oldClipper) =>
      !identical(oldClipper.gaps, gaps);
}
