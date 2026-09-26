import 'dart:convert' show jsonDecode;
import 'dart:ui' show Offset;

import 'network_map_models.dart';
import 'network_map_station_aligner.dart' show normalizeStationNameForBasemap;

/// 오너 SVG basemap의 역 노드(circle / capsule centroid) 실측 중심 좌표 1건.
class RouteMapOwnerNodeEntry {
  const RouteMapOwnerNodeEntry({
    required this.stationId,
    required this.lineId,
    required this.name,
    required this.x,
    required this.y,
  });

  /// 카탈로그 station_id.
  final String stationId;

  /// 카탈로그 line_id.
  final String lineId;

  /// 정본 역명.
  final String name;

  /// SVG viewBox(source) X 좌표.
  final int x;

  /// SVG viewBox(source) Y 좌표.
  final int y;

  /// [Offset] 좌표.
  Offset get position => Offset(x.toDouble(), y.toDouble());
}

/// 동명이역(예: 신촌, 양평) 후보 중 역의 호선/속성에 가장 적합한 노드 엔트리를 선택한다.
RouteMapOwnerNodeEntry matchBestNodeEntry(
  NetworkMapStation station,
  List<RouteMapOwnerNodeEntry> entries,
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
      final entryLineId = entry.lineId.toLowerCase();
      final isEntryGyeongui =
          entryLineId.contains('gyeongui') || entryLineId.contains('경의');
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
      final isNorthern = entry.y < 1000;
      if (isGyeongui == isNorthern) {
        return entry;
      }
    }
  }
  // 동일 라인 매칭 우선
  for (final entry in entries) {
    if (entry.lineId == station.lineId) {
      return entry;
    }
  }
  return entries.first;
}

/// 한 권역의 [RouteMapOwnerNodeEntry] 목록을 고속 조회하기 위한 인덱스 맵.
class RouteMapOwnerNodesLookup {
  RouteMapOwnerNodesLookup({required this.entries}) {
    for (final entry in entries) {
      if (entry.stationId.isNotEmpty && entry.lineId.isNotEmpty) {
        _byStationAndLine['${entry.stationId}:${entry.lineId}'] = entry;
      }
      if (entry.stationId.isNotEmpty) {
        _byStationId[entry.stationId] = entry;
      }
      final normName = normalizeStationNameForBasemap(entry.name);
      if (entry.lineId.isNotEmpty) {
        _byNameAndLine['$normName:${entry.lineId}'] = entry;
      }
      _byName.putIfAbsent(normName, () => []).add(entry);
      if (normName != entry.name) {
        _byName.putIfAbsent(entry.name, () => []).add(entry);
      }
    }
  }

  final List<RouteMapOwnerNodeEntry> entries;
  final Map<String, RouteMapOwnerNodeEntry> _byStationAndLine = {};
  final Map<String, RouteMapOwnerNodeEntry> _byStationId = {};
  final Map<String, RouteMapOwnerNodeEntry> _byNameAndLine = {};
  final Map<String, List<RouteMapOwnerNodeEntry>> _byName = {};

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// 역에 해당하는 노드 엔트리를 다단계로 정밀 매칭한다.
  RouteMapOwnerNodeEntry? findNode(NetworkMapStation station) {
    // 1. (stationId, lineId) 정확 일치
    if (station.id.isNotEmpty && station.lineId.isNotEmpty) {
      final match = _byStationAndLine['${station.id}:${station.lineId}'];
      if (match != null) return match;
    }

    // 2. stationId 일치
    if (station.id.isNotEmpty) {
      final match = _byStationId[station.id];
      if (match != null) return match;
    }

    final normName = normalizeStationNameForBasemap(station.nameKo);

    // 3. (normalizedName, lineId) 일치
    if (station.lineId.isNotEmpty) {
      final match = _byNameAndLine['$normName:${station.lineId}'];
      if (match != null) return match;
    }

    // 4. nameKo 일치 후보군 중 최적 매칭
    final candidates = _byName[normName] ?? _byName[station.nameKo];
    if (candidates != null && candidates.isNotEmpty) {
      if (candidates.length == 1) {
        return candidates.first;
      }
      return matchBestNodeEntry(station, candidates);
    }

    return null;
  }
}

/// basemap 노드 좌표 sidecar asset 경로.
const String kRouteMapOwnerNodesAssetPath =
    'assets/datapacks/metro_map_pack/basemap/nodes.json';

RouteMapOwnerNodesLookup _buildOwnerNodesLookup(Object? regionEntries) {
  if (regionEntries is! List) {
    return RouteMapOwnerNodesLookup(entries: const []);
  }
  final entries = <RouteMapOwnerNodeEntry>[];
  for (final raw in regionEntries) {
    if (raw is! Map) continue;
    final stationId = raw['stationId'] as String? ?? '';
    final lineId = raw['lineId'] as String? ?? '';
    final name = raw['name'] as String? ?? '';
    final x = raw['x'];
    final y = raw['y'];
    if (x is! num || y is! num) continue;
    entries.add(
      RouteMapOwnerNodeEntry(
        stationId: stationId,
        lineId: lineId,
        name: name,
        x: x.toInt(),
        y: y.toInt(),
      ),
    );
  }
  return RouteMapOwnerNodesLookup(entries: entries);
}

/// sidecar 전체 JSON을 region별로 한 번에 파싱한다.
Map<String, RouteMapOwnerNodesLookup> routeMapOwnerNodesByRegionFrom(
  String sidecarJson,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(sidecarJson);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map || decoded['regions'] is! Map) {
    return const {};
  }
  final regions = decoded['regions'] as Map;
  return {
    for (final key in regions.keys)
      if (key is String) key: _buildOwnerNodesLookup(regions[key]),
  };
}
