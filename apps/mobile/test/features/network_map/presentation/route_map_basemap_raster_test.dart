import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 같은 배율로 팬하는 동안 바탕을 구운 이미지로 그려도 화면은 벡터로 그린 것과 같아야
// 한다(#517). 팬 거리는 화면 픽셀 단위로 둔다. 소수 픽셀 위치는 이미지가 가장 가까운
// 픽셀로 옮겨 그려 최대 0.5픽셀 어긋날 수 있고, 그 차이는 실기기 비교가 맡는다.
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

RouteMapBasemapRasterPainter? _rasterPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<RouteMapBasemapRasterPainter>()
    .firstOrNull;

/// 카메라가 [kRouteMapBasemapRasterSettleDelay]보다 오래 멈춘 뒤의 프레임.
Future<void> _rest(WidgetTester tester) async {
  await tester.pump(kRouteMapBasemapRasterSettleDelay);
  await tester.pump();
}

/// 바탕을 처음 그린 프레임(벡터)의 화면. 새 key로 새 State를 만들어 이미지를 아직
/// 굽지 않은 상태에서 찍는다.
Future<Uint8List> _vectorScreen(
  WidgetTester tester,
  MapCameraState camera, {
  String? lineId,
}) async {
  await tester.pumpWidget(_map(camera, lineId: lineId, key: UniqueKey()));
  await _settleLoads(tester);
  expect(_rasterPainter(tester), isNull);
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
    testWidgets('$label: 카메라가 멈추면 화면 둘레를 굽고, 그 안의 픽셀 단위 팬은 벡터와 같다', (
      tester,
    ) async {
      // 여유는 화면 크기의 절반(200픽셀)이라 아래 팬은 모두 구운 영역 안이다.
      const pans = [Offset.zero, Offset(37, -21), Offset(-120, 64)];
      final expected = <Uint8List>[
        for (final pan in pans)
          await _vectorScreen(tester, _camera(pan: pan), lineId: lineId),
      ];

      final key = UniqueKey();
      await tester.pumpWidget(_map(_camera(), lineId: lineId, key: key));
      await _settleLoads(tester);
      await _rest(tester);
      final image = _rasterPainter(tester)!.image;
      expect(image.width, lessThanOrEqualTo(_viewport.width * 2));
      expect(image.height, lessThanOrEqualTo(_viewport.height * 2));

      for (var i = 0; i < pans.length; i++) {
        await tester.pumpWidget(
          _map(
            _camera(pan: pans[i]),
            lineId: lineId,
            key: key,
          ),
        );
        expect(
          _rasterPainter(tester)?.image,
          same(image),
          reason: '팬마다 다시 굽지 않는다',
        );
        _expectEdgeOnlyDiff(await _screen(tester), expected[i], '팬 ${pans[i]}');
      }
    });
  }

  testWidgets('카메라가 픽셀 사이에 멈춰도 구운 화면은 벡터와 같은 픽셀에 놓인다', (tester) async {
    const between = Offset(0.37, 0.61);
    final expected = await _vectorScreen(tester, _camera(pan: between));

    await tester.pumpWidget(_map(_camera(pan: between), key: UniqueKey()));
    await _settleLoads(tester);
    await _rest(tester);

    expect(_rasterPainter(tester), isNotNull);
    _expectEdgeOnlyDiff(await _screen(tester), expected, '픽셀 사이 카메라');
  });

  testWidgets('구운 영역 밖으로 팬하면 벡터로 그리고, 멈추면 그 자리를 다시 굽는다', (tester) async {
    const farPan = Offset(260, 0);
    final expected = await _vectorScreen(tester, _camera(pan: farPan));

    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _settleLoads(tester);
    await _rest(tester);
    final first = _rasterPainter(tester)!.image;

    await tester.pumpWidget(_map(_camera(pan: farPan), key: key));
    expect(_rasterPainter(tester), isNull);
    _expectEdgeOnlyDiff(await _screen(tester), expected, '벡터로 그린 프레임');

    await _rest(tester);
    final second = _rasterPainter(tester)!.image;
    expect(second, isNot(same(first)));
    _expectEdgeOnlyDiff(await _screen(tester), expected, '다시 구운 프레임');
  });

  testWidgets('노선을 고르면 이전 이미지를 버리고 벡터로 그린 뒤, 멈추면 강조한 바탕을 굽는다', (tester) async {
    final expected = await _vectorScreen(
      tester,
      _camera(),
      lineId: _uiSinseolLineId,
    );

    final key = UniqueKey();
    await tester.pumpWidget(_map(_camera(), key: key));
    await _settleLoads(tester);
    await _rest(tester);
    final plain = _rasterPainter(tester)!.image;

    await tester.pumpWidget(
      _map(_camera(), lineId: _uiSinseolLineId, key: key),
    );
    await _settleLoads(tester);
    expect(_rasterPainter(tester), isNull);
    expect(plain.debugDisposed, isTrue);

    await _rest(tester);
    expect(_rasterPainter(tester)!.image, isNot(same(plain)));
    _expectEdgeOnlyDiff(await _screen(tester), expected, '강조한 바탕');
  });

  testWidgets('구운 바탕 painter는 그리는 입력이 바뀔 때만 다시 그린다', (tester) async {
    final image = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = const Color(0xFF000000),
      );
      final picture = recorder.endRecording();
      final result = await picture.toImage(4, 4);
      picture.dispose();
      return result;
    }))!;
    final camera = _camera();
    RouteMapBasemapRasterPainter painter({
      MapCameraState? movedCamera,
      Rect sourceRect = const Rect.fromLTWH(0, 0, 4, 4),
      double devicePixelRatio = 1,
      Offset sourceOrigin = Offset.zero,
      String? attributionText,
    }) => RouteMapBasemapRasterPainter(
      image: image,
      sourceRect: sourceRect,
      devicePixelRatio: devicePixelRatio,
      camera: movedCamera ?? camera,
      sourceOrigin: sourceOrigin,
      attributionText: attributionText,
    );
    final base = painter();

    expect(painter().shouldRepaint(base), isFalse);
    expect(
      painter(
        movedCamera: _camera(pan: const Offset(1, 0)),
      ).shouldRepaint(base),
      isTrue,
    );
    expect(
      painter(sourceRect: const Rect.fromLTWH(1, 0, 4, 4)).shouldRepaint(base),
      isTrue,
    );
    expect(painter(devicePixelRatio: 2).shouldRepaint(base), isTrue);
    expect(
      painter(sourceOrigin: const Offset(1, 0)).shouldRepaint(base),
      isTrue,
    );
    expect(painter(attributionText: '출처').shouldRepaint(base), isTrue);
    image.dispose();
  });

  testWidgets('배율이 바뀌는 동안은 굽지 않고 벡터로 그린다', (tester) async {
    await tester.pumpWidget(_map(_camera()));
    await _settleLoads(tester);
    for (final scale in [0.52, 0.54, 0.56, 0.58]) {
      await tester.pumpWidget(_map(_camera(scale: scale)));
      await tester.pump(kRouteMapBasemapRasterSettleDelay ~/ 2);
      expect(_rasterPainter(tester), isNull, reason: 'scale $scale');
    }

    await _rest(tester);

    expect(_rasterPainter(tester), isNotNull);
  });

  testWidgets('구울 영역 한 변이 4096픽셀을 넘으면 벡터로만 그린다', (tester) async {
    // 화면 2100픽셀에 여유를 더하면 굽는 영역이 4200픽셀이다.
    const viewport = Size(2100, 2100);
    _setView(viewport);
    await tester.pumpWidget(_map(_camera(scale: 1.5, viewport: viewport)));
    await _settleLoads(tester);
    await _rest(tester);

    expect(_rasterPainter(tester), isNull);
  });
}
