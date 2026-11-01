import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_tiles.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_waits.dart';

// 같은 배율로 팬하는 동안 바탕을 구운 타일로 그려도 화면은 벡터로 그린 것과 같아야
// 한다(#517). 타일 이음매와, 아직 굽지 않아 벡터로 채운 칸도 같은 화면이어야 한다.
// 팬 거리는 화면 픽셀 단위로 둔다. 소수 픽셀 위치는 타일을 가장 가까운 화면 픽셀로 옮겨
// 그려 최대 0.5픽셀 어긋날 수 있다.
//
// 같은 그림도 화면 픽셀 정수만큼 옮겨 그리면 안티앨리어싱 표본이 경계에 걸린 픽셀이 조금
// 달라진다. 채널 차 1~32의 작은 차이는 렌더러 플랫폼마다 양이 달라(같은 비교가 macOS
// 0.59%, CI Linux 1.10%) 판정에 쓰지 않는다. 2026-10-25 macOS 실측(화면 밀도
// 1·2·2.625·2.8125·3배, 전체·고른 노선): 구운 타일과 벡터는 채널 차 32 초과 최대 0.047%,
// 64 초과 최대 0.001%다. 격자가 화면 픽셀에서 0.25픽셀 이상 어긋나면 32 초과가 0.248%
// 이상, 64 초과가 0.017% 이상이다.
const _maxBeyondEighthShare = 0.001;
const _maxBeyondQuarterShare = 0.0001;
const _viewport = Size(400, 400);
const _uiSinseolLineId = 'line-30886152e4f8';

/// 확인할 화면 밀도. 2.625와 3은 흔한 안드로이드 밀도(420·480dpi)다.
const _devicePixelRatios = [1.0, 2.0, 2.625, 3.0];

/// Galaxy A17 화면 밀도(450dpi). 논리 픽셀 정수 위치가 화면 픽셀 사이에 놓인다.
const _galaxyA17DevicePixelRatio = 2.8125;
final _boundaryKey = GlobalKey();

var _devicePixelRatio = 1.0;

/// [pan]은 화면 픽셀 거리다.
MapCameraState _camera({
  double scale = 0.5,
  Offset pan = Offset.zero,
  Size viewport = _viewport,
}) => MapCameraState(
  sourceBounds: const Rect.fromLTWH(0, 0, 3688, 2972),
  viewportSize: viewport,
  center: const Offset(2230, 880) + pan / _devicePixelRatio / scale,
  scale: scale,
  minScale: 0.1,
  maxScale: 4,
  revision: 1,
);

/// [top]은 지도 위 여백(논리 픽셀)이다. 앱처럼 지도 밖은 잘라 그린다.
Widget _map(
  MapCameraState camera, {
  String? lineId,
  Key? key,
  double top = 0,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _boundaryKey,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: ClipRect(
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
    ),
  ),
);

Future<Uint8List> _screen(WidgetTester tester) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _devicePixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }))!;
}

/// 채널 차가 32(덮임 1/8)와 64(덮임 1/4)를 넘는 픽셀의 비율.
({double beyondEighth, double beyondQuarter}) _pixelDiff(
  Uint8List a,
  Uint8List b,
) {
  var beyondEighth = 0;
  var beyondQuarter = 0;
  for (var p = 0; p < a.length; p += 4) {
    var pixelMax = 0;
    for (var c = 0; c < 4; c++) {
      final diff = (a[p + c] - b[p + c]).abs();
      if (diff > pixelMax) pixelMax = diff;
    }
    if (pixelMax > 32) beyondEighth++;
    if (pixelMax > 64) beyondQuarter++;
  }
  final pixels = a.length ~/ 4;
  return (
    beyondEighth: beyondEighth / pixels,
    beyondQuarter: beyondQuarter / pixels,
  );
}

RouteMapBasemapTilePainter? _tilePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<RouteMapBasemapTilePainter>()
    .firstOrNull;

/// 뷰가 [lineId]에 맞는 그림(바탕, 노선을 골랐으면 노선 레이어까지)을 모두 그릴 때까지 기다린다.
Future<void> _paintLoaded(WidgetTester tester, {String? lineId}) =>
    pumpUntilBasemapPainted(tester, count: lineId == null ? 1 : 2);

/// 카메라가 [kRouteMapBasemapRasterSettleDelay] 동안 멈춰 격자를 만든 프레임.
Future<void> _rest(WidgetTester tester) =>
    tester.pump(kRouteMapBasemapRasterSettleDelay);

/// 바탕을 처음 그린 프레임(벡터)의 화면. 새 key로 새 State를 만들어 격자를 아직
/// 만들지 않은 상태에서 찍는다.
Future<Uint8List> _vectorScreen(
  WidgetTester tester,
  MapCameraState camera, {
  String? lineId,
}) async {
  await tester.pumpWidget(_map(camera, lineId: lineId, key: UniqueKey()));
  await _paintLoaded(tester, lineId: lineId);
  expect(_tilePainter(tester), isNull);
  return _screen(tester);
}

void _expectSameScreen(Uint8List actual, Uint8List expected, String reason) {
  final diff = _pixelDiff(actual, expected);
  expect(
    diff.beyondEighth,
    lessThanOrEqualTo(_maxBeyondEighthShare),
    reason: reason,
  );
  expect(
    diff.beyondQuarter,
    lessThanOrEqualTo(_maxBeyondQuarterShare),
    reason: reason,
  );
}

/// 위 여백 [top]을 뺀 지도 화면. 여백은 양쪽 모두 비어 있어 다른 픽셀 비율을 묽게 한다.
Uint8List _belowTop(Uint8List screen, double top) => Uint8List.sublistView(
  screen,
  (top * _devicePixelRatio).ceil() *
      (_viewport.width * _devicePixelRatio).ceil() *
      4,
);

/// [logicalSize] 논리 픽셀 화면을 [devicePixelRatio]배 밀도로 둔다.
void _setView(Size logicalSize, {double devicePixelRatio = 1}) {
  _devicePixelRatio = devicePixelRatio;
  TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
    ..devicePixelRatio = devicePixelRatio
    ..physicalSize = logicalSize * devicePixelRatio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _setView(const Size(800, 800));
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetDevicePixelRatio()
      ..resetPhysicalSize();
    RouteMapBasemapAssets.shared.resetForTest();
  });

  for (final devicePixelRatio in _devicePixelRatios) {
    group('화면 밀도 $devicePixelRatio배', () {
      setUp(() => _setView(_viewport, devicePixelRatio: devicePixelRatio));

      for (final lineId in [null, _uiSinseolLineId]) {
        final label = lineId == null ? '전체 노선' : '고른 노선';
        testWidgets('$label: 멈추면 타일을 한 프레임에 한 장씩 굽고, 팬한 화면은 벡터와 같다', (
          tester,
        ) async {
          // 256픽셀 타일이라 화면 안에 이음매가 있다. 세 번째 팬은 새 타일을 드러내고, 그
          // 프레임은 아직 없는 타일 칸을 벡터로 채운다.
          const pans = [Offset.zero, Offset(37, -21), Offset(300, 64)];
          final expected = <Uint8List>[
            for (final pan in pans)
              await _vectorScreen(tester, _camera(pan: pan), lineId: lineId),
          ];

          final key = UniqueKey();
          await tester.pumpWidget(_map(_camera(), lineId: lineId, key: key));
          await _paintLoaded(tester, lineId: lineId);
          await _rest(tester);
          final counts = await bakeAllBasemapTiles(tester);
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
            _expectSameScreen(
              await _screen(tester),
              expected[i],
              '팬 ${pans[i]}',
            );
          }
          expect(
            drawsBasemapTileGaps(tester),
            isTrue,
            reason: '새로 드러난 타일은 아직 벡터',
          );

          await bakeAllBasemapTiles(tester);
          _expectSameScreen(await _screen(tester), expected.last, '다 구운 팬');
        });
      }

      testWidgets('카메라가 픽셀 사이에 멈춰도 구운 화면은 벡터와 같은 픽셀에 놓인다', (tester) async {
        const between = Offset(0.37, 0.61);
        final expected = await _vectorScreen(tester, _camera(pan: between));

        await tester.pumpWidget(_map(_camera(pan: between), key: UniqueKey()));
        await _paintLoaded(tester);
        await _rest(tester);
        await bakeAllBasemapTiles(tester);

        _expectSameScreen(await _screen(tester), expected, '픽셀 사이 카메라');
      });
    });
  }

  group('지도가 화면 픽셀 사이에 놓인 화면(Galaxy A17 밀도)', () {
    // 위 여백 183 논리 픽셀은 2.8125배에서 514.6875 화면 픽셀이다.
    const top = 183.0;
    setUp(
      () => _setView(
        _viewport + const Offset(0, top),
        devicePixelRatio: _galaxyA17DevicePixelRatio,
      ),
    );

    for (final lineId in [null, _uiSinseolLineId]) {
      final label = lineId == null ? '전체 노선' : '고른 노선';
      testWidgets('$label: 구운 화면은 벡터와 같다', (tester) async {
        // 세 번째 팬은 새 타일을 드러내 아직 없는 칸을 벡터로 채운다.
        const pans = [Offset.zero, Offset(37, -21), Offset(300, 64)];
        final expected = <Uint8List>[];
        for (final pan in pans) {
          await tester.pumpWidget(
            _map(
              _camera(pan: pan),
              lineId: lineId,
              key: UniqueKey(),
              top: top,
            ),
          );
          await _paintLoaded(tester, lineId: lineId);
          expect(_tilePainter(tester), isNull);
          expected.add(await _screen(tester));
        }

        final key = UniqueKey();
        await tester.pumpWidget(
          _map(_camera(), lineId: lineId, key: key, top: top),
        );
        await _paintLoaded(tester, lineId: lineId);
        await _rest(tester);
        await bakeAllBasemapTiles(tester);
        for (var i = 0; i < pans.length; i++) {
          await tester.pumpWidget(
            _map(
              _camera(pan: pans[i]),
              lineId: lineId,
              key: key,
              top: top,
            ),
          );
          _expectSameScreen(
            _belowTop(await _screen(tester), top),
            _belowTop(expected[i], top),
            '팬 ${pans[i]}',
          );
        }
        expect(
          drawsBasemapTileGaps(tester),
          isTrue,
          reason: '새로 드러난 타일은 아직 벡터',
        );
      });
    }

    testWidgets('팬이 화면 픽셀 사이에서 멈춰도 타일은 화면 정수 픽셀에 놓인다', (tester) async {
      final key = UniqueKey();
      await tester.pumpWidget(_map(_camera(), key: key, top: top));
      await _paintLoaded(tester);
      await _rest(tester);
      await bakeAllBasemapTiles(tester);

      for (final pan in const [Offset(0.37, 0.61), Offset(-41.2, 17.5)]) {
        await tester.pumpWidget(
          _map(
            _camera(pan: pan),
            key: key,
            top: top,
          ),
        );
        final onScreen =
            _tilePainter(tester)!.gridOrigin +
            const Offset(0, top) * _galaxyA17DevicePixelRatio;
        expect(onScreen.dx, onScreen.dx.roundToDouble(), reason: '팬 $pan');
        expect(onScreen.dy, onScreen.dy.roundToDouble(), reason: '팬 $pan');
      }
    });
  });

  testWidgets('같은 배율의 팬은 남은 타일을 다시 굽지 않고, 화면을 벗어난 타일은 버린다', (tester) async {
    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _paintLoaded(tester);
    await _rest(tester);
    await bakeAllBasemapTiles(tester);
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

  testWidgets('노선을 고르면 타일을 버리고 벡터로 그린 뒤, 멈추면 강조한 바탕을 굽는다', (tester) async {
    final expected = await _vectorScreen(
      tester,
      _camera(),
      lineId: _uiSinseolLineId,
    );

    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _paintLoaded(tester);
    await _rest(tester);
    await bakeAllBasemapTiles(tester);
    final plain = _tilePainter(tester)!.tiles.map((tile) => tile.image);

    await tester.pumpWidget(
      _map(_camera(), lineId: _uiSinseolLineId, key: key),
    );
    await _paintLoaded(tester, lineId: _uiSinseolLineId);
    expect(_tilePainter(tester), isNull);
    expect(plain.every((image) => image.debugDisposed), isTrue);

    await _rest(tester);
    await bakeAllBasemapTiles(tester);
    _expectSameScreen(await _screen(tester), expected, '강조한 바탕');
  });

  testWidgets('배율이 바뀌는 동안은 굽지 않고 벡터로 그린다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _paintLoaded(tester);
    for (final scale in [0.52, 0.54, 0.56, 0.58]) {
      await tester.pumpWidget(_map(_camera(scale: scale)));
      await tester.pump(kRouteMapBasemapRasterSettleDelay ~/ 2);
      expect(_tilePainter(tester), isNull, reason: 'scale $scale');
    }

    await _rest(tester);

    expect(_tilePainter(tester), isNotNull);
  });

  testWidgets('카메라가 멈추면 보이는 타일 수만큼만 프레임을 요청하고 그 뒤로는 멈춘다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _paintLoaded(tester);
    await _rest(tester);

    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames < 100) {
      await tester.pump();
      frames++;
    }

    final visible = _tilePainter(tester)!.tiles.length;
    expect(visible, greaterThan(1));
    expect(drawsBasemapTileGaps(tester), isFalse, reason: '보이는 타일을 모두 굽는다');
    expect(frames, lessThanOrEqualTo(visible), reason: '프레임마다 한 장');
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '다 굽고 나면 요청 없음');
  });

  testWidgets('보이는 타일이 상한을 넘는 큰 화면은 상한까지만 굽고 나머지는 벡터로 그린다', (tester) async {
    // 2100픽셀 화면은 256픽셀 타일 9×9장(약 28 MB)이 보여 상한 14 MiB를 넘는다.
    const viewport = Size(2100, 2100);
    _setView(viewport);
    await tester.pumpWidget(_map(_camera(scale: 1.5, viewport: viewport)));
    await _paintLoaded(tester);
    await _rest(tester);
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump();
    }

    final baked = _tilePainter(tester)!.tiles;
    final bakedBytes = baked.fold<int>(
      0,
      (sum, tile) =>
          sum +
          routeMapTileBytes(
            tile.pixels.width.toInt(),
            tile.pixels.height.toInt(),
          ),
    );
    expect(baked, isNotEmpty);
    expect(bakedBytes, lessThanOrEqualTo(kRouteMapBasemapTileCacheBytes));
    expect(
      bakedBytes + routeMapTileBytes(256, 256),
      greaterThan(kRouteMapBasemapTileCacheBytes),
      reason: '한 장도 더 들어가지 않는다',
    );
    expect(drawsBasemapTileGaps(tester), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '더 굽지 않는다');
  });

  testWidgets('메모리가 부족해도 보이는 타일은 그대로 두고 다시 굽지 않는다', (tester) async {
    // MapLibre Native TilePyramid::reduceMemoryUse는 렌더하지 않는 캐시만 비운다. 이 캐시에는
    // 보이는 타일만 있으니 버릴 것이 없다. 버리면 같은 타일을 곧바로 다시 굽는다.
    await tester.pumpWidget(_map(_camera()));
    await _paintLoaded(tester);
    await _rest(tester);
    await bakeAllBasemapTiles(tester);
    final images = _tilePainter(
      tester,
    )!.tiles.map((tile) => tile.image).toList();

    tester.binding.handleMemoryPressure();
    await tester.pump();

    expect(images.any((image) => image.debugDisposed), isFalse);
    expect(drawsBasemapTileGaps(tester), isFalse);
    expect(
      _tilePainter(tester)!.tiles.map((tile) => tile.image),
      orderedEquals(images),
    );
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '다시 굽지 않는다');
  });

  testWidgets('바탕이 화면을 벗어나면 타일을 모두 버리고 아무것도 그리지 않는다', (tester) async {
    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _paintLoaded(tester);
    await _rest(tester);
    await bakeAllBasemapTiles(tester);

    await tester.pumpWidget(
      _map(_camera(pan: const Offset(-5000, 0)), key: key),
    );

    expect(_tilePainter(tester)!.tiles, isEmpty);
    expect(drawsBasemapTileGaps(tester), isFalse);
  });

  testWidgets('뷰는 바탕을 떠나면 굽은 타일을 버린다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _paintLoaded(tester);
    await _rest(tester);
    await bakeAllBasemapTiles(tester);
    final images = _tilePainter(tester)!.tiles.map((tile) => tile.image);
    expect(images, isNotEmpty);

    await tester.pumpWidget(const SizedBox());

    expect(images.every((image) => image.debugDisposed), isTrue);
  });

  testWidgets('대기 중인 격자가 있는 채로 뷰가 사라져도 settle 지연이 지나도록 오류가 없다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _paintLoaded(tester);
    await tester.pumpWidget(_map(_camera(scale: 0.52)));
    expect(_tilePainter(tester), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(kRouteMapBasemapRasterSettleDelay * 2);

    expect(tester.takeException(), isNull);
  });

  testWidgets('대기 중인 격자가 있는 채로 뷰가 사라지면 타이머가 남지 않는다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _paintLoaded(tester);
    await tester.pumpWidget(_map(_camera(scale: 0.52)));

    await tester.pumpWidget(const SizedBox());
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
