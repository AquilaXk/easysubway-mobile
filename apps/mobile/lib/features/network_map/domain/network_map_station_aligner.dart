import '../presentation/route_map_basemap_view.dart'
    show kRouteMapBasemapRegionToId;
import 'network_map_models.dart';
import 'route_map_min_scale.dart' show routeMapDisplayRegionName;
import 'route_map_owner_labels.dart';
import 'route_map_owner_nodes.dart';

/// 역명 정규화: '석남(거북시장)' -> '석남', '서해구청' -> '서구청' 등
/// 부역명/괄호 표기를 제거해 오너 SVG 노드(`nodes.json`) 및 라벨(`labels.json`)의 정본 역명과 매칭한다.
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
  if (entries.isEmpty) {
    throw ArgumentError.value(entries, 'entries', 'entries must not be empty');
  }
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

/// 오너 자작 SVG basemap(`nodes.json` / `labels.json`) 좌표계를 기준으로,
/// 역의 좌표를 SVG 실측 위치로 정렬한다.
///
/// 1) [ownerNodes]가 주어지면 exact node symbol 중심 좌표(circle / transfer capsule centroid)를 우선 바인딩한다.
///    환승역의 모든 호선(예: 옥수 3호선·경의중앙선)이 동일한 노드 중심 좌표를 공유하도록 보장한다.
/// 2) 이미 도식 캔버스 내부 좌표(<= 5000)이거나 오너 자작 스키매틱 원천인 경우 그대로 유지한다.
/// 3) [ownerNodes] 미제공 또는 미매칭 시 [ownerEntries](라벨 좌표)로 폴백한다.
NetworkMapStation alignStationForBasemap(
  NetworkMapStation station, {
  RouteMapOwnerNodesLookup? ownerNodes,
  Map<String, List<RouteMapOwnerLabelEntry>>? ownerEntries,
}) {
  // 1. exact node symbol center matching (nodes.json)
  if (ownerNodes != null) {
    final node = ownerNodes.findNode(station);
    if (node != null) {
      final isOutlier = station.position.x > 5000 || station.position.y > 5000;
      if (station.position.x == node.x &&
          station.position.y == node.y &&
          !isOutlier) {
        return station;
      }
      return station.copyWith(
        position: station.position.copyWith(
          x: node.x,
          y: node.y,
          labelPolygon: isOutlier ? '' : station.position.labelPolygon,
          upPath: isOutlier ? '' : station.position.upPath,
          downPath: isOutlier ? '' : station.position.downPath,
        ),
      );
    }
  }

  // 2. 이미 도식 캔버스 내부 좌표(<= 5000)이거나 오너 자작 스키매틱 원천인 경우 그대로 유지.
  if (station.position.sourceId == 'owner-self-drawn-sma-schematic' ||
      (station.position.x <= 5000 && station.position.y <= 5000)) {
    return station;
  }

  // 3. Fallback: labels.json
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
  NetworkMapData data, {
  RouteMapOwnerNodesLookup? ownerNodes,
  Map<String, List<RouteMapOwnerLabelEntry>>? ownerEntries,
}) {
  final basemapAssetId =
      kRouteMapBasemapRegionToId[routeMapDisplayRegionName(
        data.selectedRegion,
      )];
  final hasNodes = ownerNodes != null && ownerNodes.isNotEmpty;
  final hasEntries = ownerEntries != null && ownerEntries.isNotEmpty;
  if (basemapAssetId == null || (!hasNodes && !hasEntries)) {
    return data;
  }
  final alignedStations = [
    for (final station in data.stations)
      alignStationForBasemap(
        station,
        ownerNodes: ownerNodes,
        ownerEntries: ownerEntries,
      ),
  ];
  return data.copyWith(stations: alignedStations);
}
