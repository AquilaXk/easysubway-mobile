import 'dart:io';
import 'dart:typed_data';

import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

import '../../../support/basemap_vec_draws.dart';

// 노선도 바탕 .vec의 그리기 명령 수 상한(#517). 넓게 본 노선도의 팬 프레임은 화면에 든
// 그리기 명령 수만큼 래스터 스레드 CPU를 쓴다(Galaxy A17 실측: 래스터 시간의 92%가
// 래스터 스레드 CPU 시간). 바탕을 새로 들여와 명령이 늘면 이 테스트가 실패한다. 그때는
// tools/mobile/run-route-map-frame-ab.sh로 실기기 프레임을 이전 바탕과 번갈아 잰 뒤
// 상한을 올린다. 벽시계 시간을 재지 않으므로 CI에서 흔들리지 않는다.
//
// 상한은 실측 개수와 같다(여유 0). 줄어도 실패하므로 바탕을 새로 들여와 개수가 줄면 같은
// PR에서 상한을 내린다(AI 슬롭 가드 기준선과 같은 규칙). data 54e2e7c99(pipelineRevision 6)
// 바탕에 맞췄다. 역명을 글리프 윤곽선으로 구우면서(data #1488) 텍스트 그리기는 사라졌고
// (texts 0), 같은 paint의 인접 path를 이어(data #1495) path 그리기 수가 줄었다. 대신
// 윤곽 좌표가 늘어 그리기 한 번이 처리하는 path 선분 수(segments)가 커지므로 이것도
// 같은 규칙으로 못 박는다. 그리기 수만으로는 비용을 더 못 본다.
const _ceilings =
    <String, ({int paths, int texts, int invisible, int segments})>{
      '수도권': (paths: 1652, texts: 0, invisible: 0, segments: 67501),
      '부산': (paths: 562, texts: 0, invisible: 0, segments: 12599),
      '대구': (paths: 283, texts: 0, invisible: 0, segments: 9370),
      '대전': (paths: 66, texts: 0, invisible: 0, segments: 2074),
      '광주': (paths: 61, texts: 0, invisible: 0, segments: 2378),
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

void main() {
  test('상한표는 노선도 바탕이 있는 모든 권역을 다룬다', () {
    expect(_ceilings.keys.toSet(), kRouteMapBasemapRegionToId.keys.toSet());
  });

  for (final MapEntry(key: region, value: ceiling) in _ceilings.entries) {
    test('$region 바탕 그리기 명령 수가 상한과 같다', () {
      final asset = routeMapBasemapAssetForRegion(region)!;
      final counter = _DrawCounter();
      final response = const VectorGraphicsCodec().decode(
        ByteData.sublistView(File(asset).readAsBytesSync()),
        counter,
      );

      expect(response.complete, isTrue);
      final mismatches = [
        _ceilingMismatch('경로 그리기', counter.paths, ceiling.paths),
        _ceilingMismatch('글자 그리기', counter.texts, ceiling.texts),
        _ceilingMismatch('path 선분', counter.segments, ceiling.segments),
      ].nonNulls;
      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
      expect(
        counter.invisible,
        ceiling.invisible,
        reason: '보이지 않는 그리기도 매 프레임 비용이다. 바탕 원본에서 지운다.',
      );
    });
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
