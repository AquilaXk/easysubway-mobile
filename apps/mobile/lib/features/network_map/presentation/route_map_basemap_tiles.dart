import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

// 노선도 바탕을 화면 픽셀 크기의 타일로 구워 두고 팬하는 동안 이미지로 그린다(#517).
// 상용 지도 앱처럼 고정 크기 타일로 나누고 바이트 상한으로 메모리를 묶는다. 타일 범위와
// 가운데부터 채우는 순서는 flutter_map TileLayer(BSD-3), 내용이 바뀌면 통째로 비우는
// 규칙은 MapLibre Native TilePyramid(BSD-2)를 따른다. 출시 메모리 예산이 화면에 보이는
// 타일만 허락해(#517 Galaxy A17 실측) 화면 밖 타일은 남기지 않는다.

/// 노선을 고른 동안 바탕을 그리는 불투명도. 상용 지하철 서비스 노선 선택 화면
/// 캡처(2026-10-24)에서 흐린 1·4·6호선 칸 색을 흰 바탕과 노선색 사이 비율로 역산한
/// 값이다. 9개 채널 중앙값 0.22, 범위 0.165~0.28.
const double kRouteMapFadedBasemapOpacity = 0.22;

/// 타일 한 변의 화면 픽셀 수. Galaxy A17 실측(#517)에서 화면 하나를 덮는 비용(GPU
/// 메모리 + 장당 고정 비용 + 가장자리 낭비)이 128·192·512보다 작았다.
const int kRouteMapBasemapTileSize = 256;

/// 바탕 타일이 함께 쓸 수 있는 GPU 메모리(밉맵 포함 바이트). Galaxy A17 노선도 화면
/// (1080×1421 픽셀)에 동시에 보이는 타일은 많아야 6×7장(14,680,008바이트)이다. 더 큰
/// 화면에서 넘치는 타일은 벡터로 그린다.
const int kRouteMapBasemapTileCacheBytes = 14 << 20;

/// 한 프레임에 새로 굽는 타일 수. 굽기는 그 프레임 앞에서 래스터 스레드를 쓴다.
const int kRouteMapBasemapTilesPerFrame = 1;

/// 격자 안 타일 위치(열, 행).
typedef RouteMapBasemapTileKey = ({int column, int row});

/// 타일 열·행 범위(양 끝 포함). flutter_map DiscreteTileRange와 같은 규칙이다.
@immutable
class RouteMapBasemapTileRange {
  const RouteMapBasemapTileRange({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  bool contains(RouteMapBasemapTileKey key) =>
      key.column >= left &&
      key.column <= right &&
      key.row >= top &&
      key.row <= bottom;

  /// 범위 가운데에서 가까운 타일부터. flutter_map TileLayer._loadTiles가 불러올 타일을
  /// 범위 중심과의 거리로 정렬하는 것과 같다.
  List<RouteMapBasemapTileKey> keysFromCenter() {
    final centerColumn = (left + right) / 2;
    final centerRow = (top + bottom) / 2;
    double distance(RouteMapBasemapTileKey key) =>
        math.pow(key.column - centerColumn, 2) +
        math.pow(key.row - centerRow, 2).toDouble();
    return [
      for (var row = top; row <= bottom; row++)
        for (var column = left; column <= right; column++)
          (column: column, row: row),
    ]..sort((a, b) => distance(a).compareTo(distance(b)));
  }
}

/// 같은 바탕을 같은 배율·화면 밀도로 그리는 내용. 이것이 바뀌면 타일을 모두 버린다.
@immutable
class RouteMapBasemapTileContent {
  const RouteMapBasemapTileContent({
    required this.basemap,
    required this.basemapSize,
    required this.overlay,
    required this.scale,
    required this.devicePixelRatio,
  });

  final ui.Picture basemap;

  /// 바탕 그림의 viewBox 크기.
  final Size basemapSize;

  /// 고른 노선 레이어. 있으면 바탕을 [kRouteMapFadedBasemapOpacity]로 흐려 굽는다.
  final ui.Picture? overlay;
  final double scale;
  final double devicePixelRatio;

  double get pixelScale => scale * devicePixelRatio;

  bool isSameAs(RouteMapBasemapTileContent other) =>
      identical(other.basemap, basemap) &&
      other.basemapSize == basemapSize &&
      identical(other.overlay, overlay) &&
      other.scale == scale &&
      other.devicePixelRatio == devicePixelRatio;
}

/// [content]를 [kRouteMapBasemapTileSize] 픽셀 칸으로 나눈 격자.
///
/// 격자 픽셀 g = viewBox 좌표 × pixelScale + [phase]이고, 타일 (열, 행)은 g가 그 칸에
/// 드는 영역이다. [phase]는 격자를 만든 순간 viewBox 원점의 화면 픽셀 소수부라서, 그
/// 카메라에서는 타일 경계가 화면 픽셀 경계에 놓인다. 같은 배율에서 팬하면 격자를
/// 가장 가까운 화면 픽셀로 옮겨 그려 최대 0.5픽셀 어긋난다. 엔진 래스터 캐시가
/// 변환의 이동을 정수로 맞추는 것과 같다(flow/raster_cache_util.h GetIntegralTransCTM).
@immutable
class RouteMapBasemapTileGrid {
  const RouteMapBasemapTileGrid({required this.content, required this.phase});

  /// [viewBoxOriginPixels](viewBox 원점의 화면 픽셀 좌표)에서 격자를 만든다.
  factory RouteMapBasemapTileGrid.at(
    RouteMapBasemapTileContent content,
    Offset viewBoxOriginPixels,
  ) => RouteMapBasemapTileGrid(
    content: content,
    phase: Offset(
      viewBoxOriginPixels.dx - viewBoxOriginPixels.dx.floorToDouble(),
      viewBoxOriginPixels.dy - viewBoxOriginPixels.dy.floorToDouble(),
    ),
  );

  final RouteMapBasemapTileContent content;
  final Offset phase;

  /// 바탕 그림이 차지하는 격자 픽셀(정수로 넓힌 영역).
  Rect get _contentPixels => Rect.fromLTRB(
    0,
    0,
    (phase.dx + content.basemapSize.width * content.pixelScale).ceilToDouble(),
    (phase.dy + content.basemapSize.height * content.pixelScale).ceilToDouble(),
  );

  /// 격자 픽셀 (0, 0)이 놓이는 화면 픽셀 위치(정수).
  Offset gridOriginOnScreen(Offset viewBoxOriginPixels) => Offset(
    (viewBoxOriginPixels.dx - phase.dx).roundToDouble(),
    (viewBoxOriginPixels.dy - phase.dy).roundToDouble(),
  );

  /// 화면 [viewportPixels]에 보이는 바탕 타일. 바탕이 화면 밖이면 null이다.
  RouteMapBasemapTileRange? visibleRange(
    Offset viewBoxOriginPixels,
    Size viewportPixels,
  ) {
    final origin = gridOriginOnScreen(viewBoxOriginPixels);
    final visible = (-origin & viewportPixels).intersect(_contentPixels);
    if (visible.isEmpty) {
      return null;
    }
    const size = kRouteMapBasemapTileSize;
    return RouteMapBasemapTileRange(
      left: visible.left ~/ size,
      top: visible.top ~/ size,
      right: (visible.right / size).ceil() - 1,
      bottom: (visible.bottom / size).ceil() - 1,
    );
  }

  /// 타일이 덮는 격자 픽셀. 바탕 가장자리 타일은 바탕까지만 자른다.
  Rect tilePixels(RouteMapBasemapTileKey key) {
    const size = kRouteMapBasemapTileSize;
    final cell = Rect.fromLTWH(
      (key.column * size).toDouble(),
      (key.row * size).toDouble(),
      size.toDouble(),
      size.toDouble(),
    );
    return cell.intersect(_contentPixels);
  }

  /// 타일을 화면 픽셀 1개가 이미지 픽셀 1개가 되게 굽는다. 흐림은 [Opacity] 위젯과
  /// 같은 엔진 불투명도 레이어(같은 정수 알파)로 만든다.
  ui.Image rasterize(RouteMapBasemapTileKey key) {
    final pixels = tilePixels(key);
    final pixelScale = content.pixelScale;
    final builder = ui.SceneBuilder()
      ..pushTransform(
        (Matrix4.translationValues(
          phase.dx - pixels.left,
          phase.dy - pixels.top,
          0,
        )..scaleByDouble(pixelScale, pixelScale, 1, 1)).storage,
      );
    final highlight = content.overlay;
    if (highlight == null) {
      builder.addPicture(Offset.zero, content.basemap);
    } else {
      builder
        ..pushOpacity(Color.getAlphaFromOpacity(kRouteMapFadedBasemapOpacity))
        ..addPicture(Offset.zero, content.basemap)
        ..pop()
        ..addPicture(Offset.zero, highlight);
    }
    final scene = (builder..pop()).build();
    try {
      return scene.toImageSync(pixels.width.toInt(), pixels.height.toInt());
    } finally {
      scene.dispose();
    }
  }
}

/// [width]×[height] RGBA 이미지와 밉맵 사슬이 쓰는 바이트. Impeller는 Picture를 이미지로
/// 구울 때 밉맵을 늘 만든다(shell/common/snapshot_controller_impeller.cc
/// DoMakeRasterSnapshot의 generate_mips=true, impeller/geometry/size.h MipCount).
int routeMapTileBytes(int width, int height) {
  var bytes = 0;
  var w = width;
  var h = height;
  while (true) {
    bytes += w * h * 4;
    if (w == 1 && h == 1) {
      return bytes;
    }
    w = math.max(1, w ~/ 2);
    h = math.max(1, h ~/ 2);
  }
}

/// 지금 화면에 보이는 구운 타일. 모두 합쳐 [maxBytes]를 넘지 않는다.
class RouteMapBasemapTileCache {
  RouteMapBasemapTileCache({this.maxBytes = kRouteMapBasemapTileCacheBytes});

  final int maxBytes;
  final Map<RouteMapBasemapTileKey, ({ui.Image image, int bytes})> _tiles = {};
  int _bytes = 0;

  int get bytes => _bytes;
  int get length => _tiles.length;

  ui.Image? operator [](RouteMapBasemapTileKey key) => _tiles[key]?.image;

  /// [bytes]짜리 타일을 더해도 상한 안인지.
  bool fits(int bytes) => _bytes + bytes <= maxBytes;

  void add(RouteMapBasemapTileKey key, ui.Image image, int bytes) {
    _remove(key);
    _tiles[key] = (image: image, bytes: bytes);
    _bytes += bytes;
  }

  /// [keep] 밖 타일을 버린다. [keep]이 null이면 모두 버린다.
  void retainWithin(RouteMapBasemapTileRange? keep) {
    for (final key in _tiles.keys.toList()) {
      if (keep == null || !keep.contains(key)) {
        _remove(key);
      }
    }
  }

  void _remove(RouteMapBasemapTileKey key) {
    final tile = _tiles.remove(key);
    if (tile != null) {
      tile.image.dispose();
      _bytes -= tile.bytes;
    }
  }
}

/// 구운 타일을 카메라 위치에 그린다. 이미지 픽셀 하나가 화면 픽셀 하나라 확대·축소
/// 없이 정수 픽셀로 옮기기만 한다.
class RouteMapBasemapTilePainter extends CustomPainter {
  RouteMapBasemapTilePainter({
    required this.tiles,
    required this.gridOrigin,
    required this.devicePixelRatio,
  });

  /// 그릴 타일과 그 격자 픽셀 영역.
  final List<({ui.Image image, Rect pixels})> tiles;

  /// 격자 픽셀 (0, 0)이 놓이는 화면 픽셀.
  final Offset gridOrigin;
  final double devicePixelRatio;

  static final Paint _paint = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(1 / devicePixelRatio);
    for (final tile in tiles) {
      canvas.drawImage(tile.image, gridOrigin + tile.pixels.topLeft, _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RouteMapBasemapTilePainter oldDelegate) =>
      oldDelegate.gridOrigin != gridOrigin ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      !_sameTiles(oldDelegate.tiles, tiles);

  static bool _sameTiles(
    List<({ui.Image image, Rect pixels})> a,
    List<({ui.Image image, Rect pixels})> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].image, b[i].image) || a[i].pixels != b[i].pixels) {
        return false;
      }
    }
    return true;
  }
}
