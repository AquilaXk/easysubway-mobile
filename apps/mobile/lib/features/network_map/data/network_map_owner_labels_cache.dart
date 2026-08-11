import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../domain/route_map_owner_labels.dart';

// 5권역 결합 sidecar는 process 생애주기 동안 바뀌지 않으므로 한 번의 Future를
// 공유한다. 로드 실패 시 Future만 비워 다음 마운트에서 재시도한다.
Future<Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>>?
_sharedOwnerLabelsByRegionFuture;

// 완료된 값은 캔버스 첫 build가 동기로 읽어 초기 카메라 줌 팝을 피한다.
Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>?
_sharedOwnerLabelsByRegionValue;

Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>?
get cachedNetworkMapOwnerLabelsByRegion => _sharedOwnerLabelsByRegionValue;

Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>
_decodeNetworkMapOwnerLabelsSidecar(Uint8List bytes) {
  return routeMapOwnerLabelsByRegionFrom(utf8.decode(bytes));
}

Future<Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>>
loadNetworkMapOwnerLabelsByRegion() {
  // 바이트만 읽고(rootBundle.load는 compute를 타지 않는다) 디코드·파싱 전체를
  // 한 번의 worker isolate로 넘겨 UI isolate에는 결과 대입만 남긴다.
  return _sharedOwnerLabelsByRegionFuture ??= rootBundle
      .load(kRouteMapOwnerLabelsAssetPath)
      .then(
        (data) => compute(
          _decodeNetworkMapOwnerLabelsSidecar,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      )
      .then((byRegion) {
        _sharedOwnerLabelsByRegionValue = byRegion;
        return byRegion;
      });
}

void invalidateNetworkMapOwnerLabelsLoad() {
  _sharedOwnerLabelsByRegionFuture = null;
}

@visibleForTesting
void resetNetworkMapOwnerLabelsCacheForTest() {
  _sharedOwnerLabelsByRegionFuture = null;
  _sharedOwnerLabelsByRegionValue = null;
}

@visibleForTesting
void primeNetworkMapOwnerLabelsCacheForTest(
  Map<String, Map<String, List<RouteMapOwnerLabelEntry>>> byRegion,
) {
  _sharedOwnerLabelsByRegionFuture = Future.value(byRegion);
  _sharedOwnerLabelsByRegionValue = byRegion;
}
