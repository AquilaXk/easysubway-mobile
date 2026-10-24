import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

// #2068 하이브리드 바탕층 성능 계측(계측 위주, 느슨한 assert).
//
// 바탕 .vec 런타임 로드+디코드 시간과 파일 크기를 측정해 print한다. 컴파일 시간은
// 셸 `time`으로 별도 측정하므로 여기에 넣지 않는다. structured recordRouteMapPicture
// 대비 비교는 데이터 로드가 무거워 생략하고 vec 로드만 계측한다(범위 밖 노이즈 회피).
//
// flutter test cwd는 apps/mobile다 — 자산 경로를 그 기준 상대경로로 연다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seoulAsset = 'assets/datapacks/metro_map_pack/basemap/seoul.vec';

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
  // `opacity="0"`이라 사실상 무료다. 상한은 프레임 예산(16.7ms) 기준의 느슨한
  // 회귀 감지선이며, 목적은 수치를 기록해 두는 것이다.
  testWidgets('바탕 .vec 래스터 프레임 시간 p50/p90 계측', (tester) async {
    const targets = <String, String>{
      'seoul': 'assets/datapacks/metro_map_pack/basemap/seoul.vec',
      'daejeon': 'assets/datapacks/metro_map_pack/basemap/daejeon.vec',
    };
    await tester.runAsync(() async {
      for (final entry in targets.entries) {
        final info = await vg.loadPicture(AssetBytesLoader(entry.value), null);
        // 첫 프레임들은 셰이더·JIT 워밍업이라 잡음이 크다 — 5장 버리고 잰다.
        const warmup = 5;
        final samples = <double>[];
        for (var index = 0; index < warmup + 25; index += 1) {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.scale(0.35);
          canvas.drawPicture(info.picture);
          final frame = recorder.endRecording();
          final stopwatch = Stopwatch()..start();
          final image = await frame.toImage(1080, 1920);
          stopwatch.stop();
          image.dispose();
          frame.dispose();
          if (index >= warmup) {
            samples.add(stopwatch.elapsedMicroseconds / 1000.0);
          }
        }
        info.picture.dispose();
        samples.sort();
        final p50 = samples[samples.length ~/ 2];
        final p90 = samples[(samples.length * 0.9).floor()];
        // ignore: avoid_print
        print(
          '[#2593 raster] ${entry.key}.vec 1080x1920 '
          'p50=${p50.toStringAsFixed(2)}ms p90=${p90.toStringAsFixed(2)}ms',
        );
        // CI 러너 가상화 환경 성능 편차를 고려하여 CI에서는 33.3ms, 로컬에서는 16.7ms를 적용한다.
        final maxBudget = Platform.environment['CI'] != null ? 33.3 : 16.7;
        expect(
          p50,
          lessThan(maxBudget),
          reason: '${entry.key}: 래스터 p50이 프레임 예산을 넘었다',
        );
      }
    });
  });

  // 노선 강조(#511): 가장 큰 노선 레이어(수도권 1호선) 디코드 시간과, 흐린 바탕
  // saveLayer + 레이어 그리기가 바탕만 그릴 때보다 래스터를 얼마나 늘리는지 잰다.
  // 두 쪽을 번갈아 그려 워밍업·캐시 편차가 한쪽으로 쏠리지 않게 한다.
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
      Future<double> rasterMs({required bool highlighted}) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.scale(0.35);
        if (highlighted) {
          canvas.saveLayer(null, fadePaint);
          canvas.drawPicture(base.picture);
          canvas.restore();
          canvas.drawPicture(overlay.picture);
        } else {
          canvas.drawPicture(base.picture);
        }
        final frame = recorder.endRecording();
        final stopwatch = Stopwatch()..start();
        final image = await frame.toImage(1080, 1920);
        stopwatch.stop();
        image.dispose();
        frame.dispose();
        return stopwatch.elapsedMicroseconds / 1000.0;
      }

      const warmup = 5;
      final plain = <double>[];
      final highlighted = <double>[];
      for (var index = 0; index < warmup + 25; index += 1) {
        final plainMs = await rasterMs(highlighted: false);
        final highlightedMs = await rasterMs(highlighted: true);
        if (index >= warmup) {
          plain.add(plainMs);
          highlighted.add(highlightedMs);
        }
      }
      base.picture.dispose();
      overlay.picture.dispose();
      double percentile(List<double> samples, double q) =>
          (samples.toList()..sort())[(samples.length * q).floor()];
      // ignore: avoid_print
      print(
        '[#511 overlay] seoul 1호선 레이어 '
        '${File(overlayAsset).lengthSync()}B 디코드 '
        'p50=${percentile(decodeMs, 0.5).toStringAsFixed(2)}ms '
        '범위=${percentile(decodeMs, 0).toStringAsFixed(2)}~'
        '${(decodeMs.toList()..sort()).last.toStringAsFixed(2)}ms(7회) | '
        '1080x1920 래스터 바탕만 p50=${percentile(plain, 0.5).toStringAsFixed(2)}'
        ' p90=${percentile(plain, 0.9).toStringAsFixed(2)}ms, '
        '강조 p50=${percentile(highlighted, 0.5).toStringAsFixed(2)}'
        ' p90=${percentile(highlighted, 0.9).toStringAsFixed(2)}ms(25회 교대)',
      );
      final maxBudget = Platform.environment['CI'] != null ? 33.3 : 16.7;
      expect(percentile(decodeMs, 0.5), lessThan(2000));
      expect(
        percentile(highlighted, 0.5),
        lessThan(maxBudget),
        reason: '강조 래스터 p50이 프레임 예산을 넘었다',
      );
    });
  });
}
