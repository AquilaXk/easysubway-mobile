import 'package:flutter/services.dart';

import 'network_map_attribution.dart';

// Manifest는 프로세스 생애주기 동안 바뀌지 않는 번들 asset이다. 노선도 canvas가
// 다시 마운트될 때마다 읽지 않도록 한 번의 Future를 공유하고, 실패 시 caller가
// cache를 비워 다음 마운트에서 재시도할 수 있게 한다.
Future<Map<String, String>>? _sharedAttributionTextByRegionFuture;

Future<Map<String, String>> loadNetworkMapAttributionTextByRegion() {
  return _sharedAttributionTextByRegionFuture ??= rootBundle
      .loadString(networkMapManifestAssetPath)
      .then(parseNetworkMapAttributionByRegion);
}

void resetNetworkMapAttributionCache() {
  _sharedAttributionTextByRegionFuture = null;
}
