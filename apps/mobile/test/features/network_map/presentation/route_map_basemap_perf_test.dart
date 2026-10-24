import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_tiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

// #2068 하이브리드 바탕층 성능 계측(계측 위주, 느슨한 assert).
//
// 바탕 .vec 런타임 로드+디코드 시간과 파일 크기를 측정해 print한다. 컴파일 시간은
// 셸 `time`으로 별도 측정하므로 여기에 넣지 않는다. structured recordRouteMapPicture
// 대비 비교는 데이터 로드가 무거워 생략하고 vec 로드만 계측한다(범위 밖 노이즈 회피).
//
// 래스터 프레임 예산은 앱이 쓰는 렌더러인 Impeller에서만 건다. 앱은 Android(Vulkan)와
// iOS(Metal)에서 Impeller로 그리고, `flutter test` 기본 실행은 Skia 소프트웨어
// 래스터라(flutter_tools flutter_tester_device.dart --enable-software-rendering) 기기에
// 없는 CPU 커버리지 계산을 잰다. CI는 이 파일을 `flutter test --enable-impeller`로 한 번
// 더 돌려 예산을 건다(ci.yml "Raster frame budget (Impeller)"). 기본 실행 값은 기록만 한다.
//
// flutter test cwd는 apps/mobile다 — 자산 경로를 그 기준 상대경로로 연다.

/// 엔진이 Impeller로 그리는지. dart:ui가 엔진의 Impeller 설정을 그대로 돌려준다.
final bool _impeller = ui.ImageFilter.isShaderFilterSupported;

/// CI Impeller 게이트 단계가 켠다. 켜졌는데 Impeller가 아니면 예산이 조용히 빠진다.
const bool _impellerGateRun = bool.fromEnvironment(
  'ROUTE_MAP_RASTER_GATE_IMPELLER',
);

String get _renderer => _impeller ? 'Impeller' : 'Skia 소프트웨어(기록만)';

const int _warmupFrames = 5;
const int _sampleFrames = 25;
const double _overviewScale = 0.35;
const int _frameWidth = 1080;
const int _frameHeight = 1920;

/// [frame]을 toImage로 그리는 시간(ms). Impeller의 toImage는 래스터 스레드가 명령을
/// 만들어 제출하면 끝나고 GPU 완료를 기다리지 않는다(impeller/display_list/dl_dispatcher.cc
/// DisplayListToTexture). 그래서 잰 다음 toByteData로 완료를 기다려 다음 표본이 밀린 GPU
/// 일과 겹치지 않게 하고, 그림이 실제로 그려졌는지 바이트 수로 확인한다.
Future<double> _frameMs(ui.Picture frame) async {
  final stopwatch = Stopwatch()..start();
  final image = await frame.toImage(_frameWidth, _frameHeight);
  stopwatch.stop();
  final pixels = await image.toByteData();
  expect(pixels?.lengthInBytes, _frameWidth * _frameHeight * 4);
  image.dispose();
  frame.dispose();
  return stopwatch.elapsedMicroseconds / 1000.0;
}

/// [draw]로 그린 프레임을 워밍업 뒤 [_sampleFrames]장 잰다.
Future<List<double>> _sampleFrameMs(void Function(ui.Canvas) draw) async {
  final samples = <double>[];
  for (var index = 0; index < _warmupFrames + _sampleFrames; index += 1) {
    final recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    final ms = await _frameMs(recorder.endRecording());
    if (index >= _warmupFrames) {
      samples.add(ms);
    }
  }
  return samples;
}

double _percentile(List<double> samples, double q) =>
    (samples.toList()..sort())[(samples.length * q).floor()];

/// CI 러너 가상화 편차를 고려해 CI에서는 33.3ms, 로컬에서는 16.7ms를 적용한다.
void _expectWithinFrameBudget(double p50, String reason) {
  if (!_impeller) {
    return;
  }
  final maxBudget = Platform.environment['CI'] != null ? 33.3 : 16.7;
  expect(p50, lessThan(maxBudget), reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seoulAsset = 'assets/datapacks/metro_map_pack/basemap/seoul.vec';

  test('Impeller 게이트 실행이면 엔진이 Impeller로 그린다', () {
    expect(
      !_impellerGateRun || _impeller,
      isTrue,
      reason: '--enable-impeller 없이 게이트를 돌리면 예산이 걸리지 않는다',
    );
  });

  testWidgets('seoul 바탕 .vec 로드+디코드 시간과 파일 크기 계측', (tester) async {
    // 파일 크기(bytes) — File.lengthSync는 cwd(apps/mobile) 기준 상대경로로 연다.
    final vecFile = File(seoulAsset);
    expect(vecFile.existsSync(), isTrue, reason: '$seoulAsset가 번들에 있어야 한다');
    final sizeBytes = vecFile.lengthSync();

    // 로드+디코드 시간 — 실제 async 자산 로드가 완료되도록 runAsync 안에서 잰다.
    late final Duration loadDuration;
    await tester.runAsync(() async {
      final stopwatch = Stopwatch()..start();
      final info = await vg.loadPicture(
        const AssetBytesLoader(seoulAsset),
        null,
      );
      stopwatch.stop();
      loadDuration = stopwatch.elapsed;
      info.picture.dispose();
    });

    // ignore: avoid_print
    print(
      '[#2068 perf] seoul.vec 크기=${sizeBytes}B(${(sizeBytes / 1024).toStringAsFixed(1)}KB) '
      '로드+디코드=${loadDuration.inMicroseconds}us(${loadDuration.inMilliseconds}ms)',
    );

    // 느슨한 회귀 상한(계측이 주목적) — 로드가 2초를 넘으면 이상 신호.
    expect(loadDuration.inMilliseconds, lessThan(2000));
    expect(sizeBytes, greaterThan(0));
  });

  // #2593 리뷰 Major — 전량 반입으로 새로 들어온 `page-background`(전면 흰 rect)와
  // `background-grid-overlay`(격자 패턴 타일)의 래스터 비용을 계측한다.
  // 대전·광주 오버레이는 `opacity="0.52"`라 실제로 보이는 요소이고, 패턴 타일링이
  // 프레임 시간을 크게 좌우한다(실측: 대전 p90 0.43ms → 1.93ms). 수도권 오버레이는
  // `opacity="0"`이라 사실상 무료다. 상한은 프레임 예산 기준의 느슨한 회귀 감지선이다.
  testWidgets('바탕 .vec 래스터 프레임 시간 p50/p90 계측', (tester) async {
    const targets = <String, String>{
      'seoul': 'assets/datapacks/metro_map_pack/basemap/seoul.vec',
      'daejeon': 'assets/datapacks/metro_map_pack/basemap/daejeon.vec',
    };
    await tester.runAsync(() async {
      for (final entry in targets.entries) {
        final info = await vg.loadPicture(AssetBytesLoader(entry.value), null);
        final samples = await _sampleFrameMs(
          (canvas) => canvas
            ..scale(_overviewScale)
            ..drawPicture(info.picture),
        );
        info.picture.dispose();
        final p50 = _percentile(samples, 0.5);
        // ignore: avoid_print
        print(
          '[#2593 raster] $_renderer ${entry.key}.vec 1080x1920 '
          'p50=${p50.toStringAsFixed(2)}ms '
          'p90=${_percentile(samples, 0.9).toStringAsFixed(2)}ms',
        );
        _expectWithinFrameBudget(p50, '${entry.key}: 래스터 p50이 프레임 예산을 넘었다');
      }
    });
  });

  // 노선 강조(#511): 가장 큰 노선 레이어(수도권 1호선) 디코드 시간과, 흐린 바탕
  // saveLayer + 레이어 그리기가 바탕만 그릴 때보다 래스터를 얼마나 늘리는지 잰다.
  testWidgets('노선 강조 레이어 디코드와 흐린 바탕 래스터 시간 계측', (tester) async {
    const overlayAsset =
        'assets/datapacks/metro_map_pack/basemap/seoul.line-472a81add377.vec';
    await tester.runAsync(() async {
      final decodeMs = <double>[];
      for (var run = 0; run < 7; run += 1) {
        final stopwatch = Stopwatch()..start();
        final info = await vg.loadPicture(
          const AssetBytesLoader(overlayAsset),
          null,
        );
        stopwatch.stop();
        decodeMs.add(stopwatch.elapsedMicroseconds / 1000.0);
        info.picture.dispose();
      }
      final base = await vg.loadPicture(
        const AssetBytesLoader(seoulAsset),
        null,
      );
      final overlay = await vg.loadPicture(
        const AssetBytesLoader(overlayAsset),
        null,
      );
      final fadePaint = ui.Paint()
        ..color = const ui.Color.fromRGBO(
          0,
          0,
          0,
          kRouteMapFadedBasemapOpacity,
        );
      final plain = await _sampleFrameMs(
        (canvas) => canvas
          ..scale(_overviewScale)
          ..drawPicture(base.picture),
      );
      final highlighted = await _sampleFrameMs(
        (canvas) => canvas
          ..scale(_overviewScale)
          ..saveLayer(null, fadePaint)
          ..drawPicture(base.picture)
          ..restore()
          ..drawPicture(overlay.picture),
      );
      base.picture.dispose();
      overlay.picture.dispose();
      // ignore: avoid_print
      print(
        '[#511 overlay] $_renderer seoul 1호선 레이어 '
        '${File(overlayAsset).lengthSync()}B 디코드 '
        'p50=${_percentile(decodeMs, 0.5).toStringAsFixed(2)}ms '
        '범위=${_percentile(decodeMs, 0).toStringAsFixed(2)}~'
        '${(decodeMs.toList()..sort()).last.toStringAsFixed(2)}ms(7회) | '
        '1080x1920 래스터 바탕만 p50=${_percentile(plain, 0.5).toStringAsFixed(2)}'
        ' p90=${_percentile(plain, 0.9).toStringAsFixed(2)}ms, '
        '강조 p50=${_percentile(highlighted, 0.5).toStringAsFixed(2)}'
        ' p90=${_percentile(highlighted, 0.9).toStringAsFixed(2)}ms'
        '($_sampleFrames회)',
      );
      expect(_percentile(decodeMs, 0.5), lessThan(2000));
      _expectWithinFrameBudget(
        _percentile(highlighted, 0.5),
        '강조 래스터 p50이 프레임 예산을 넘었다',
      );
    });
  });

  // 카메라가 멈추면 앱은 바탕을 화면 픽셀 타일로 구워 두고(#518) 팬하는 동안 구운 타일만
  // 그린다. 넓게 본 노선도에서 사용자가 보는 프레임이 이 합성이다. 타일은 앱의 격자로 굽는다.
  testWidgets('구운 바탕 타일 합성 프레임 시간 계측', (tester) async {
    await tester.runAsync(() async {
      final base = await vg.loadPicture(
        const AssetBytesLoader(seoulAsset),
        null,
      );
      final grid = RouteMapBasemapTileGrid(
        content: RouteMapBasemapTileContent(
          basemap: base.picture,
          basemapSize: base.size,
          overlay: null,
          scale: _overviewScale,
          devicePixelRatio: 1,
        ),
        phase: ui.Offset.zero,
      );
      final keys = grid
          .visibleRange(
            ui.Offset.zero,
            ui.Rect.fromLTWH(
              0,
              0,
              _frameWidth.toDouble(),
              _frameHeight.toDouble(),
            ),
          )!
          .keysFromCenter();
      final tiles = [
        for (final key in keys)
          (image: grid.rasterize(key), pixels: grid.tilePixels(key)),
      ];
      for (final tile in tiles) {
        expect(await tile.image.toByteData(), isNotNull);
      }
      final painter = RouteMapBasemapTilePainter(
        tiles: tiles,
        gridOrigin: ui.Offset.zero,
        devicePixelRatio: 1,
      );
      final samples = await _sampleFrameMs(
        (canvas) => painter.paint(
          canvas,
          ui.Size(_frameWidth.toDouble(), _frameHeight.toDouble()),
        ),
      );
      for (final tile in tiles) {
        tile.image.dispose();
      }
      base.picture.dispose();
      final p50 = _percentile(samples, 0.5);
      // ignore: avoid_print
      print(
        '[#518 tiles] $_renderer seoul 타일 ${tiles.length}장 합성 1080x1920 '
        'p50=${p50.toStringAsFixed(2)}ms '
        'p90=${_percentile(samples, 0.9).toStringAsFixed(2)}ms',
      );
      _expectWithinFrameBudget(p50, '구운 타일 합성 p50이 프레임 예산을 넘었다');
    });
  });
}
