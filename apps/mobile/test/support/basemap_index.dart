import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';

/// 번들 바탕 색인(`line-overlays.json`) 원문. flutter test cwd(apps/mobile) 기준으로 연다.
final String bundledBasemapIndexJson = File(
  kRouteMapLineOverlayIndexAssetPath,
).readAsStringSync();

/// 앱과 같은 권역 집합으로 읽은 번들 바탕 색인.
final RouteMapLineOverlayIndex bundledBasemapIndex =
    RouteMapLineOverlayIndex.parse(
      bundledBasemapIndexJson,
      regionIds: kRouteMapBasemapRegionToId.values.toSet(),
    );

/// 번들 색인 [variant] 변형에 실린 모든 .vec의 자산 경로 → sha256. 앱은 파일 목록과
/// sha256을 읽지 않으므로 자산 계약 테스트가 색인 원문에서 직접 꺼낸다.
Map<String, String> bundledBasemapIndexFiles(RouteMapBasemapVariant variant) {
  final root = jsonDecode(bundledBasemapIndexJson) as Map<String, dynamic>;
  final regions =
      ((root['variants'] as Map<String, dynamic>)[variant.indexKey]
              as Map<String, dynamic>)['regions']
          as Map<String, dynamic>;
  return {
    for (final region in regions.values.cast<Map<String, dynamic>>()) ...{
      '$kRouteMapBasemapAssetDir/${region['baseVector']}':
          region['baseVectorSha256'] as String,
      for (final line
          in (region['lines'] as Map<String, dynamic>).values
              .cast<Map<String, dynamic>>())
        '$kRouteMapBasemapAssetDir/${line['vector']}': line['sha256'] as String,
    },
  };
}
