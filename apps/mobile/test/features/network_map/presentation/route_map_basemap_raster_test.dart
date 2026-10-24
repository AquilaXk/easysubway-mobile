import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_tiles.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 같은 배율로 팬하는 동안 바탕을 구운 타일로 그려도 화면은 벡터로 그린 것과 같아야
// 한다(#517). 타일 이음매와, 아직 굽지 않아 벡터로 채운 칸도 같은 화면이어야 한다.
// 팬 거리는 화면 픽셀 단위로 둔다. 소수 픽셀 위치는 타일을 가장 가까운 픽셀로 옮겨
// 그려 최대 0.5픽셀 어긋날 수 있고, 그 차이는 실기기 비교가 맡는다.
//
// 같은 경로라도 화면 위치가 다르면 곡선·꺾임 경계 픽셀의 안티앨리어싱이 조금 달라진다
// (2026-10-24 실측: 400x400 화면에서 791픽셀(0.49%), 최대 채널 차 36). 경계 픽셀만
// 다르다는 것을 아래 두 허용치로 확인한다.
const _maxEdgePixelShare = 0.01;
const _maxEdgeChannelDiff = 64;
const _viewport = Size(400, 400);
const _uiSinseolLineId = 'line-30886152e4f8';
final _boundaryKey = GlobalKey();

MapCameraState _camera({
  double scale = 0.5,
  Offset pan = Offset.zero,
  Size viewport = _viewport,
}) => MapCameraState(
  sourceBounds: const Rect.fromLTWH(0, 0, 3688, 2972),
  viewportSize: viewport,
  center: const Offset(2230, 880) + pan / scale,
  scale: scale,
  minScale: 0.1,
  maxScale: 4,
  revision: 1,
);

Widget _map(MapCameraState camera, {String? lineId, Key? key}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: SizedBox.fromSize(
            size: camera.viewportSize,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: RouteMapBasemapView(
                key: key,
                region: '수도권',
                camera: camera,
                highlightedLineId: lineId,
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _settleLoads(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<Uint8List> _screen(WidgetTester tester) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }))!;
}

/// 채널 차가 1을 넘는 픽셀의 비율과 가장 큰 채널 차.
({double share, int max}) _pixelDiff(Uint8List a, Uint8List b) {
  var differing = 0;
  var max = 0;
  for (var p = 0; p < a.length; p += 4) {
    var pixelMax = 0;
    for (var c = 0; c < 4; c++) {
      final diff = (a[p + c] - b[p + c]).abs();
      if (diff > pixelMax) pixelMax = diff;
    }
    if (pixelMax > 1) differing++;
    if (pixelMax > max) max = pixelMax;
  }
  return (share: differing / (a.length ~/ 4), max: max);
}

RouteMapBasemapTilePainter? _tilePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<RouteMapBasemapTilePainter>()
    .firstOrNull;

/// 아직 굽지 않은 타일 자리를 벡터로 그리는 중인지.
bool _drawsGaps(WidgetTester tester) => find
    .descendant(
      of: find.byType(RouteMapBasemapView),
      matching: find.byType(ClipPath),
    )
    .evaluate()
    .isNotEmpty;

RouteMapBasemapTileCache _tiles(WidgetTester tester) => tester
    .state<RouteMapBasemapViewState>(find.byType(RouteMapBasemapView))
    .debugTiles;

/// 카메라가 [kRouteMapBasemapRasterSettleDelay] 동안 멈춰 격자를 만든 프레임.
Future<void> _rest(WidgetTester tester) =>
    tester.pump(kRouteMapBasemapRasterSettleDelay);

/// 보이는 타일을 다 구울 때까지 프레임을 돌린다. 굽은 타일 수를 프레임마다 센다.
Future<List<int>> _bakeAll(WidgetTester tester) async {
  final counts = <int>[];
  for (var frame = 0; frame < 50 && _drawsGaps(tester); frame++) {
    counts.add(_tiles(tester).length);
    await tester.pump();
  }
  expect(_drawsGaps(tester), isFalse, reason: '보이는 타일을 모두 굽는다');
  return counts;
}

/// 바탕을 처음 그린 프레임(벡터)의 화면. 새 key로 새 State를 만들어 격자를 아직
/// 만들지 않은 상태에서 찍는다.
Future<Uint8List> _vectorScreen(
  WidgetTester tester,
  MapCameraState camera, {
  String? lineId,
}) async {
  await tester.pumpWidget(_map(camera, lineId: lineId, key: UniqueKey()));
  await _settleLoads(tester);
  expect(_tilePainter(tester), isNull);
  return _screen(tester);
}

void _expectEdgeOnlyDiff(Uint8List actual, Uint8List expected, String reason) {
  final diff = _pixelDiff(actual, expected);
  expect(diff.share, lessThanOrEqualTo(_maxEdgePixelShare), reason: reason);
  expect(diff.max, lessThanOrEqualTo(_maxEdgeChannelDiff), reason: reason);
}

void _setView(Size physicalSize) {
  TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
    ..devicePixelRatio = 1
    ..physicalSize = physicalSize;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => _setView(const Size(800, 800)));
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetDevicePixelRatio()
      ..resetPhysicalSize();
    RouteMapBasemapViewState.clearPictureCacheForTest();
  });

  for (final lineId in [null, _uiSinseolLineId]) {
    final label = lineId == null ? '전체 노선' : '고른 노선';
    testWidgets('$label: 멈추면 타일을 한 프레임에 한 장씩 굽고, 팬한 화면은 벡터와 같다', (
      tester,
    ) async {
      // 400픽셀 화면에 256픽셀 타일이라 화면 안에 이음매가 있다. 두 번째 팬은 새 타일을
      // 드러내고, 그 프레임은 아직 없는 타일 칸을 벡터로 채운다.
      const pans = [Offset.zero, Offset(37, -21), Offset(300, 64)];
      final expected = <Uint8List>[
        for (final pan in pans)
          await _vectorScreen(tester, _camera(pan: pan), lineId: lineId),
      ];

      final key = UniqueKey();
      await tester.pumpWidget(_map(_camera(), lineId: lineId, key: key));
      await _settleLoads(tester);
      await _rest(tester);
      final counts = await _bakeAll(tester);
      expect(counts.first, 1, reason: '격자를 만든 프레임에 한 장');
      expect(
        [for (var i = 1; i < counts.length; i++) counts[i] - counts[i - 1]],
        everyElement(1),
        reason: '프레임마다 한 장',
      );

      for (var i = 0; i < pans.length; i++) {
        await tester.pumpWidget(
          _map(
            _camera(pan: pans[i]),
            lineId: lineId,
            key: key,
          ),
        );
        _expectEdgeOnlyDiff(await _screen(tester), expected[i], '팬 ${pans[i]}');
      }
      expect(_drawsGaps(tester), isTrue, reason: '새로 드러난 타일은 아직 벡터');

      await _bakeAll(tester);
      _expectEdgeOnlyDiff(await _screen(tester), expected.last, '다 구운 팬');
    });
  }

  testWidgets('같은 배율의 팬은 남은 타일을 다시 굽지 않고, 화면을 벗어난 타일은 버린다', (tester) async {
    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _settleLoads(tester);
    await _rest(tester);
    await _bakeAll(tester);
    final before = {
      for (final tile in _tilePainter(tester)!.tiles) tile.pixels: tile.image,
    };

    await tester.pumpWidget(_map(_camera(pan: const Offset(300, 0)), key: key));

    final after = _tilePainter(tester)!.tiles;
    final kept = after.where((tile) => before.containsKey(tile.pixels));
    expect(kept, isNotEmpty);
    for (final tile in kept) {
      expect(tile.image, same(before[tile.pixels]));
    }
    final dropped = before.entries.where(
      (entry) => !after.any((tile) => tile.pixels == entry.key),
    );
    expect(dropped, isNotEmpty);
    for (final entry in dropped) {
      expect(entry.value.debugDisposed, isTrue);
    }
  });

  testWidgets('카메라가 픽셀 사이에 멈춰도 구운 화면은 벡터와 같은 픽셀에 놓인다', (tester) async {
    const between = Offset(0.37, 0.61);
    final expected = await _vectorScreen(tester, _camera(pan: between));

    await tester.pumpWidget(_map(_camera(pan: between), key: UniqueKey()));
    await _settleLoads(tester);
    await _rest(tester);
    await _bakeAll(tester);

    _expectEdgeOnlyDiff(await _screen(tester), expected, '픽셀 사이 카메라');
  });

  testWidgets('노선을 고르면 타일을 버리고 벡터로 그린 뒤, 멈추면 강조한 바탕을 굽는다', (tester) async {
    final expected = await _vectorScreen(
      tester,
      _camera(),
      lineId: _uiSinseolLineId,
    );

    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _settleLoads(tester);
    await _rest(tester);
    await _bakeAll(tester);
    final plain = _tilePainter(tester)!.tiles.map((tile) => tile.image);

    await tester.pumpWidget(
      _map(_camera(), lineId: _uiSinseolLineId, key: key),
    );
    await _settleLoads(tester);
    expect(_tilePainter(tester), isNull);
    expect(_tiles(tester).length, 0);
    expect(plain.every((image) => image.debugDisposed), isTrue);

    await _rest(tester);
    await _bakeAll(tester);
    _expectEdgeOnlyDiff(await _screen(tester), expected, '강조한 바탕');
  });

  testWidgets('배율이 바뀌는 동안은 굽지 않고 벡터로 그린다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _settleLoads(tester);
    for (final scale in [0.52, 0.54, 0.56, 0.58]) {
      await tester.pumpWidget(_map(_camera(scale: scale)));
      await tester.pump(kRouteMapBasemapRasterSettleDelay ~/ 2);
      expect(_tilePainter(tester), isNull, reason: 'scale $scale');
    }

    await _rest(tester);

    expect(_tilePainter(tester), isNotNull);
  });

  testWidgets('보이는 타일이 상한을 넘는 큰 화면은 상한까지만 굽고 나머지는 벡터로 그린다', (tester) async {
    // 2100픽셀 화면은 256픽셀 타일 9×9장(약 28 MB)이 보여 상한 14 MiB를 넘는다.
    const viewport = Size(2100, 2100);
    _setView(viewport);
    await tester.pumpWidget(_map(_camera(scale: 1.5, viewport: viewport)));
    await _settleLoads(tester);
    await _rest(tester);
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump();
    }

    final tiles = _tiles(tester);
    expect(tiles.length, greaterThan(0));
    expect(tiles.bytes, lessThanOrEqualTo(kRouteMapBasemapTileCacheBytes));
    expect(tiles.fits(routeMapTileBytes(256, 256)), isFalse);
    expect(_drawsGaps(tester), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '더 굽지 않는다');
  });

  testWidgets('메모리가 부족하면 타일을 버리고 벡터로 그린 뒤 다시 굽는다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _settleLoads(tester);
    await _rest(tester);
    await _bakeAll(tester);
    final images = _tilePainter(tester)!.tiles.map((tile) => tile.image);

    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(images.every((image) => image.debugDisposed), isTrue);
    expect(_drawsGaps(tester), isTrue);
    await _bakeAll(tester);
  });

  testWidgets('바탕이 화면을 벗어나면 타일을 모두 버리고 아무것도 그리지 않는다', (tester) async {
    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _settleLoads(tester);
    await _rest(tester);
    await _bakeAll(tester);

    await tester.pumpWidget(
      _map(_camera(pan: const Offset(-5000, 0)), key: key),
    );

    expect(_tiles(tester).length, 0);
    expect(_tilePainter(tester)!.tiles, isEmpty);
    expect(_drawsGaps(tester), isFalse);
  });

  testWidgets('바탕을 떠나면 격자 대기를 거두고 타일을 버린다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _settleLoads(tester);
    await _rest(tester);
    final tiles = _tiles(tester);
    expect(tiles.length, 1);
    await tester.pumpWidget(_map(_camera(scale: 0.6)));

    await tester.pumpWidget(const SizedBox());

    expect(tiles.length, 0);
    await tester.pump(kRouteMapBasemapRasterSettleDelay * 2);
  });

  testWidgets('타일 painter는 그리는 입력이 바뀔 때만 다시 그린다', (tester) async {
    final images = (await tester.runAsync(() async {
      Future<ui.Image> image() {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 4, 4),
          Paint()..color = const Color(0xFF000000),
        );
        final picture = recorder.endRecording();
        return picture.toImage(4, 4).whenComplete(picture.dispose);
      }

      return [await image(), await image()];
    }))!;
    const pixels = Rect.fromLTWH(0, 0, 4, 4);
    RouteMapBasemapTilePainter painter({
      List<({ui.Image image, Rect pixels})>? tiles,
      Offset gridOrigin = Offset.zero,
      double devicePixelRatio = 1,
    }) => RouteMapBasemapTilePainter(
      tiles: tiles ?? [(image: images.first, pixels: pixels)],
      gridOrigin: gridOrigin,
      devicePixelRatio: devicePixelRatio,
    );
    final base = painter();

    expect(painter().shouldRepaint(base), isFalse);
    expect(painter(gridOrigin: const Offset(1, 0)).shouldRepaint(base), isTrue);
    expect(painter(devicePixelRatio: 2).shouldRepaint(base), isTrue);
    expect(painter(tiles: const []).shouldRepaint(base), isTrue);
    expect(
      painter(
        tiles: [(image: images.last, pixels: pixels)],
      ).shouldRepaint(base),
      isTrue,
    );
    expect(
      painter(
        tiles: [
          (image: images.first, pixels: pixels.shift(const Offset(4, 0))),
        ],
      ).shouldRepaint(base),
      isTrue,
    );
    for (final image in images) {
      image.dispose();
    }
  });
}
