import 'dart:convert' show jsonDecode;

/// 노선도 바탕 .vec와 노선 강조 레이어가 함께 들어 있는 자산 폴더. pubspec.yaml에
/// 폴더째 등록돼 있다.
const String kRouteMapBasemapAssetDir =
    'assets/datapacks/metro_map_pack/basemap';

/// data 레포 바탕 컴파일러(`tools/route-map/compile-basemap-vec.mjs`)가 굽는 바탕·노선
/// 강조 레이어 색인.
const String kRouteMapLineOverlayIndexAssetPath =
    '$kRouteMapBasemapAssetDir/line-overlays.json';

const int _supportedSchemaVersion = 2;
const String _artifactKind = 'route-map-basemap-line-overlays';
final RegExp _vectorFileName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*\.vec$');
final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// 바탕 .vec 변형. 같은 그림을 라벨을 담는 방식만 달리 굽는다(data
/// `tools/route-map/basemap-variants.mjs`).
enum RouteMapBasemapVariant {
  /// 라벨을 참조 서체의 글리프 윤곽선 path로 굽는다.
  outlined(indexKey: 'outlined', labels: 'outlined-into-vec'),

  /// 라벨을 텍스트 그리기로 두어 기기 서체로 그린다.
  text(indexKey: 'text', labels: 'text-into-vec');

  const RouteMapBasemapVariant({required this.indexKey, required this.labels});

  /// 엔진 렌더러가 그릴 변형. Galaxy A17 교대 측정에서 윤곽선 라벨은 Impeller에서 텍스트
  /// 라벨과 같거나 빨랐고, Skia OpenGLES에서는 래스터가 더 느렸다(PR #519 측정 원자료).
  factory RouteMapBasemapVariant.forRenderer({required bool impeller}) =>
      impeller ? outlined : text;

  /// 색인 `variants`의 키.
  final String indexKey;

  /// 색인 `variants.<indexKey>.labels` 값.
  final String labels;
}

/// 색인에 [regionId] 권역의 [lineId] 노선 레이어가 없다. 바탕을 흐리지 않은 채 조용히
/// 넘기지 않고 오류로 드러낸다.
final class RouteMapLineOverlayMissing implements Exception {
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

/// 권역 바탕과 노선 id → 노선 레이어의 번들 자산 경로.
typedef _RegionAssets = ({String base, Map<String, String> lines});

/// 한 변형의 권역 바탕과 노선 강조 레이어. 권역은 [RouteMapLineOverlayIndex.parse]에
/// 넘긴 권역과 정확히 같다.
class RouteMapBasemapVariantFiles {
  const RouteMapBasemapVariantFiles._(this._regions);

  final Map<String, _RegionAssets> _regions;

  /// [regionId] 권역 바탕의 자산 경로. 색인을 읽을 때 넘긴 권역이 아니면 [ArgumentError].
  String baseAssetFor(String regionId) =>
      (_regions[regionId] ??
              (throw ArgumentError.value(
                regionId,
                'regionId',
                '바탕 색인 권역이 아닙니다',
              )))
          .base;

  /// [regionId] 권역 [lineId] 노선 레이어의 자산 경로. 색인에 없으면
  /// [RouteMapLineOverlayMissing].
  String overlayAssetFor({required String regionId, required String lineId}) =>
      _regions[regionId]?.lines[lineId] ??
      (throw RouteMapLineOverlayMissing(regionId: regionId, lineId: lineId));

  bool _hasSameLines(RouteMapBasemapVariantFiles other) =>
      _regions.entries.every(
        (region) => _sameSet(
          region.value.lines.keys,
          other._regions[region.key]!.lines.keys,
        ),
      );
}

/// `line-overlays.json`. 변형마다 권역 id(`seoul`) → 바탕과 데이터팩 `lines.id` → 노선
/// 레이어 .vec. 앱은 렌더러에 맞는 변형 하나에서 바탕과 레이어를 함께 고른다.
class RouteMapLineOverlayIndex {
  const RouteMapLineOverlayIndex._(this._variants);

  /// 색인 JSON을 읽는다. 모르는 schemaVersion, 다른 산출물 종류, 빠지거나 모르는
  /// 변형, 권역이 [regionIds]와 다른 변형, 변형끼리 다른 노선, 두 항목이 함께 가리키는
  /// 파일, sha256이 없는 파일, 모양이 다른 항목은 [FormatException]으로 실패한다.
  factory RouteMapLineOverlayIndex.parse(
    String json, {
    required Set<String> regionIds,
  }) {
    final root = _objectOf(jsonDecode(json), '최상위');
    if (root['schemaVersion'] != _supportedSchemaVersion) {
      throw FormatException(
        '바탕 색인 schemaVersion ${root['schemaVersion']}은 읽지 않습니다.',
      );
    }
    if (root['artifactKind'] != _artifactKind) {
      throw FormatException('바탕 색인이 아닌 산출물입니다: ${root['artifactKind']}');
    }
    final variantsJson = _objectOf(root['variants'], 'variants');
    final keys = RouteMapBasemapVariant.values.map(
      (variant) => variant.indexKey,
    );
    if (!_sameSet(variantsJson.keys, keys)) {
      throw FormatException(
        '바탕 색인 variants ${variantsJson.keys.toList()}가 ${keys.toList()}가 아닙니다.',
      );
    }
    final reader = _IndexReader(regionIds);
    final variants = {
      for (final variant in RouteMapBasemapVariant.values)
        variant: reader.variantOf(variant, variantsJson[variant.indexKey]),
    };
    final reference = variants[RouteMapBasemapVariant.outlined]!;
    for (final MapEntry(key: variant, value: files) in variants.entries) {
      if (!files._hasSameLines(reference)) {
        throw FormatException(
          '바탕 색인 ${variant.indexKey} 변형의 노선이 outlined 변형과 다릅니다.',
        );
      }
    }
    return RouteMapLineOverlayIndex._(variants);
  }

  final Map<RouteMapBasemapVariant, RouteMapBasemapVariantFiles> _variants;

  /// [variant] 변형의 바탕과 노선 레이어.
  RouteMapBasemapVariantFiles variant(RouteMapBasemapVariant variant) =>
      _variants[variant]!;
}

bool _sameSet(Iterable<String> a, Iterable<String> b) {
  final left = a.toSet();
  final right = b.toSet();
  return left.length == right.length && left.containsAll(right);
}

Map<String, dynamic> _objectOf(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('바탕 색인 $path가 객체가 아닙니다.');
  }
  return value;
}

/// 색인 한 개를 읽는 동안 앱 권역과, 이미 다른 항목이 가리킨 파일을 들고 있다.
class _IndexReader {
  _IndexReader(this._regionIds);

  final Set<String> _regionIds;
  final Set<String> _seenVectors = {};

  RouteMapBasemapVariantFiles variantOf(
    RouteMapBasemapVariant variant,
    Object? json,
  ) {
    final path = 'variants.${variant.indexKey}';
    final entry = _objectOf(json, path);
    if (entry['labels'] != variant.labels) {
      throw FormatException(
        '바탕 색인 $path.labels ${entry['labels']}가 ${variant.labels}가 아닙니다.',
      );
    }
    final regions = _objectOf(entry['regions'], '$path.regions');
    if (!_sameSet(regions.keys, _regionIds)) {
      throw FormatException(
        '바탕 색인 $path.regions 권역 ${regions.keys.toList()}가 앱 권역 '
        '${_regionIds.toList()}와 다릅니다.',
      );
    }
    return RouteMapBasemapVariantFiles._({
      for (final MapEntry(key: regionId, value: region) in regions.entries)
        regionId: _regionOf(region, '$path.regions.$regionId'),
    });
  }

  _RegionAssets _regionOf(Object? json, String path) {
    final region = _objectOf(json, path);
    return (
      base: _assetOf(region, 'baseVector', 'baseVectorSha256', path),
      lines: {
        for (final MapEntry(key: lineId, value: line) in _objectOf(
          region['lines'],
          '$path.lines',
        ).entries)
          lineId: _assetOf(
            _objectOf(line, '$path.lines.$lineId'),
            'vector',
            'sha256',
            '$path.lines.$lineId',
          ),
      },
    );
  }

  /// 항목의 .vec 자산 경로. 파일 sha256은 앱이 쓰지 않지만 색인 계약이라 모양을 확인한다.
  String _assetOf(
    Map<String, dynamic> entry,
    String vectorKey,
    String sha256Key,
    String path,
  ) {
    final vector = entry[vectorKey];
    if (vector is! String || !_vectorFileName.hasMatch(vector)) {
      throw FormatException('바탕 색인 $path.$vectorKey 파일 이름이 잘못됐습니다: $vector');
    }
    if (!_seenVectors.add(vector)) {
      throw FormatException('바탕 색인 $path.$vectorKey $vector를 다른 항목도 가리킵니다.');
    }
    final sha256 = entry[sha256Key];
    if (sha256 is! String || !_sha256.hasMatch(sha256)) {
      throw FormatException('바탕 색인 $path.$sha256Key sha256이 잘못됐습니다: $sha256');
    }
    return '$kRouteMapBasemapAssetDir/$vector';
  }
}
