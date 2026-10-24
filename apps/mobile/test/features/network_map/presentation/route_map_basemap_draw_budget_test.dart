import 'dart:io';
import 'dart:typed_data';

import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

import '../../../support/basemap_vec_text_draws.dart';

// 노선도 바탕 .vec의 그리기 명령 수 상한(#517). 넓게 본 노선도의 팬 프레임은 화면에 든
// 그리기 명령 수만큼 래스터 스레드 CPU를 쓴다(Galaxy A17 실측: 래스터 시간의 92%가
// 래스터 스레드 CPU 시간). 바탕을 새로 들여와 명령이 늘면 이 테스트가 실패한다. 그때는
// tools/mobile/run-route-map-frame-ab.sh로 실기기 프레임을 이전 바탕과 번갈아 잰 뒤
// 상한을 올린다. 벽시계 시간을 재지 않으므로 CI에서 흔들리지 않는다.
const _ceilings = <String, ({int paths, int texts, int invisible})>{
  '수도권': (paths: 1699, texts: 1057, invisible: 1),
  '부산': (paths: 362, texts: 342, invisible: 0),
  '대구': (paths: 229, texts: 226, invisible: 0),
  '대전': (paths: 55, texts: 47, invisible: 0),
  '광주': (paths: 49, texts: 42, invisible: 0),
};

const _remeasure =
    '바탕 그리기 명령이 상한을 넘었다. tools/mobile/run-route-map-frame-ab.sh로 '
    '실기기 팬 프레임을 이전 바탕과 번갈아 잰 뒤 상한을 올린다.';

/// 경로·글자 그리기 수와, 알파 0 paint로 그려 화면에 아무것도 남기지 않는 그리기 수.
class _DrawCounter extends BasemapVecListener {
  final _paintAlpha = <int, int>{};
  int paths = 0;
  int texts = 0;
  int invisible = 0;

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
        counter.invisible,
        lessThanOrEqualTo(ceiling.invisible),
        reason: '보이지 않는 그리기도 매 프레임 비용이다. 바탕 원본에서 지운다.',
      );
    });
  }
}
