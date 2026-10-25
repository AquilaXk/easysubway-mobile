import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

import '../../../support/basemap_index.dart';
import '../../../support/basemap_vec_draws.dart';

// 노선도 바탕 .vec의 그리기 명령 수 상한(#517). 넓게 본 노선도의 팬 프레임은 화면에 든
// 그리기 명령 수만큼 래스터 스레드 CPU를 쓴다(Galaxy A17 실측: 래스터 시간의 92%가
// 래스터 스레드 CPU 시간). 바탕을 새로 들여와 명령이 늘면 이 테스트가 실패한다. 그때는
// tools/mobile/run-route-map-frame-ab.sh로 실기기 프레임을 이전 바탕과 번갈아 잰 뒤
// 상한을 올린다. 벽시계 시간을 재지 않으므로 CI에서 흔들리지 않는다.
//
// 상한은 실측 개수와 같다(여유 0). 줄어도 실패하므로 바탕을 새로 들여와 개수가 줄면 같은
// PR에서 상한을 내린다(AI 슬롭 가드 기준선과 같은 규칙). 앱은 렌더러에 맞는 변형 하나를
// 그리므로 변형마다 따로 못 박는다(data pipelineRevision 8).
//   outlined : 역명을 글리프 윤곽선으로 구워(data #1488) 텍스트 그리기가 없고(texts 0),
//     같은 paint의 인접 path를 이어(data #1495) path 그리기 수가 줄었다. 대신 윤곽 좌표가
//     늘어 그리기 한 번이 처리하는 path 선분 수(segments)가 커진다.
//   text     : 역명이 텍스트 그리기로 남는다. halo와 글자가 한 줄마다 두 번 그려진다. Skia
//     OpenGLES에서 합친 path가 합치기 전보다 느려(2호선 40% 래스터 p50 11.95ms에서 74.75ms)
//     이 변형은 path를 합치지 않는다(data #1509). path 그리기 수가 합치기 전과 같다.
// 그리기 수만으로는 비용을 더 못 보므로 선분 수도 같은 규칙으로 못 박는다.
typedef _Ceiling = ({int paths, int texts, int invisible, int segments});

const _ceilings = <RouteMapBasemapVariant, Map<String, _Ceiling>>{
  RouteMapBasemapVariant.outlined: {
    '수도권': (paths: 1652, texts: 0, invisible: 0, segments: 67501),
    '부산': (paths: 562, texts: 0, invisible: 0, segments: 12599),
    '대구': (paths: 283, texts: 0, invisible: 0, segments: 9370),
    '대전': (paths: 66, texts: 0, invisible: 0, segments: 2074),
    '광주': (paths: 61, texts: 0, invisible: 0, segments: 2378),
  },
  RouteMapBasemapVariant.text: {
    '수도권': (paths: 1697, texts: 1057, invisible: 0, segments: 7625),
    '부산': (paths: 340, texts: 342, invisible: 0, segments: 1346),
    '대구': (paths: 219, texts: 226, invisible: 0, segments: 866),
    '대전': (paths: 55, texts: 47, invisible: 0, segments: 418),
    '광주': (paths: 49, texts: 42, invisible: 0, segments: 399),
  },
};

// 노선 강조 레이어(권역마다 노선 하나가 바탕 위에 겹쳐 그려진다)의 상한. 한 번에 하나만 그리므로
// 권역 안 레이어들의 지표별 최댓값을 못 박는다. 바탕과 같은 규칙(실측과 같을 때만 통과)이다.
const _overlayCeilings = <RouteMapBasemapVariant, Map<String, _Ceiling>>{
  RouteMapBasemapVariant.outlined: {
    '수도권': (paths: 307, texts: 0, invisible: 0, segments: 8946),
    '부산': (paths: 179, texts: 0, invisible: 0, segments: 3634),
    '대구': (paths: 114, texts: 0, invisible: 0, segments: 3787),
    '대전': (paths: 60, texts: 0, invisible: 0, segments: 1804),
    '광주': (paths: 55, texts: 0, invisible: 0, segments: 2108),
  },
  RouteMapBasemapVariant.text: {
    '수도권': (paths: 275, texts: 177, invisible: 0, segments: 846),
    '부산': (paths: 99, texts: 106, invisible: 0, segments: 271),
    '대구': (paths: 81, texts: 88, invisible: 0, segments: 222),
    '대전': (paths: 49, texts: 47, invisible: 0, segments: 148),
    '광주': (paths: 43, texts: 42, invisible: 0, segments: 129),
  },
};

const _raise =
    '상한보다 늘었다. tools/mobile/run-route-map-frame-ab.sh로 실기기 팬 프레임을 '
    '이전 바탕과 번갈아 잰 뒤 상한을 올린다.';

const _lower = '상한보다 줄었다. 여유를 남기지 않도록 이 파일 _ceilings의 값을 실측으로 내린다.';

/// [actual]이 상한 [ceiling]과 다르면 고치는 방법을 담은 실패 문구, 같으면 null.
String? _ceilingMismatch(String metric, int actual, int ceiling) =>
    switch (actual - ceiling) {
      0 => null,
      > 0 => '$metric $actual (상한 $ceiling): $_raise',
      _ => '$metric $actual (상한 $ceiling): $_lower',
    };

/// 경로·글자 그리기 수와 path 선분 수, 알파 0 paint로 그려 화면에 아무것도 남기지 않는 그리기 수.
class _DrawCounter extends BasemapVecListener {
  final _paintAlpha = <int, int>{};
  int paths = 0;
  int texts = 0;
  int segments = 0;
  int invisible = 0;

  @override
  void onPathMoveTo(double x, double y) => segments++;

  @override
  void onPathLineTo(double x, double y) => segments++;

  @override
  void onPathCubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => segments++;

  bool _isInvisible(int? paintId) =>
      paintId != null && _paintAlpha[paintId] == 0;

  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {
    _paintAlpha[id] = (color >> 24) & 0xff;
  }

  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) {
    paths++;
    if (_isInvisible(paintId)) invisible++;
  }

  @override
  void onDrawText(int textId, int? fillId, int? strokeId, int? patternId) {
    texts++;
    if (_isInvisible(fillId) && (strokeId == null || _isInvisible(strokeId))) {
      invisible++;
    }
  }
}

/// [asset] `.vec` 한 장의 그리기 명령 수와 path 선분 수.
_Ceiling _drawsOf(String asset) {
  final counter = _DrawCounter();
  final response = const VectorGraphicsCodec().decode(
    ByteData.sublistView(File(asset).readAsBytesSync()),
    counter,
  );
  expect(response.complete, isTrue, reason: asset);
  return (
    paths: counter.paths,
    texts: counter.texts,
    invisible: counter.invisible,
    segments: counter.segments,
  );
}

/// [measured]가 [ceiling]과 다른 지표마다 고치는 방법을 담은 줄을 이은 문구. 모두 같으면 빈 문자열.
String _ceilingMismatches(_Ceiling measured, _Ceiling ceiling) => [
  _ceilingMismatch('경로 그리기', measured.paths, ceiling.paths),
  _ceilingMismatch('글자 그리기', measured.texts, ceiling.texts),
  _ceilingMismatch('path 선분', measured.segments, ceiling.segments),
].nonNulls.join('\n');

/// [asset]이 [regionId] 권역의 파일이면 true. 파일 이름이 `<권역 id>.`로 시작한다.
bool _isRegionAsset(String asset, String regionId) =>
    asset.split('/').last.startsWith('$regionId.');

void main() {
  test('상한표는 모든 변형의 노선도 바탕이 있는 모든 권역을 다룬다', () {
    expect(_ceilings.keys.toSet(), RouteMapBasemapVariant.values.toSet());
    for (final regions in _ceilings.values) {
      expect(regions.keys.toSet(), kRouteMapBasemapRegionToId.keys.toSet());
    }
  });

  for (final MapEntry(key: variant, value: regions) in _ceilings.entries) {
    for (final MapEntry(key: region, value: ceiling) in regions.entries) {
      test('${variant.name} $region 바탕 그리기 명령 수가 상한과 같다', () {
        final measured = _drawsOf(
          bundledBasemapIndex
              .variant(variant)
              .baseAssetFor(kRouteMapBasemapRegionToId[region]!),
        );

        expect(_ceilingMismatches(measured, ceiling), isEmpty);
        expect(
          measured.invisible,
          ceiling.invisible,
          reason: '보이지 않는 그리기도 매 프레임 비용이다. 바탕 원본에서 지운다.',
        );
      });

      test('${variant.name} $region 노선 강조 레이어 그리기 명령 수의 최댓값이 상한과 같다', () {
        final regionId = kRouteMapBasemapRegionToId[region]!;
        final files = bundledBasemapIndex.variant(variant);
        final base = files.baseAssetFor(regionId);
        final layers = [
          for (final file in files.files)
            if (file.asset != base && _isRegionAsset(file.asset, regionId))
              _drawsOf(file.asset),
        ];
        int largest(int Function(_Ceiling) metric) =>
            layers.map(metric).reduce(math.max);
        final measured = (
          paths: largest((c) => c.paths),
          texts: largest((c) => c.texts),
          invisible: largest((c) => c.invisible),
          segments: largest((c) => c.segments),
        );

        expect(layers, isNotEmpty);
        expect(
          _ceilingMismatches(measured, _overlayCeilings[variant]![region]!),
          isEmpty,
        );
        expect(measured.invisible, 0);
      });
    }
  }

  group('상한 판정', () {
    test('실측이 상한과 같으면 통과한다', () {
      expect(_ceilingMismatch('path 선분', 100, 100), isNull);
    });

    test('상한보다 늘면 실패하고 실기기로 다시 잰 뒤 올리라고 한다', () {
      expect(
        _ceilingMismatch('path 선분', 101, 100),
        contains('run-route-map-frame-ab.sh'),
      );
    });

    test('상한보다 줄어도 실패하고 상한을 실측으로 내리라고 한다', () {
      expect(_ceilingMismatch('path 선분', 99, 100), contains('_ceilings'));
    });
  });
}
