import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_tiles.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _tile = kRouteMapBasemapTileSize;

RouteMapBasemapTileGrid _grid({
  Size basemapSize = const Size(1000, 600),
  double scale = 1,
  Offset phase = Offset.zero,
}) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  return RouteMapBasemapTileGrid(
    content: RouteMapBasemapTileContent(
      basemap: recorder.endRecording(),
      basemapSize: basemapSize,
      overlay: null,
      scale: scale,
      devicePixelRatio: 1,
    ),
    phase: phase,
  );
}

void main() {
  group('routeMapTileBytes', () {
    test('256픽셀 타일은 밉맵 사슬까지 349,524바이트다', () {
      expect(routeMapTileBytes(256, 256), 349524);
    });

    test('정사각이 아닌 가장자리 타일은 짧은 변이 1이 된 뒤에도 긴 변이 1이 될 때까지 센다', () {
      expect(routeMapTileBytes(4, 1), (4 * 1 + 2 * 1 + 1 * 1) * 4);
    });

    test('Galaxy A17 화면에 보이는 최대 6×7장이 상한 안에 든다', () {
      expect(
        42 * routeMapTileBytes(_tile, _tile),
        lessThanOrEqualTo(kRouteMapBasemapTileCacheBytes),
      );
      expect(
        43 * routeMapTileBytes(_tile, _tile),
        greaterThan(kRouteMapBasemapTileCacheBytes),
      );
    });
  });

  group('RouteMapBasemapTileGrid', () {
    test('격자를 만든 카메라의 소수 픽셀이 위상이 되고, 그 카메라에서 격자 원점은 정수 픽셀이다', () {
      final grid = RouteMapBasemapTileGrid.at(
        _grid().content,
        const Offset(-10.25, 3.75),
      );

      expect(grid.phase, const Offset(0.75, 0.75));
      expect(
        grid.gridOriginOnScreen(const Offset(-10.25, 3.75)),
        const Offset(-11, 3),
      );
      expect(
        grid.gridOriginOnScreen(const Offset(-10.25 + 0.6, 3.75 - 0.4)),
        const Offset(-10, 3),
      );
    });

    test('보이는 범위는 바탕이 있는 칸으로 자른다', () {
      final grid = _grid();

      final range = grid.visibleRange(
        const Offset(-300, 100),
        const Size(400, 400),
      )!;

      expect((range.left, range.top, range.right, range.bottom), (1, 0, 2, 1));
    });

    test('바탕이 화면 밖이면 보이는 타일이 없다', () {
      expect(
        _grid().visibleRange(const Offset(500, 0), const Size(400, 400)),
        isNull,
      );
    });

    test('가장자리 타일은 바탕까지만 잘라 굽는다', () {
      final grid = _grid(phase: const Offset(0.5, 0));

      expect(
        grid.tilePixels((column: 3, row: 2)),
        const Rect.fromLTRB(768, 512, 1001, 600),
      );
      expect(
        grid.tilePixels((column: 0, row: 0)),
        const Rect.fromLTWH(0, 0, 256, 256),
      );
    });

    test('타일은 그 칸의 격자 픽셀 크기로 굽는다', () {
      final grid = _grid(basemapSize: const Size(300, 100));

      final image = grid.rasterize((column: 1, row: 0));

      expect((image.width, image.height), (44, 100));
      image.dispose();
    });
  });

  test('범위는 가운데 타일부터 돌려준다', () {
    const range = RouteMapBasemapTileRange(
      left: 0,
      top: 0,
      right: 2,
      bottom: 2,
    );

    final keys = range.keysFromCenter();

    expect(keys.first, (column: 1, row: 1));
    expect(keys, hasLength(9));
    expect(keys.toSet(), hasLength(9));
  });

  group('RouteMapBasemapTileCache', () {
    ui.Image image() {
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      return recorder.endRecording().toImageSync(1, 1);
    }

    test('상한을 넘는 타일은 들어갈 수 없다', () {
      final cache = RouteMapBasemapTileCache(maxBytes: 10)
        ..add((column: 0, row: 0), image(), 6);

      expect(cache.fits(4), isTrue);
      expect(cache.fits(5), isFalse);
    });

    test('같은 자리에 다시 넣으면 이전 이미지를 버리고 바이트를 다시 센다', () {
      final first = image();
      final cache = RouteMapBasemapTileCache(maxBytes: 10)
        ..add((column: 0, row: 0), first, 6)
        ..add((column: 0, row: 0), image(), 3);

      expect(first.debugDisposed, isTrue);
      expect((cache.length, cache.bytes), (1, 3));
    });

    test('범위 밖 타일을 버리고, 범위가 없으면 모두 버린다', () {
      final outside = image();
      final cache = RouteMapBasemapTileCache()
        ..add((column: 0, row: 0), image(), 1)
        ..add((column: 5, row: 0), outside, 1);

      cache.retainWithin(
        const RouteMapBasemapTileRange(left: 0, top: 0, right: 1, bottom: 1),
      );

      expect(outside.debugDisposed, isTrue);
      expect(cache[(column: 0, row: 0)], isNotNull);
      expect(cache[(column: 5, row: 0)], isNull);
      cache.retainWithin(null);
      expect((cache.length, cache.bytes), (0, 0));
    });
  });
}
