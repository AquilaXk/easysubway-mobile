import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_tiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../../../support/basemap_index.dart';

// #2068 하이브리드 바탕층 성능 상한 확인.
//
// 바탕 .vec 런타임 로드+디코드 시간과 파일 크기를 재서 print하고 느슨한 상한 안인지 본다.
// 컴파일 시간은 셸 `time`으로 별도 측정하므로 여기에 넣지 않는다. structured
// recordRouteMapPicture 대비 비교는 데이터 로드가 무거워 생략하고 vec 로드만 잰다(범위 밖
// 노이즈 회피).
//
// 앱은 엔진 렌더러에 맞는 바탕 변형을 그린다(RouteMapBasemapAssets.shared.variant). Flutter 3.44
// 엔진은 Android API 29 이상(Vivante GPU 제외)과 iOS에서 Impeller로, API 24~28과 Vivante
// GPU에서 Skia OpenGLES로 그린다(flutter_main.cc SelectedRenderingAPI,
// kMinimumAndroidApiLevelForImpeller = 29). 앱 minSdk는 24다. Impeller 기기군은 윤곽선 라벨
// 변형을, Skia OpenGLES 기기군은 텍스트 라벨 변형을 쓴다. 이 파일도 같은 규칙으로 자산을 고른다.
//
// 래스터 프레임 상한은 Impeller로 그릴 때만 확인한다. 그래서 상한은 Impeller 기기군의 윤곽선
// 변형만 대표한다. Skia OpenGLES 기기군의 텍스트 변형은 호스트에서 재지 못하므로 Impeller를
// 끈 측정용 빌드의 실기기 교대 측정이 맡는다(test/evidence/perf-route-map-raster-517).
//
// 호스트 렌더러는 단계마다 다르다. `flutter test` 기본 실행은 Skia 소프트웨어 래스터라
// (flutter_tools flutter_tester_device.dart --enable-software-rendering) 텍스트 변형을 고르고
// 어느 기기에도 없는 CPU 커버리지 계산을 잰다. 이 값은 기록만 한다. CI는 이 파일을 `flutter test
// --enable-impeller`로 한 번 더 돌려 상한을 확인한다(ci.yml "Raster frame upper bound (Impeller)").
// 이때 flutter_tester는 SwiftShader 위 Impeller Vulkan으로 그리고(tester_main.cc), 상한이 재는
// 값은 래스터 스레드가 명령을 만드는 시간이다. GPU를 포함한 프레임은 실기기 측정만 본다.
//
// flutter test cwd는 apps/mobile다 — 자산 경로를 그 기준 상대경로로 연다.

/// 엔진이 Impeller로 그리는지. dart:ui가 엔진의 Impeller 설정을 그대로 돌려준다.
final bool _impeller = ui.ImageFilter.isShaderFilterSupported;

/// CI 상한 확인 단계가 켠다. 켜졌는데 Impeller가 아니면 상한 확인이 조용히 빠진다.
const bool _upperBoundRun = bool.fromEnvironment(
  'ROUTE_MAP_RASTER_UPPER_BOUND_IMPELLER',
);

String get _renderer => _impeller ? 'Impeller' : 'Skia 소프트웨어(기록만)';

const int _warmupFrames = 5;
const int _sampleFrames = 25;
const double _overviewScale = 0.35;
const int _frameWidth = 1080;
const int _frameHeight = 1920;

/// 지도 바탕 면과 다른 픽셀이 프레임 안 지도 면적에서 차지해야 하는 최소 비율. 실제 노선도
/// 프레임의 비율보다 훨씬 낮아 렌더러마다 다른 안티앨리어싱에는 걸리지 않고, 아무것도 그리지
/// 않았거나 바탕 면만 그린 프레임(0)은 잡는다. 라벨이나 강조 레이어 하나가 빠진 프레임은
/// 잡지 못한다.
const double _minInkShare = 0.01;

/// [mapSize] 크기 지도를 [_overviewScale]로 원점에 그린 프레임에서 최소한 칠해져야 하는 픽셀 수.
/// 지도 면적은 .vec viewBox 크기를 배율로 줄여 프레임에 잘린 넓이다.
int _minInkPixels(ui.Size mapSize) =>
    (math.min(mapSize.width * _overviewScale, _frameWidth) *
            math.min(mapSize.height * _overviewScale, _frameHeight) *
            _minInkShare)
        .ceil();

/// 투명하지 않고 지도 바탕 면과도 다른 픽셀 수. 지도는 원점에 그리고 맨 처음 바탕 면을 칠하므로
/// 왼쪽 위 픽셀이 바탕 면 색이다.
int _inkPixels(ByteData rgba) {
  final pixels = rgba.buffer.asUint32List(
    rgba.offsetInBytes,
    rgba.lengthInBytes ~/ 4,
  );
  final background = pixels.first;
  var ink = 0;
  for (final pixel in pixels) {
    if (pixel != 0 && pixel != background) {
      ink += 1;
    }
  }
  return ink;
}

/// [frame]을 toImage로 그리는 시간(ms). Impeller의 toImage는 래스터 스레드가 명령을
/// 만들어 제출하면 끝나고 GPU 완료를 기다리지 않는다(impeller/display_list/dl_dispatcher.cc
/// DisplayListToTexture). 그래서 잰 다음 toByteData로 완료를 기다려 다음 표본이 밀린 GPU
/// 일과 겹치지 않게 하고, 빈 프레임이 상한 확인을 통과하지 않도록 칠한 픽셀이 [minInkPixels]
/// 이상인지 확인한다.
Future<double> _frameMs(ui.Picture frame, int minInkPixels) async {
  try {
    final stopwatch = Stopwatch()..start();
    final image = await frame.toImage(_frameWidth, _frameHeight);
    stopwatch.stop();
    try {
      final pixels = (await image.toByteData())!;
      expect(pixels.lengthInBytes, _frameWidth * _frameHeight * 4);
      expect(
        _inkPixels(pixels),
        greaterThanOrEqualTo(minInkPixels),
        reason: '프레임에 노선도가 그려지지 않았다',
      );
    } finally {
      image.dispose();
    }
    return stopwatch.elapsedMicroseconds / 1000.0;
  } finally {
    frame.dispose();
  }
}

/// [mapSize] 크기 지도를 [draw]로 그린 프레임을 워밍업 뒤 [_sampleFrames]장 잰다.
Future<List<double>> _sampleFrameMs(
  ui.Size mapSize,
  void Function(ui.Canvas) draw,
) async {
  final minInkPixels = _minInkPixels(mapSize);
  final samples = <double>[];
  for (var index = 0; index < _warmupFrames + _sampleFrames; index += 1) {
    final recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    final ms = await _frameMs(recorder.endRecording(), minInkPixels);
    if (index >= _warmupFrames) {
      samples.add(ms);
    }
  }
  return samples;
}

double _percentile(List<double> samples, double q) =>
    (samples.toList()..sort())[(samples.length * q).floor()];

/// [asset]을 디코드해 [body]에 주고, [body]가 던져도 그림을 해제한다.
Future<T> _withPicture<T>(
  String asset,
  Future<T> Function(PictureInfo info) body,
) async {
  final info = await vg.loadPicture(AssetBytesLoader(asset), null);
  try {
    return await body(info);
  } finally {
    info.picture.dispose();
  }
}

/// Impeller로 그릴 때 [p50]이 래스터 상한 아래인지 본다. 상한은 로컬에서 60 Hz 한 프레임
/// 16.7 ms이고, CI 러너 가상화 편차를 고려해 CI에서는 두 프레임 33.3 ms다.
void _expectUnderRasterUpperBound(double p50, String reason) {
  if (!_impeller) {
    return;
  }
  final upperBoundMs = Platform.environment['CI'] != null ? 33.3 : 16.7;
  expect(p50, lessThan(upperBoundMs), reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 앱처럼 엔진 렌더러에 맞는 변형을 잰다.
  final files = bundledBasemapIndex.variant(
    RouteMapBasemapAssets.shared.variant,
  );
  final seoulAsset = files.baseAssetFor('seoul');

  test('상한 확인 실행은 Impeller로 윤곽선 변형을, 기본 실행은 Skia로 텍스트 변형을 그린다', () {
    expect(
      _impeller,
      _upperBoundRun,
      reason: '상한 확인은 --enable-impeller와 그 define을 함께 줄 때만 돈다',
    );
    expect(
      RouteMapBasemapAssets.shared.variant,
      _upperBoundRun
          ? RouteMapBasemapVariant.outlined
          : RouteMapBasemapVariant.text,
    );
  });

  testWidgets('seoul 바탕 .vec 로드+디코드가 상한 안이고 파일이 비어 있지 않다', (tester) async {
    // 파일 크기(bytes) — File.lengthSync는 cwd(apps/mobile) 기준 상대경로로 연다.
    final vecFile = File(seoulAsset);
    expect(vecFile.existsSync(), isTrue, reason: '$seoulAsset가 번들에 있어야 한다');
    final sizeBytes = vecFile.lengthSync();

    // 로드+디코드 시간 — 실제 async 자산 로드가 완료되도록 runAsync 안에서 잰다.
    late final Duration loadDuration;
    await tester.runAsync(() async {
      final stopwatch = Stopwatch()..start();
      final info = await vg.loadPicture(AssetBytesLoader(seoulAsset), null);
      stopwatch.stop();
      info.picture.dispose();
      loadDuration = stopwatch.elapsed;
    });

    // ignore: avoid_print
    print(
      '[#2068 perf] $_renderer $seoulAsset 크기=${sizeBytes}B(${(sizeBytes / 1024).toStringAsFixed(1)}KB) '
      '로드+디코드=${loadDuration.inMicroseconds}us(${loadDuration.inMilliseconds}ms)',
    );

    // 느슨한 회귀 상한. 로드가 2초를 넘으면 이상 신호다.
    expect(loadDuration.inMilliseconds, lessThan(2000));
    expect(sizeBytes, greaterThan(0));
  });

  // #2593 리뷰 Major. 전량 반입으로 새로 들어온 `page-background`(전면 흰 rect)와
  // `background-grid-overlay`(격자 패턴 타일)의 래스터 비용이 상한 안인지 본다. 대전·광주
  // 오버레이는 `opacity="0.52"`라 실제로 보이는 요소이고 패턴 타일링이 프레임 시간을 크게
  // 좌우한다. 수도권 오버레이는 `opacity="0"`이라 사실상 무료다. 상한은
  // [_expectUnderRasterUpperBound]의 느슨한 확인선이다.
  testWidgets('바탕 .vec 래스터 프레임 p50이 상한 안이다', (tester) async {
    final targets = {
      for (final regionId in ['seoul', 'daejeon'])
        regionId: files.baseAssetFor(regionId),
    };
    await tester.runAsync(() async {
      for (final entry in targets.entries) {
        await _withPicture(entry.value, (info) async {
          final samples = await _sampleFrameMs(
            info.size,
            (canvas) => canvas
              ..scale(_overviewScale)
              ..drawPicture(info.picture),
          );
          final p50 = _percentile(samples, 0.5);
          // ignore: avoid_print
          print(
            '[#2593 raster] $_renderer ${entry.value} 1080x1920 '
            'p50=${p50.toStringAsFixed(2)}ms '
            'p90=${_percentile(samples, 0.9).toStringAsFixed(2)}ms',
          );
          _expectUnderRasterUpperBound(p50, '${entry.key}: 래스터 p50이 상한을 넘었다');
        });
      }
    });
  });

  // 노선 강조(#511): 가장 큰 노선 레이어(수도권 1호선) 디코드와, 흐린 바탕 saveLayer + 레이어
  // 그리기가 바탕만 그릴 때보다 늘리는 래스터가 상한 안인지 본다.
  testWidgets('노선 강조 레이어 디코드와 흐린 바탕 래스터가 상한 안이다', (tester) async {
    final overlayAsset = files.overlayAssetFor(
      regionId: 'seoul',
      lineId: 'line-472a81add377',
    );
    await tester.runAsync(() async {
      final decodeMs = <double>[];
      for (var run = 0; run < 7; run += 1) {
        final stopwatch = Stopwatch()..start();
        final info = await vg.loadPicture(AssetBytesLoader(overlayAsset), null);
        stopwatch.stop();
        info.picture.dispose();
        decodeMs.add(stopwatch.elapsedMicroseconds / 1000.0);
      }
      await _withPicture(seoulAsset, (base) {
        return _withPicture(overlayAsset, (overlay) async {
          final fadePaint = ui.Paint()
            ..color = const ui.Color.fromRGBO(
              0,
              0,
              0,
              kRouteMapFadedBasemapOpacity,
            );
          final plain = await _sampleFrameMs(
            base.size,
            (canvas) => canvas
              ..scale(_overviewScale)
              ..drawPicture(base.picture),
          );
          final highlighted = await _sampleFrameMs(
            base.size,
            (canvas) => canvas
              ..scale(_overviewScale)
              ..saveLayer(null, fadePaint)
              ..drawPicture(base.picture)
              ..restore()
              ..drawPicture(overlay.picture),
          );
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
          _expectUnderRasterUpperBound(
            _percentile(highlighted, 0.5),
            '강조 래스터 p50이 상한을 넘었다',
          );
        });
      });
    });
  });

  // 카메라가 멈추면 앱은 바탕을 화면 픽셀 타일로 구워 두고(#518) 팬하는 동안 구운 타일만
  // 그린다. 넓게 본 노선도에서 사용자가 보는 프레임이 이 합성이다. 타일은 앱의 격자로 굽는다.
  testWidgets('구운 바탕 타일 합성 프레임 p50이 상한 안이다', (tester) async {
    await tester.runAsync(() async {
      await _withPicture(seoulAsset, (base) async {
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
        try {
          for (final tile in tiles) {
            expect(await tile.image.toByteData(), isNotNull);
          }
          final painter = RouteMapBasemapTilePainter(
            tiles: tiles,
            gridOrigin: ui.Offset.zero,
            devicePixelRatio: 1,
          );
          final samples = await _sampleFrameMs(
            base.size,
            (canvas) => painter.paint(
              canvas,
              ui.Size(_frameWidth.toDouble(), _frameHeight.toDouble()),
            ),
          );
          final p50 = _percentile(samples, 0.5);
          // ignore: avoid_print
          print(
            '[#518 tiles] $_renderer seoul 타일 ${tiles.length}장 합성 1080x1920 '
            'p50=${p50.toStringAsFixed(2)}ms '
            'p90=${_percentile(samples, 0.9).toStringAsFixed(2)}ms',
          );
          _expectUnderRasterUpperBound(p50, '구운 타일 합성 p50이 상한을 넘었다');
        } finally {
          for (final tile in tiles) {
            tile.image.dispose();
          }
        }
      });
    });
  });
}
