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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteMapOwnerNodeEntry &&
          runtimeType == other.runtimeType &&
          stationId == other.stationId &&
          lineId == other.lineId &&
          name == other.name &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(stationId, lineId, name, x, y);

  @override
  String toString() =>
      'RouteMapOwnerNodeEntry($name, $stationId, $lineId, x: $x, y: $y)';
}

/// 경의중앙선 식별: 정규 카탈로그 ID(line-6e39be0cb6e2) 또는 친화 식별자(경의/gyeongui)
bool isGyeonguiLineId(String lineId) {
  final l = lineId.toLowerCase();
  return l == 'line-6e39be0cb6e2' || l.contains('gyeongui') || l.contains('경의');
}

/// 2호선 식별: 'seoul-2', 'line-2', '2호선' 등
bool isLine2(String lineId) {
  final l = lineId.toLowerCase();
  return l == 'seoul-2' || l == 'line-2' || l == '2' || l.contains('2호선');
}

/// 5호선 식별: 'line-80fc4d5350d4', 'line-5', '5호선' 등
bool isLine5(String lineId) {
  final l = lineId.toLowerCase();
  return l == 'line-80fc4d5350d4' ||
      l == 'line-5' ||
      l == '5' ||
      l.contains('5호선');
}

/// 동해선 식별 (부산): 'line-f52eb59d8497', 'donghae', '동해'
bool isDonghaeLineId(String lineId) {
  final l = lineId.toLowerCase();
  return l == 'line-f52eb59d8497' || l.contains('donghae') || l.contains('동해');
}

/// 부산 1호선 식별: 'line-ab1a041f6266', 'busan-1', '1호선' 등
bool isBusanLine1(String lineId) {
  final l = lineId.toLowerCase();
  return l == 'line-ab1a041f6266' || l == 'busan-1' || l.contains('1호선');
}

/// 동명이역(예: 신촌, 양평, 부산 부전/좌천/동래) 후보 중 역의 호선/속성에 가장 적합한 노드 엔트리를 선택한다.
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

  // 1. 동일 라인 완전 일치 우선 (station.lineId == entry.lineId)
  if (station.lineId.isNotEmpty) {
    for (final entry in entries) {
      if (entry.lineId == station.lineId) {
        return entry;
      }
    }
  }

  // 2. 신촌: 2호선(seoul-2, y > 1200) vs 경의중앙선(line-6e39be0cb6e2, y < 1200)
  if (station.nameKo.contains('신촌')) {
    final isGyeongui = isGyeonguiLineId(station.lineId);
    final isL2 = isLine2(station.lineId);
    if (isGyeongui || isL2) {
      for (final entry in entries) {
        final isEntryGyeongui =
            isGyeonguiLineId(entry.lineId) || entry.y < 1200;
        if (isGyeongui == isEntryGyeongui) {
          return entry;
        }
      }
    }
    final prefersGyeongui = station.position.y > 0 && station.position.y < 1200;
    for (final entry in entries) {
      final isEntryNorthern = entry.y < 1200;
      if (prefersGyeongui == isEntryNorthern) {
        return entry;
      }
    }
  }

  // 3. 양평: 5호선(도심 영등포, line-80fc4d5350d4, y > 1000) vs 경의중앙선(양평군, line-6e39be0cb6e2, y < 1000)
  if (station.nameKo.contains('양평')) {
    final isGyeongui = isGyeonguiLineId(station.lineId);
    final isL5 = isLine5(station.lineId);
    if (isGyeongui || isL5) {
      for (final entry in entries) {
        final isEntryGyeongui =
            isGyeonguiLineId(entry.lineId) || entry.y < 1000;
        if (isGyeongui == isEntryGyeongui) {
          return entry;
        }
      }
    }
    final prefersNorthern = station.position.y > 0 && station.position.y < 1000;
    for (final entry in entries) {
      final isNorthern = entry.y < 1000;
      if (prefersNorthern == isNorthern) {
        return entry;
      }
    }
  }

  // 4. 부산 동명이역 (부전, 좌천, 동래): 동해선(line-f52eb59d8497) vs 1호선/4호선
  if (station.nameKo.contains('부전') ||
      station.nameKo.contains('좌천') ||
      station.nameKo.contains('동래')) {
    final isDonghae = isDonghaeLineId(station.lineId);
    final isL1 = isBusanLine1(station.lineId);
    if (isDonghae || isL1) {
      for (final entry in entries) {
        final isEntryDonghae = isDonghaeLineId(entry.lineId);
        if (isDonghae == isEntryDonghae) {
          return entry;
        }
      }
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
