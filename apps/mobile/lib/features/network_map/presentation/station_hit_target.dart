import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/map_camera.dart';
import '../domain/network_map_models.dart';
import '../domain/network_map_station_tap_score.dart';
import '../domain/route_map_label_polygon.dart';
import '../infrastructure/cached_route_map_path.dart';
import 'network_map_geometry.dart';

const _maximumStationHitDistance = 24.0;

@visibleForTesting
const double networkMapStationHitTargetLogicalSize =
    _maximumStationHitDistance * 2;

class NetworkMapStationHitTarget extends StatelessWidget {
  const NetworkMapStationHitTarget({
    required this.station,
    required this.onTap,
    super.key,
  });

  final NetworkMapStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 팬 성능: 축소 상태에서 화면에 잡히는 canonical 역이 수백 개(예: 수도권
    // 축소 시 300~450개)라, 제스처 종료 프레임에서 이 오버레이가 한 번에 재구축
    // 되며 큰 build 스파이크를 만든다. 여기서 GestureDetector를 개별 역마다 두면
    // 그 비용이 배가되는데, 시각(포인터) 탭은 이미 배경 GestureDetector의
    // onTapUp → `_openNearestStation`(`_stationAtViewportPosition` 공간 히트
    // 테스트)이 노드·라벨 폴리곤까지 고려해 전담하므로 개별 GestureDetector는
    // 중복이다. 접근성(스크린리더) 탭만 Semantics onTap 액션으로 남겨 역별
    // 버튼 시맨틱을 유지한다.
    return Semantics(
      button: true,
      label: station.displayName,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}

class NetworkMapStationHitGeometry {
  const NetworkMapStationHitGeometry({required this.geometry});

  final NetworkMapGeometry geometry;

  static String stationKeyFor(NetworkMapStation station) {
    return '${station.id}:${station.lineId}';
  }

  static Rect sourceBoundsForStation(
    NetworkMapStation station,
    NetworkMapGeometry geometry, {
    double nodeRadius = 24,
    double labelHeight = 40,
  }) {
    final node = Rect.fromCenter(
      center: Offset(geometry.x(station), geometry.y(station)),
      width: nodeRadius * 2,
      height: nodeRadius * 2,
    );
    final labelPolygon = _labelPolygonFor(station, geometry);
    if (labelPolygon != null) {
      return node.expandToInclude(networkMapPolygonBounds(labelPolygon));
    }
    return node.expandToInclude(
      _stationLabelRect(station, geometry, labelHeight: labelHeight),
    );
  }

  Rect sourceBoundsFor(
    NetworkMapStation station, {
    double nodeRadius = 24,
    double labelHeight = 40,
  }) {
    return sourceBoundsForStation(
      station,
      geometry,
      nodeRadius: nodeRadius,
      labelHeight: labelHeight,
    );
  }

  Rect viewportBoundsFor(
    NetworkMapStation station, {
    required MapCameraState camera,
    double nodeRadius = 24,
    double labelHeight = 40,
  }) {
    return _sourceRectToViewport(
      sourceBoundsFor(
        station,
        nodeRadius: nodeRadius,
        labelHeight: labelHeight,
      ),
      camera,
    );
  }

  List<NetworkMapStation> visibleCanonicalStations({
    required MapCameraState camera,
  }) {
    final visibleSourceRect = camera.visibleSourceRect.inflate(
      96 / camera.scale,
    );
    return _canonicalStations(
      geometry.stationIndex.query(visibleSourceRect).where((station) {
        return sourceBoundsFor(station).overlaps(visibleSourceRect);
      }),
    );
  }

  NetworkMapStation? stationAtViewportPosition(
    Offset viewportPosition, {
    required MapCameraState camera,
  }) {
    final safeScale = camera.scale > 0 ? camera.scale : 1.0;
    final sourcePosition = camera.viewportToSourcePoint(viewportPosition);
    final sourceQuery = Rect.fromCircle(
      center: sourcePosition,
      radius: _maximumStationHitDistance / safeScale,
    );
    NetworkMapStation? bestStation;
    NetworkMapStationTapScore? bestScore;
    for (final station in geometry.stationIndex.query(sourceQuery)) {
      final score = _stationTapScore(viewportPosition, station, camera);
      if (score == null) {
        continue;
      }
      if (bestScore == null || score.compareTo(bestScore) < 0) {
        bestScore = score;
        bestStation = station;
      }
    }
    return bestStation;
  }

  List<NetworkMapStation> _canonicalStations(
    Iterable<NetworkMapStation> stations,
  ) {
    final canonicalStations = <NetworkMapStation>[];
    for (final station in stations) {
      final existingIndex = canonicalStations.indexWhere((existing) {
        return existing.id == station.id &&
            sourceBoundsFor(
              existing,
            ).inflate(8).overlaps(sourceBoundsFor(station).inflate(8));
      });
      if (existingIndex == -1) {
        canonicalStations.add(station);
        continue;
      }
      final existing = canonicalStations[existingIndex];
      if (_stationGeometryPriority(station) >
          _stationGeometryPriority(existing)) {
        canonicalStations[existingIndex] = station;
      }
    }
    return canonicalStations;
  }

  NetworkMapStationTapScore? _stationTapScore(
    Offset viewportPosition,
    NetworkMapStation station,
    MapCameraState camera,
  ) {
    final safeScale = camera.scale > 0 ? camera.scale : 1.0;
    final nodeCenter = camera.sourceToViewportPoint(
      Offset(geometry.x(station), geometry.y(station)),
    );
    final nodeHitRect = Rect.fromCenter(
      center: nodeCenter,
      width: networkMapStationHitTargetLogicalSize,
      height: networkMapStationHitTargetLogicalSize,
    );
    final containsNode = nodeHitRect.contains(viewportPosition);
    final nodeDistance = (viewportPosition - nodeCenter).distance;
    var bestHitDistance = containsNode ? 0.0 : double.infinity;
    var bestSelectionDistance = containsNode ? nodeDistance : double.infinity;
    var containsShape = containsNode;
    final labelPolygon = _labelPolygonFor(station, geometry);
    if (labelPolygon != null) {
      final viewportPolygon = [
        for (final point in labelPolygon) camera.sourceToViewportPoint(point),
      ];
      final polygonDistance = math.sqrt(
        _distanceSquaredToPolygon(viewportPosition, viewportPolygon),
      );
      bestHitDistance = math.min(bestHitDistance, polygonDistance);
      if (polygonDistance <= _maximumStationHitDistance) {
        bestSelectionDistance = math.min(
          bestSelectionDistance,
          polygonDistance,
        );
      }
      containsShape = containsShape || polygonDistance == 0;
    } else {
      final labelRect = _sourceRectToViewport(
        _stationLabelRect(station, geometry, labelHeight: 40 / safeScale),
        camera,
      );
      final labelDistance = _distanceToRect(viewportPosition, labelRect);
      bestHitDistance = math.min(bestHitDistance, labelDistance);
      if (labelDistance <= _maximumStationHitDistance) {
        bestSelectionDistance = math.min(
          bestSelectionDistance,
          (viewportPosition - labelRect.center).distance,
        );
      }
      containsShape = containsShape || labelDistance == 0;
    }
    if (bestHitDistance > _maximumStationHitDistance) {
      return null;
    }
    return NetworkMapStationTapScore(
      containsNode: containsNode,
      containsShape: containsShape,
      screenDistance: bestSelectionDistance.isFinite
          ? bestSelectionDistance
          : bestHitDistance,
      stableKey: stationKeyFor(station),
    );
  }
}

@visibleForTesting
Rect networkMapGeometrySourceBoundsFor(
  List<NetworkMapStation> stations, {
  List<Rect> ownerLabelSourceRects = const [],
}) {
  final geometry = NetworkMapGeometry.fromStations(
    stations,
    ownerLabelSourceRects: ownerLabelSourceRects,
    stationSourceBoundsFor: NetworkMapStationHitGeometry.sourceBoundsForStation,
    stationKeyFor: NetworkMapStationHitGeometry.stationKeyFor,
  );
  return Rect.fromLTWH(
    geometry.origin.dx,
    geometry.origin.dy,
    geometry.width,
    geometry.height,
  );
}

Rect _sourceRectToViewport(Rect sourceRect, MapCameraState camera) {
  final topLeft = camera.sourceToViewportPoint(sourceRect.topLeft);
  final bottomRight = camera.sourceToViewportPoint(sourceRect.bottomRight);
  return Rect.fromLTRB(
    math.min(topLeft.dx, bottomRight.dx),
    math.min(topLeft.dy, bottomRight.dy),
    math.max(topLeft.dx, bottomRight.dx),
    math.max(topLeft.dy, bottomRight.dy),
  );
}

int _stationGeometryPriority(NetworkMapStation station) {
  if (station.position.labelPolygon.isNotEmpty) {
    return 3;
  }
  if (station.position.upPath.isNotEmpty ||
      station.position.downPath.isNotEmpty) {
    return 2;
  }
  return 1;
}

Rect _stationLabelRect(
  NetworkMapStation station,
  NetworkMapGeometry geometry, {
  double labelHeight = 40,
}) {
  final labelOffset = _labelOffsetFor(station);
  final labelCenter = Offset(
    geometry.x(station) + labelOffset.dx,
    geometry.y(station) + labelOffset.dy,
  );
  return Rect.fromCenter(
    center: labelCenter,
    width: math.max(64, station.nameKo.characters.length * 18 + 32),
    height: labelHeight,
  );
}

double _distanceToRect(Offset point, Rect rect) {
  if (rect.contains(point)) {
    return 0;
  }
  final dx = point.dx < rect.left
      ? rect.left - point.dx
      : point.dx > rect.right
      ? point.dx - rect.right
      : 0.0;
  final dy = point.dy < rect.top
      ? rect.top - point.dy
      : point.dy > rect.bottom
      ? point.dy - rect.bottom
      : 0.0;
  return math.sqrt(dx * dx + dy * dy);
}

List<Offset>? _labelPolygonFor(
  NetworkMapStation station,
  NetworkMapGeometry geometry,
) {
  final polygon = parseRouteMapLabelPolygon(station.position.labelPolygon);
  if (polygon == null) {
    return null;
  }
  return [
    for (final point in polygon)
      Offset(point.dx - geometry.origin.dx, point.dy - geometry.origin.dy),
  ];
}

double _distanceSquaredToPolygon(Offset point, List<Offset> polygon) {
  if (_pointInPolygon(point, polygon)) {
    return 0;
  }
  var best = double.infinity;
  for (var index = 0; index < polygon.length; index += 1) {
    best = math.min(
      best,
      _distanceSquaredToSegment(
        point,
        polygon[index],
        polygon[(index + 1) % polygon.length],
      ),
    );
  }
  return best;
}

bool _pointInPolygon(Offset point, List<Offset> polygon) {
  var inside = false;
  for (
    var index = 0, previous = polygon.length - 1;
    index < polygon.length;
    previous = index, index += 1
  ) {
    final currentPoint = polygon[index];
    final previousPoint = polygon[previous];
    final crossesY =
        (currentPoint.dy > point.dy) != (previousPoint.dy > point.dy);
    if (!crossesY) {
      continue;
    }
    final intersectionX =
        (previousPoint.dx - currentPoint.dx) *
            (point.dy - currentPoint.dy) /
            (previousPoint.dy - currentPoint.dy) +
        currentPoint.dx;
    if (point.dx < intersectionX) {
      inside = !inside;
    }
  }
  return inside;
}

double _distanceSquaredToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.distanceSquared;
  if (lengthSquared == 0) {
    return (point - start).distanceSquared;
  }
  final t =
      (((point.dx - start.dx) * segment.dx) +
          ((point.dy - start.dy) * segment.dy)) /
      lengthSquared;
  final clampedT = t.clamp(0.0, 1.0).toDouble();
  final projection = Offset(
    start.dx + segment.dx * clampedT,
    start.dy + segment.dy * clampedT,
  );
  return (point - projection).distanceSquared;
}

bool _usesOfficialRouteMapSource(NetworkMapStation station) {
  return station.position.sourceId.endsWith('-cyberstation') ||
      station.position.sourceId == 'qa-wikimedia-seoul-svg-coordinate';
}

Offset _labelOffsetFor(NetworkMapStation station) {
  if (_usesOfficialRouteMapSource(station)) {
    return Offset(
      station.position.labelDx.toDouble(),
      station.position.labelDy.toDouble(),
    );
  }
  final pathData = station.position.downPath.isNotEmpty
      ? station.position.downPath
      : station.position.upPath;
  if (pathData.isEmpty) {
    return const Offset(8, 3);
  }
  final bounds = cachedRouteMapPath(pathData, Offset.zero).bounds;
  if (bounds.width > bounds.height * 1.2) {
    return const Offset(0, 12);
  }
  if (bounds.height > bounds.width * 1.2) {
    return const Offset(9, 3);
  }
  return const Offset(8, -8);
}
