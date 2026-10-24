import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

// 노선을 고르면 바탕 전체가 흐려지고, 고른 노선 레이어(노선, 역 심벌, 환승 캡슐,
// 역명)가 그 위에 원래 진하기로 그려진다. 화면에 실제로 그려진 픽셀을 바탕·레이어
// .vec를 따로 그린 기준 이미지와 대조한다.
const _uiSinseolLineId = 'line-30886152e4f8';
const _seoulLine2Id = 'seoul-2';
const _viewport = Size(400, 400);
const _camera = MapCameraState(
  sourceBounds: Rect.fromLTWH(0, 0, 3688, 2972),
  viewportSize: _viewport,
  center: Offset(2230, 880),
  scale: 0.8,
  minScale: 0.1,
  maxScale: 4,
  revision: 1,
);
const _white = 255;
const _channelTolerance = 2;
// 이 값보다 흰색에서 덜 떨어진 채널은 8비트 반올림 오차가 비율을 흔들어 센 값에서 뺀다.
const _minInkDistance = 40;
// 상용 지하철 서비스 노선 선택 화면 캡처의 흐린 칸 색을 흰 바탕과 노선색 사이 비율로
// 역산한 9개 채널의 범위(중앙값 0.22). 구현 상수를 가져오지 않고 따로 적는다.
const _roleModelFadeLow = 0.165;
const _roleModelFadeHigh = 0.28;
final _boundaryKey = GlobalKey();

Widget _map({
  required String region,
  String? lineId,
  String? attributionText,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _boundaryKey,
      child: SizedBox.fromSize(
        size: _viewport,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: RouteMapBasemapView(
            region: region,
            camera: _camera,
            highlightedLineId: lineId,
            attributionText: attributionText,
          ),
        ),
      ),
    ),
  ),
);

/// .vec 로드를 끝내고 벡터로 그린 프레임에서 멈춘다. 시계를 앞으로 돌리지 않아 카메라가
/// 멈춘 뒤 굽는 바탕 이미지(#517)는 아직 만들지 않는다. 구운 이미지가 이 벡터 화면과
/// 같은지는 route_map_basemap_raster_test.dart가 본다.
Future<void> _settleLoads(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<Uint8List> _rgba(Future<ui.Image> Function() render) async {
  final image = await render();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Uint8List> _screen(WidgetTester tester) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => _rgba(() => boundary.toImage())))!;
}

/// [pictures]를 화면과 같은 카메라 변환으로 그린 기준 이미지. [background]가 null이면
/// 투명 바탕이다.
Future<Uint8List> _reference(
  WidgetTester tester,
  List<String> assets, {
  Color? background = const Color(0xFFFFFFFF),
}) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (background != null) {
      canvas.drawColor(background, BlendMode.src);
    }
    final vc = _viewport.center(Offset.zero);
    canvas.translate(
      vc.dx - _camera.center.dx * _camera.scale,
      vc.dy - _camera.center.dy * _camera.scale,
    );
    canvas.scale(_camera.scale);
    final loaded = <PictureInfo>[];
    for (final asset in assets) {
      final info = await vg.loadPicture(AssetBytesLoader(asset), null);
      loaded.add(info);
      canvas.drawPicture(info.picture);
    }
    final picture = recorder.endRecording();
    final bytes = await _rgba(
      () => picture.toImage(_viewport.width.toInt(), _viewport.height.toInt()),
    );
    picture.dispose();
    for (final info in loaded) {
      info.picture.dispose();
    }
    return bytes;
  }))!;
}

Future<String> _overlayAsset(String lineId) async {
  final json = await rootBundle.loadString(
    kRouteMapLineOverlayIndexAssetPath,
    cache: false,
  );
  return RouteMapLineOverlayIndex.parse(
    json,
  ).overlayAssetFor(regionId: 'seoul', lineId: lineId);
}

int _maxChannelDiff(Uint8List a, Uint8List b) {
  var max = 0;
  for (var i = 0; i < a.length; i++) {
    final diff = (a[i] - b[i]).abs();
    if (diff > max) max = diff;
  }
  return max;
}

/// 흐려진 칸의 한 채널이 바탕 기준 이미지의 진하기에서 얼마만큼 남았는지의 비율
/// `(255 - 화면) / (255 - 바탕)`. 흰색에 가까운 채널은 비율이 흔들려 넣지 않는다.
Iterable<double> _observedOpacities(Uint8List screen, Uint8List base, int p) =>
    [0, 1, 2]
        .where((c) => _white - base[p + c] >= _minInkDistance)
        .map((c) => (_white - screen[p + c]) / (_white - base[p + c]));

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// 바탕만 흐려진 칸과 레이어가 덮은 칸을 나눠 센다. 흐려진 칸은 관측한 불투명도의
/// 중앙값을 함께 낸다.
({int faded, double fadedOpacity, int overlay, int wrongOverlay}) _classify({
  required Uint8List screen,
  required Uint8List base,
  required Uint8List overlayAlone,
}) {
  var faded = 0;
  var overlay = 0;
  var wrongOverlay = 0;
  final opacities = <double>[];
  for (var p = 0; p < screen.length; p += 4) {
    final overlayAlpha = overlayAlone[p + 3];
    if (overlayAlpha == 255) {
      overlay++;
      for (var c = 0; c < 3; c++) {
        if ((screen[p + c] - overlayAlone[p + c]).abs() > _channelTolerance) {
          wrongOverlay++;
          break;
        }
      }
    } else if (overlayAlpha == 0 &&
        [0, 1, 2].any((c) => base[p + c] < _white - _minInkDistance)) {
      faded++;
      opacities.addAll(_observedOpacities(screen, base, p));
    }
  }
  return (
    faded: faded,
    fadedOpacity: opacities.isEmpty ? double.nan : _median(opacities),
    overlay: overlay,
    wrongOverlay: wrongOverlay,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const seoulBase = 'assets/datapacks/metro_map_pack/basemap/seoul.vec';
  const busanBase = 'assets/datapacks/metro_map_pack/basemap/busan.vec';

  tearDown(RouteMapBasemapViewState.clearPictureCacheForTest);

  testWidgets('전체 노선은 바탕을 흐리지 않고 그대로 그린다', (tester) async {
    await tester.pumpWidget(_map(region: '수도권'));
    await _settleLoads(tester);

    final screen = await _screen(tester);
    final base = await _reference(tester, [seoulBase]);
    expect(_maxChannelDiff(screen, base), lessThanOrEqualTo(_channelTolerance));
  });

  for (final lineId in [_uiSinseolLineId, _seoulLine2Id]) {
    testWidgets('$lineId를 고르면 바탕은 흐려지고 그 노선 레이어는 원래 진하기다', (tester) async {
      await tester.pumpWidget(_map(region: '수도권', lineId: lineId));
      await _settleLoads(tester);

      final overlayAsset = (await tester.runAsync(
        () => _overlayAsset(lineId),
      ))!;
      final counts = _classify(
        screen: await _screen(tester),
        base: await _reference(tester, [seoulBase]),
        overlayAlone: await _reference(tester, [
          overlayAsset,
        ], background: null),
      );

      expect(counts.faded, greaterThan(5000), reason: '흐려진 다른 노선 칸 수');
      expect(
        counts.fadedOpacity,
        inInclusiveRange(_roleModelFadeLow, _roleModelFadeHigh),
        reason: '흐려진 다른 노선 칸에서 관측한 불투명도 중앙값',
      );
      expect(counts.overlay, greaterThan(1000), reason: '고른 노선 칸 수');
      expect(counts.wrongOverlay, 0, reason: '흐려진 고른 노선 칸 수');
    });
  }

  testWidgets('노선을 골라도 출처 표기는 흐린 바탕 밖에서 원래 진하기로 그린다', (tester) async {
    const attribution = '노선도 출처';
    await tester.pumpWidget(
      _map(
        region: '수도권',
        lineId: _uiSinseolLineId,
        attributionText: attribution,
      ),
    );
    await _settleLoads(tester);

    String? attributionOf(Finder paint) =>
        (tester.widget<CustomPaint>(paint).painter! as RouteMapBasemapPainter)
            .attributionText;
    final faded = find.descendant(
      of: find.byType(Opacity),
      matching: find.byType(CustomPaint),
    );
    final all = find.descendant(
      of: find.byType(RouteMapBasemapView),
      matching: find.byType(CustomPaint),
    );
    expect(faded, findsOneWidget);
    expect(attributionOf(faded), isNull);
    expect(all, findsNWidgets(2));
    expect(attributionOf(all.last), attribution);
  });

  testWidgets('레이어를 읽는 동안에는 고른 척 흐리지 않고 바탕을 그대로 둔다', (tester) async {
    await tester.pumpWidget(_map(region: '수도권'));
    await _settleLoads(tester);
    final base = await _screen(tester);

    await tester.pumpWidget(_map(region: '수도권', lineId: _uiSinseolLineId));

    expect(_maxChannelDiff(await _screen(tester), base), 0);
  });

  testWidgets('한 번 읽은 노선을 다시 고르면 다시 디코드하지 않고 그 프레임에 바로 강조한다', (tester) async {
    await tester.pumpWidget(_map(region: '수도권', lineId: _uiSinseolLineId));
    await _settleLoads(tester);
    final highlighted = await _screen(tester);
    final overlayAsset = (await tester.runAsync(
      () => _overlayAsset(_uiSinseolLineId),
    ))!;
    final state = tester.state<RouteMapBasemapViewState>(
      find.byType(RouteMapBasemapView),
    );
    final decoded = state.debugPictureCache[overlayAsset];

    await tester.pumpWidget(_map(region: '수도권'));
    await tester.pumpWidget(_map(region: '수도권', lineId: _uiSinseolLineId));

    expect(_maxChannelDiff(await _screen(tester), highlighted), 0);
    await _settleLoads(tester);
    expect(state.debugPictureCache[overlayAsset], same(decoded));
  });

  testWidgets('권역을 바꾸면 이전 권역 노선 레이어를 지우고 새 바탕을 그대로 그린다', (tester) async {
    await tester.pumpWidget(_map(region: '수도권', lineId: _uiSinseolLineId));
    await _settleLoads(tester);

    await tester.pumpWidget(_map(region: '부산'));
    await _settleLoads(tester);

    final screen = await _screen(tester);
    final base = await _reference(tester, [busanBase]);
    expect(_maxChannelDiff(screen, base), lessThanOrEqualTo(_channelTolerance));
  });

  group('레이어를 그리지 못하면 오류로 드러내고 바탕을 흐리지 않는다', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    Future<List<FlutterErrorDetails>> pumpCapturingErrors(
      WidgetTester tester,
      String lineId, {
      String region = '수도권',
    }) async {
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(_map(region: region, lineId: lineId));
        await _settleLoads(tester);
      } finally {
        FlutterError.onError = previousOnError;
      }
      return errors;
    }

    Future<void> expectPlainBase(
      WidgetTester tester, {
      String baseAsset = seoulBase,
    }) async {
      final screen = await _screen(tester);
      final base = await _reference(tester, [baseAsset]);
      expect(
        _maxChannelDiff(screen, base),
        lessThanOrEqualTo(_channelTolerance),
      );
    }

    testWidgets('색인에 없는 노선', (tester) async {
      await tester.pumpWidget(_map(region: '수도권', lineId: _seoulLine2Id));
      await _settleLoads(tester);

      final errors = await pumpCapturingErrors(tester, 'line-unknown');

      expect(errors, hasLength(1));
      expect(errors.single.library, 'network_map');
      expect(errors.single.exception, isA<RouteMapLineOverlayMissing>());
      await expectPlainBase(tester);
    });

    testWidgets('고른 노선이 그대로인 채 권역만 바뀜', (tester) async {
      await tester.pumpWidget(_map(region: '수도권', lineId: _uiSinseolLineId));
      await _settleLoads(tester);

      final errors = await pumpCapturingErrors(
        tester,
        _uiSinseolLineId,
        region: '부산',
      );

      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<RouteMapLineOverlayMissing>());
      await expectPlainBase(tester, baseAsset: busanBase);
    });

    testWidgets('바탕 .vec를 읽지 못하면 고른 노선 레이어만 따로 그리지 않는다', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final key = Uri.decodeFull(
              utf8.decode(message!.buffer.asUint8List()),
            );
            if (key == seoulBase) return null;
            return ByteData.sublistView(File(key).readAsBytesSync());
          });

      final errors = await pumpCapturingErrors(tester, _uiSinseolLineId);

      expect(errors, hasLength(1));
      expect(errors.single.context.toString(), contains('seoul.vec'));
      final blank = await _reference(tester, const []);
      expect(_maxChannelDiff(await _screen(tester), blank), 0);
    });

    testWidgets('레이어 .vec를 읽지 못함', (tester) async {
      final overlayAsset = (await tester.runAsync(
        () => _overlayAsset(_uiSinseolLineId),
      ))!;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final key = Uri.decodeFull(
              utf8.decode(message!.buffer.asUint8List()),
            );
            if (key == overlayAsset) return null;
            return ByteData.sublistView(File(key).readAsBytesSync());
          });

      final errors = await pumpCapturingErrors(tester, _uiSinseolLineId);

      expect(errors, hasLength(1));
      expect(errors.single.library, 'network_map');
      expect(errors.single.context.toString(), contains(_uiSinseolLineId));
      await expectPlainBase(tester);
    });
  });
}
