import '../presentation/route_map_basemap_view.dart'
    show kRouteMapBasemapRegionToId;
import 'network_map_models.dart';
import 'route_map_min_scale.dart' show routeMapDisplayRegionName;
import 'route_map_owner_labels.dart';

/// 역명 정규화: '석남(거북시장)' -> '석남', '서해구청' -> '서구청' 등
/// 부역명/괄호 표기를 제거해 오너 SVG 라벨(`labels.json`)의 정본 역명과 매칭한다.
String normalizeStationNameForBasemap(String name) {
  final clean = name.replaceAll(RegExp(r'\(.*?\)'), '').trim();
  if (clean == '서해구청') {
    return '서구청';
  }
  return clean;
}

/// 동명이역(예: 신촌, 양평) 후보 중 역의 호선/속성에 가장 적합한 라벨 엔트리를 선택한다.
RouteMapOwnerLabelEntry matchBestOwnerEntry(
  NetworkMapStation station,
  List<RouteMapOwnerLabelEntry> entries,
) {
  if (entries.length == 1) {
    return entries.first;
  }
  // 신촌: 2호선 vs 경의중앙선
  if (station.nameKo.contains('신촌')) {
    final lineId = station.lineId.toLowerCase();
    final isGyeongui = lineId.contains('gyeongui') || lineId.contains('경의');
    for (final entry in entries) {
      final isEntryGyeongui = entry.lines.any(
        (line) => line.text.contains('경의'),
      );
      if (isGyeongui == isEntryGyeongui) {
        return entry;
      }
    }
  }
  // 양평: 5호선(도심, y > 1000) vs 경의중앙선(양평군, y < 1000)
  if (station.nameKo.contains('양평')) {
    final lineId = station.lineId.toLowerCase();
    final isGyeongui = lineId.contains('gyeongui') || lineId.contains('경의');
    for (final entry in entries) {
      final isNorthern = entry.position.dy < 1000;
      if (isGyeongui == isNorthern) {
        return entry;
      }
    }
  }
  return entries.first;
}

/// 오너 자작 SVG basemap(`labels.json`) 좌표계를 기준으로,
/// 비정규 외곽 좌표계(x/y > 5000)를 가진 역의 좌표를 SVG 실측 위치로 정렬한다.
NetworkMapStation alignStationForBasemap(
  NetworkMapStation station,
  Map<String, List<RouteMapOwnerLabelEntry>>? ownerEntries,
) {
  // 이미 도식 캔버스 내부 좌표(<= 5000)이거나 오너 자작 스키매틱 원천인 경우 그대로 유지.
  if (station.position.sourceId == 'owner-self-drawn-sma-schematic' ||
      (station.position.x <= 5000 && station.position.y <= 5000)) {
    return station;
  }
  if (ownerEntries == null || ownerEntries.isEmpty) {
    return station;
  }
  final entries =
      ownerEntries[station.nameKo] ??
      ownerEntries[normalizeStationNameForBasemap(station.nameKo)];
  if (entries == null || entries.isEmpty) {
    return station;
  }
  final entry = matchBestOwnerEntry(station, entries);
  return station.copyWith(
    position: station.position.copyWith(
      x: entry.position.dx.round(),
      y: entry.position.dy.round(),
      labelPolygon: '',
      upPath: '',
      downPath: '',
    ),
  );
}

/// [data]의 권역이 basemap 대상 권역일 때, 외곽 좌표계 역들을 정렬한 새 [NetworkMapData]를 생성한다.
NetworkMapData alignNetworkMapDataForBasemap(
  NetworkMapData data,
  Map<String, List<RouteMapOwnerLabelEntry>>? ownerEntries,
) {
  final basemapAssetId =
      kRouteMapBasemapRegionToId[routeMapDisplayRegionName(
        data.selectedRegion,
      )];
  if (basemapAssetId == null || ownerEntries == null || ownerEntries.isEmpty) {
    return data;
  }
  final alignedStations = [
    for (final station in data.stations)
      alignStationForBasemap(station, ownerEntries),
  ];
  return data.copyWith(stations: alignedStations);
}
