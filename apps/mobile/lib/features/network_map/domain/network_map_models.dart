import 'package:flutter/widgets.dart';

import 'route_map_label_polygon.dart';
import 'route_map_major_stations.dart';
import 'route_map_min_scale.dart';
import 'structured_route_map.dart';

abstract interface class NetworkMapRepository {
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId});
}

abstract interface class NetworkMapViewportRepository {
  Future<String?> loadSelectedRegion();

  Future<void> saveSelectedRegion(String region);

  Future<Rect?> loadViewport(String region);

  Future<void> saveViewport({required String region, required Rect viewport});
}

class NetworkMapData {
  const NetworkMapData({
    required this.regions,
    required this.selectedRegion,
    required this.lines,
    required this.stations,
    required this.edges,
    required this.positionSources,
    this.stationLineMemberships = const [],
    this.lineTracks = const [],
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final List<NetworkMapLine> lines;
  final List<NetworkMapStation> stations;
  final List<NetworkMapEdge> edges;
  final List<NetworkMapPositionSource> positionSources;
  final List<NetworkMapStationLineMembership> stationLineMemberships;

  /// 노선별 실제 track polyline (#1638). route_map_line_tracks에서 온다 —
  /// 렌더러 line geometry의 source(역별 down_path 조립을 대체).
  final List<NetworkMapLineTrack> lineTracks;

  factory NetworkMapData.fromJson(Map<String, Object?> json) {
    return NetworkMapData(
      regions: _objectList(
        json['regions'],
      ).map(NetworkMapRegion.fromJson).toList(growable: false),
      selectedRegion: json['selectedRegion'] as String? ?? '',
      lines: _objectList(
        json['lines'],
      ).map(NetworkMapLine.fromJson).toList(growable: false),
      stations: _objectList(
        json['stations'],
      ).map(NetworkMapStation.fromJson).toList(growable: false),
      edges: _objectList(
        json['edges'],
      ).map(NetworkMapEdge.fromJson).toList(growable: false),
      positionSources: _objectList(
        json['positionSources'],
      ).map(NetworkMapPositionSource.fromJson).toList(growable: false),
      stationLineMemberships: _objectList(
        json['stationLineMemberships'],
      ).map(NetworkMapStationLineMembership.fromJson).toList(growable: false),
      lineTracks: _objectList(
        json['lineTracks'],
      ).map(NetworkMapLineTrack.fromJson).toList(growable: false),
    );
  }

  /// 구조화 노선도 레이어(#1636 스키마 기준)를 파생한다. native canvas
  /// 렌더러(#1641)가 소비하는 line geometry / transfer group / label·LOD를
  /// route_map_positions 필드에서 계산한다.
  StructuredRouteMap toStructuredRouteMap() {
    // major 거점 allowlist(비환승) 역명 → 현재 지역 station_id 집합(#1764 C).
    // 종점 major는 빌더가 자동 산출하므로 여기서는 거점만 매핑한다.
    final landmarkNames =
        routeMapMajorLandmarkStationNamesByRegion[selectedRegion] ??
        const <String>{};
    final majorStationIds = landmarkNames.isEmpty
        ? const <String>{}
        : <String>{
            for (final station in stations)
              if (landmarkNames.contains(station.nameKo)) station.id,
          };
    return buildStructuredRouteMap(
      stations.map(
        (station) => StructuredRouteMapStationInput(
          stationId: station.id,
          lineId: station.lineId,
          sequence: station.sequence,
          position: Offset(
            station.position.x.toDouble(),
            station.position.y.toDouble(),
          ),
          labelPolygon:
              parseRouteMapLabelPolygon(station.position.labelPolygon) ??
              const [],
        ),
      ),
      lineTracks: [
        for (final track in lineTracks)
          RouteMapLineTrackInput(lineId: track.lineId, paths: track.paths),
      ],
      majorStationIds: majorStationIds,
    );
  }
}

/// 한 노선의 track 조각들 (#1638). route_map_line_tracks의 path 문자열 목록.
class NetworkMapLineTrack {
  const NetworkMapLineTrack({required this.lineId, required this.paths});

  final String lineId;

  /// track_index 순서의 "M x y L x y ..." path 문자열들.
  final List<String> paths;

  factory NetworkMapLineTrack.fromJson(Map<String, Object?> json) {
    return NetworkMapLineTrack(
      lineId: json['lineId'] as String? ?? '',
      paths:
          (json['paths'] as List<Object?>?)
              ?.map((value) => value as String)
              .toList(growable: false) ??
          const [],
    );
  }
}

class NetworkMapStationLineMembership {
  const NetworkMapStationLineMembership({
    required this.stationId,
    required this.lineId,
  });

  final String stationId;
  final String lineId;

  factory NetworkMapStationLineMembership.fromJson(Map<String, Object?> json) {
    return NetworkMapStationLineMembership(
      stationId: json['stationId'] as String? ?? '',
      lineId: json['lineId'] as String? ?? '',
    );
  }
}

class NetworkMapRegion {
  const NetworkMapRegion({required this.name});

  final String name;
  String get displayName => routeMapDisplayRegionName(name);

  factory NetworkMapRegion.fromJson(Map<String, Object?> json) {
    return NetworkMapRegion(name: json['name'] as String? ?? '');
  }
}

class NetworkMapLine {
  const NetworkMapLine({
    required this.id,
    required this.name,
    required this.color,
    required this.region,
  });

  final String id;
  final String name;
  final String color;
  final String region;

  factory NetworkMapLine.fromJson(Map<String, Object?> json) {
    return NetworkMapLine(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['nameKo'] as String? ?? '',
      color: json['color'] as String? ?? '#006D77',
      region: json['region'] as String? ?? '',
    );
  }

  String get shortName {
    final withoutRegion = name.replaceFirst('수도권 ', '');
    return withoutRegion.isEmpty ? name : withoutRegion;
  }

  String get badgeText {
    final label = shortName.replaceAll('호선', '');
    final numberMatch = RegExp(r'(\d+)').firstMatch(label);
    if (numberMatch != null) {
      return numberMatch.group(1)!;
    }
    if (label.contains('GTX-A')) {
      return 'A';
    }
    final compact = label
        .replaceAll('부산김해경전철', '김해')
        .replaceAll('김포골드라인', '김포')
        .replaceAll('경의중앙', '경의')
        .replaceAll('수인분당', '수인')
        .replaceAll('우이신설', '우이')
        .replaceAll('신분당', '신분')
        .replaceAll('에버라인', '에버')
        .replaceAll('자기부상', '자기')
        .replaceAll('의정부', '의정');
    return compact.characters.take(2).toString();
  }
}

class NetworkMapStation {
  const NetworkMapStation({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.lineId,
    required this.stationCode,
    required this.sequence,
    required this.position,
  });

  final String id;
  final String nameKo;
  final String nameEn;
  final String region;
  final String lineId;
  final String stationCode;
  final int sequence;
  final NetworkMapPosition position;

  String get displayName => nameKo.endsWith('역') ? nameKo : '$nameKo역';

  factory NetworkMapStation.fromJson(Map<String, Object?> json) {
    return NetworkMapStation(
      id: json['id'] as String? ?? '',
      nameKo: json['nameKo'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      region: json['region'] as String? ?? '',
      lineId: json['lineId'] as String? ?? '',
      stationCode: json['stationCode'] as String? ?? '',
      sequence: json['sequence'] as int? ?? 0,
      position: NetworkMapPosition.fromJson(
        (json['position'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }
}

class NetworkMapPosition {
  const NetworkMapPosition({
    required this.x,
    required this.y,
    required this.labelDx,
    required this.labelDy,
    required this.upPath,
    required this.downPath,
    required this.sourceId,
    this.labelPolygon = '',
  });

  final int x;
  final int y;
  final int labelDx;
  final int labelDy;
  final String labelPolygon;
  final String upPath;
  final String downPath;
  final String sourceId;

  factory NetworkMapPosition.fromJson(Map<String, Object?> json) {
    return NetworkMapPosition(
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      labelDx: json['labelDx'] as int? ?? 0,
      labelDy: json['labelDy'] as int? ?? 0,
      labelPolygon: json['labelPolygon'] as String? ?? '',
      upPath: json['upPath'] as String? ?? '',
      downPath: json['downPath'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
    );
  }
}

class NetworkMapEdge {
  const NetworkMapEdge({
    required this.id,
    required this.lineId,
    required this.fromStationId,
    required this.toStationId,
    required this.accessibilityStatus,
    required this.reliabilityScore,
  });

  final String id;
  final String lineId;
  final String fromStationId;
  final String toStationId;
  final String accessibilityStatus;
  final int reliabilityScore;

  factory NetworkMapEdge.fromJson(Map<String, Object?> json) {
    return NetworkMapEdge(
      id: json['id'] as String? ?? '',
      lineId: json['lineId'] as String? ?? '',
      fromStationId: json['fromStationId'] as String? ?? '',
      toStationId: json['toStationId'] as String? ?? '',
      accessibilityStatus: json['accessibilityStatus'] as String? ?? 'UNKNOWN',
      reliabilityScore: json['reliabilityScore'] as int? ?? 0,
    );
  }
}

class NetworkMapPositionSource {
  const NetworkMapPositionSource({
    required this.id,
    required this.name,
    required this.licenseStatus,
  });

  final String id;
  final String name;
  final String licenseStatus;

  factory NetworkMapPositionSource.fromJson(Map<String, Object?> json) {
    return NetworkMapPositionSource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      licenseStatus: json['licenseStatus'] as String? ?? '',
    );
  }
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}
