import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../domain/network_map_models.dart';
import '../domain/network_map_station_spatial_index.dart';
import '../domain/route_map_label_polygon.dart';
import '../infrastructure/cached_route_map_path.dart';
import 'network_map_camera_policy.dart';

class NetworkMapGeometry {
  NetworkMapGeometry({
    required this.origin,
    required this.focus,
    required this.width,
    required this.height,
    Rect? initialBounds,
    this.overlayStyleScale = 1.0,
    NetworkMapStationSpatialIndex? stationIndex,
  }) : initialBounds = initialBounds ?? Rect.fromLTWH(0, 0, width, height),
       stationIndex = stationIndex ?? NetworkMapStationSpatialIndex.empty;

  final Offset origin;
  final Offset focus;
  final double width;
  final double height;
  final Rect initialBounds;
  final double overlayStyleScale;
  final NetworkMapStationSpatialIndex stationIndex;

  factory NetworkMapGeometry.fromStations(
    List<NetworkMapStation> stations, {
    // Owner-label sidecar의 실제 렌더 extents는 합성 label polygon보다 넓을 수
    // 있으므로 초기 fit과 pan bounds가 라벨을 자르지 않게 함께 union한다.
    List<Rect> ownerLabelSourceRects = const [],
    required Rect Function(
      NetworkMapStation station,
      NetworkMapGeometry geometry,
    )
    stationSourceBoundsFor,
    required String Function(NetworkMapStation station) stationKeyFor,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
    final stationXs = <double>[];
    final stationYs = <double>[];
    for (final station in stations) {
      stationXs.add(station.position.x.toDouble());
      stationYs.add(station.position.y.toDouble());
      final point = Rect.fromCircle(
        center: Offset(
          station.position.x.toDouble(),
          station.position.y.toDouble(),
        ),
        radius: 18,
      );
      minX = math.min(minX, point.left);
      minY = math.min(minY, point.top);
      maxX = math.max(maxX, point.right);
      maxY = math.max(maxY, point.bottom);
      for (final pathData in [
        station.position.upPath,
        station.position.downPath,
      ]) {
        if (pathData.isEmpty) {
          continue;
        }
        final bounds = cachedRouteMapPath(pathData, Offset.zero).bounds;
        minX = math.min(minX, bounds.left);
        minY = math.min(minY, bounds.top);
        maxX = math.max(maxX, bounds.right);
        maxY = math.max(maxY, bounds.bottom);
      }
      final labelPolygon = parseRouteMapLabelPolygon(
        station.position.labelPolygon,
      );
      if (labelPolygon != null) {
        final bounds = networkMapPolygonBounds(labelPolygon);
        minX = math.min(minX, bounds.left);
        minY = math.min(minY, bounds.top);
        maxX = math.max(maxX, bounds.right);
        maxY = math.max(maxY, bounds.bottom);
      }
    }
    for (final rect in ownerLabelSourceRects) {
      minX = math.min(minX, rect.left);
      minY = math.min(minY, rect.top);
      maxX = math.max(maxX, rect.right);
      maxY = math.max(maxY, rect.bottom);
    }
    if (!minX.isFinite || !minY.isFinite) {
      return NetworkMapGeometry(
        origin: Offset.zero,
        focus: const Offset(430, 280),
        width: 860,
        height: 560,
      );
    }
    const margin = 54.0;
    final origin = Offset(minX - margin, minY - margin);
    final geometry = NetworkMapGeometry(
      origin: origin,
      focus: Offset(
        _median(stationXs) - origin.dx,
        _median(stationYs) - origin.dy,
      ),
      width: math.max(860, maxX - minX + margin * 2),
      height: math.max(560, maxY - minY + margin * 2),
    );
    final result = NetworkMapGeometry(
      origin: geometry.origin,
      focus: geometry.focus,
      width: geometry.width,
      height: geometry.height,
      initialBounds: _readableBoundsFor(
        geometry,
        stationCount: stations.length,
      ),
    );
    return result.copyWith(
      stationIndex: NetworkMapStationSpatialIndex.fromStations(
        stations,
        sourceBoundsForStation: (station) =>
            stationSourceBoundsFor(station, result),
        stationKeyFor: stationKeyFor,
      ),
    );
  }

  double x(NetworkMapStation station) => station.position.x - origin.dx;

  double y(NetworkMapStation station) => station.position.y - origin.dy;

  NetworkMapGeometry copyWith({NetworkMapStationSpatialIndex? stationIndex}) {
    return NetworkMapGeometry(
      origin: origin,
      focus: focus,
      width: width,
      height: height,
      initialBounds: initialBounds,
      overlayStyleScale: overlayStyleScale,
      stationIndex: stationIndex ?? this.stationIndex,
    );
  }
}

Rect _readableBoundsFor(
  NetworkMapGeometry geometry, {
  required int stationCount,
}) {
  // 소규모 지역은 전체를 기준선으로 두고, 큰 지역만 기존 38% 도심 기준선을 쓴다.
  if (networkMapUsesWholeRegionInitialView(stationCount)) {
    return Rect.fromLTWH(0, 0, geometry.width, geometry.height);
  }
  final width = math.min(
    geometry.width,
    math.max(320.0, geometry.width * 0.38),
  );
  final height = math.min(
    geometry.height,
    math.max(320.0, geometry.height * 0.38),
  );
  final maxLeft = math.max(0.0, geometry.width - width);
  final maxTop = math.max(0.0, geometry.height - height);
  final left = (geometry.focus.dx - width / 2).clamp(0.0, maxLeft).toDouble();
  final top = (geometry.focus.dy - height / 2).clamp(0.0, maxTop).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

Rect networkMapPolygonBounds(List<Offset> polygon) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in polygon) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _median(List<double> values) {
  values.sort();
  return values[values.length ~/ 2];
}
