import 'dart:convert' show jsonDecode;

/// 노선도 바탕 .vec와 노선 강조 레이어가 함께 들어 있는 자산 폴더. pubspec.yaml에
/// 폴더째 등록돼 있다.
const String kRouteMapBasemapAssetDir =
    'assets/datapacks/metro_map_pack/basemap';

/// data 레포 바탕 컴파일러(`tools/route-map/compile-basemap-vec.mjs`)가 굽는 노선
/// 강조 레이어 색인.
const String kRouteMapLineOverlayIndexAssetPath =
    '$kRouteMapBasemapAssetDir/line-overlays.json';

const int _supportedSchemaVersion = 1;
const String _artifactKind = 'route-map-basemap-line-overlays';
final RegExp _vectorFileName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*\.vec$');

/// 색인에 [regionId] 권역의 [lineId] 노선 레이어가 없다. 바탕을 흐리지 않은 채
/// 조용히 넘기지 않고 오류로 드러낸다.
class RouteMapLineOverlayMissing implements Exception {
  const RouteMapLineOverlayMissing({
    required this.regionId,
    required this.lineId,
  });

  final String regionId;
  final String lineId;

  @override
  String toString() =>
      'RouteMapLineOverlayMissing: 노선 강조 레이어 색인에 $regionId/$lineId가 없습니다.';
}

/// `line-overlays.json`. 권역 id(`seoul`)마다 데이터팩 `lines.id` → 레이어 .vec 파일.
class RouteMapLineOverlayIndex {
  const RouteMapLineOverlayIndex._(this._vectorsByRegion);

  /// 색인 JSON을 읽는다. 모르는 schemaVersion, 다른 산출물 종류, 모양이 다른 항목은
  /// [FormatException]으로 실패한다.
  factory RouteMapLineOverlayIndex.parse(String json) {
    final root = jsonDecode(json);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('노선 강조 레이어 색인이 객체가 아닙니다.');
    }
    if (root['schemaVersion'] != _supportedSchemaVersion) {
      throw FormatException(
        '노선 강조 레이어 색인 schemaVersion ${root['schemaVersion']}은 읽지 않습니다.',
      );
    }
    if (root['artifactKind'] != _artifactKind) {
      throw FormatException('노선 강조 레이어 색인이 아닌 산출물입니다: ${root['artifactKind']}');
    }
    return RouteMapLineOverlayIndex._({
      for (final region in _objectEntries(root['regions'], 'regions'))
        region.key: {
          for (final line in _objectEntries(
            _objectOf(region.value, region.key)['lines'],
            '${region.key}.lines',
          ))
            line.key: _vectorOf(line.value, '${region.key}/${line.key}'),
        },
    });
  }

  final Map<String, Map<String, String>> _vectorsByRegion;

  /// [regionId] 권역 [lineId] 노선 레이어의 자산 경로. 색인에 없으면
  /// [RouteMapLineOverlayMissing].
  String overlayAssetFor({required String regionId, required String lineId}) {
    final vector = _vectorsByRegion[regionId]?[lineId];
    if (vector == null) {
      throw RouteMapLineOverlayMissing(regionId: regionId, lineId: lineId);
    }
    return '$kRouteMapBasemapAssetDir/$vector';
  }
}

Map<String, dynamic> _objectOf(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('노선 강조 레이어 색인 $path가 객체가 아닙니다.');
  }
  return value;
}

Iterable<MapEntry<String, dynamic>> _objectEntries(
  Object? value,
  String path,
) => _objectOf(value, path).entries;

String _vectorOf(Object? entry, String path) {
  final vector = _objectOf(entry, path)['vector'];
  if (vector is! String || !_vectorFileName.hasMatch(vector)) {
    throw FormatException('노선 강조 레이어 $path의 vector 파일 이름이 잘못됐습니다: $vector');
  }
  return vector;
}
