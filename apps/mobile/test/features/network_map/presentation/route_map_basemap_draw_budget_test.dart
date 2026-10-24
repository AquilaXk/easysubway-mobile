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
// 상한은 실측 개수와 같다(여유 0). 같은 규칙으로 data 54e2e7c99(pipelineRevision 6) 바탕에
// 맞췄다. 역명을 글리프 윤곽선으로 구우면서(data #1488) 텍스트 그리기는 사라졌고
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

const _remeasure =
    '바탕 그리기 명령이 상한을 넘었다. tools/mobile/run-route-map-frame-ab.sh로 '
    '실기기 팬 프레임을 이전 바탕과 번갈아 잰 뒤 상한을 올린다.';

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
    test('$region 바탕 그리기 명령 수가 상한 안이다', () {
      final asset = routeMapBasemapAssetForRegion(region)!;
      final counter = _DrawCounter();
      final response = const VectorGraphicsCodec().decode(
        ByteData.sublistView(File(asset).readAsBytesSync()),
        counter,
      );

      expect(response.complete, isTrue);
      expect(
        counter.paths,
        lessThanOrEqualTo(ceiling.paths),
        reason: _remeasure,
      );
      expect(
        counter.texts,
        lessThanOrEqualTo(ceiling.texts),
        reason: _remeasure,
      );
      expect(
        counter.segments,
        lessThanOrEqualTo(ceiling.segments),
        reason: _remeasure,
      );
      expect(
        counter.invisible,
        lessThanOrEqualTo(ceiling.invisible),
        reason: '보이지 않는 그리기도 매 프레임 비용이다. 바탕 원본에서 지운다.',
      );
    });
  }
}
