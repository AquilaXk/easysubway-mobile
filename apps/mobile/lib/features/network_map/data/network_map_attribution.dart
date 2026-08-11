import 'dart:convert';

// 지도 datapack manifest의 license 블록에서 지역별 attribution 표기 문자열을
// 만든다. 하드코딩 지역 분기 대신 `attributionRequired`를 정본으로 삼는다.
const networkMapManifestAssetPath =
    'assets/datapacks/metro_map_pack/manifest.json';

Map<String, String> parseNetworkMapAttributionByRegion(String manifestJson) {
  final manifest = jsonDecode(manifestJson) as Map<String, Object?>;
  final maps = (manifest['maps'] as List? ?? const [])
      .cast<Map<String, Object?>>();
  final result = <String, String>{};
  for (final map in maps) {
    final appRegion = map['app_region'] as String?;
    final license = map['license'] as Map<String, Object?>?;
    if (appRegion == null || license == null) {
      continue;
    }
    if (license['attributionRequired'] != true) {
      continue;
    }
    final authors = (license['authors'] as List? ?? const [])
        .whereType<Object>()
        .map((author) => '$author')
        .join(', ');
    final spdx = (license['spdx'] as String?)?.replaceAll('-', ' ').trim();
    final licenseLabel = (spdx != null && spdx.isNotEmpty)
        ? spdx
        : (license['name'] as String? ?? '');
    final text = [
      if (authors.isNotEmpty) authors,
      if (licenseLabel.isNotEmpty) licenseLabel,
    ].join(', ');
    if (text.isNotEmpty) {
      result[appRegion] = text;
    }
  }
  return result;
}
