import 'package:flutter/widgets.dart';

import 'network_map_models.dart';

/// 2D 정수 격자 좌표 `(gx, gy)`를 64비트 정수로 패킹한다.
/// 음수 `gy`의 상위 비트가 `gx`를 덮어쓰지 않도록 하위 32비트로 마스킹한다.
int packRouteMapGridKey(int gx, int gy) => (gx << 32) | (gy & 0xFFFFFFFF);

class NetworkMapStationSpatialIndex {
  NetworkMapStationSpatialIndex._({
    required this._buckets,
    required this._stationOrder,
    required this._stationKeyFor,
  });

  static final empty = NetworkMapStationSpatialIndex._(
    buckets: const {},
    stationOrder: const {},
    stationKeyFor: null,
  );

  static const _cellSize = 256.0;

  final Map<int, List<NetworkMapStation>> _buckets;
  final Map<String, int> _stationOrder;
  final String Function(NetworkMapStation station)? _stationKeyFor;

  factory NetworkMapStationSpatialIndex.fromStations(
    List<NetworkMapStation> stations, {
    required Rect Function(NetworkMapStation station) sourceBoundsForStation,
    required String Function(NetworkMapStation station) stationKeyFor,
  }) {
    final buckets = <int, List<NetworkMapStation>>{};
    final stationOrder = <String, int>{};
    for (var index = 0; index < stations.length; index += 1) {
      final station = stations[index];
      stationOrder[stationKeyFor(station)] = index;
      final bounds = sourceBoundsForStation(station);
      final left = _cellFor(bounds.left);
      final right = _cellFor(bounds.right);
      final top = _cellFor(bounds.top);
      final bottom = _cellFor(bounds.bottom);
      for (var x = left; x <= right; x += 1) {
        for (var y = top; y <= bottom; y += 1) {
          final key = packRouteMapGridKey(x, y);
          (buckets[key] ??= <NetworkMapStation>[]).add(station);
        }
      }
    }
    return NetworkMapStationSpatialIndex._(
      buckets: buckets,
      stationOrder: stationOrder,
      stationKeyFor: stationKeyFor,
    );
  }

  List<NetworkMapStation> query(Rect sourceBounds) {
    if (_buckets.isEmpty || sourceBounds.isEmpty) {
      return const [];
    }
    final stationKeyFor = _stationKeyFor!;
    final byKey = <String, NetworkMapStation>{};
    final left = _cellFor(sourceBounds.left);
    final right = _cellFor(sourceBounds.right);
    final top = _cellFor(sourceBounds.top);
    final bottom = _cellFor(sourceBounds.bottom);
    for (var x = left; x <= right; x += 1) {
      for (var y = top; y <= bottom; y += 1) {
        final bucket = _buckets[packRouteMapGridKey(x, y)];
        if (bucket == null) {
          continue;
        }
        for (final station in bucket) {
          byKey[stationKeyFor(station)] = station;
        }
      }
    }
    final result = byKey.values.toList(growable: false);
    result.sort((a, b) {
      final aOrder = _stationOrder[stationKeyFor(a)] ?? 0;
      final bOrder = _stationOrder[stationKeyFor(b)] ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return result;
  }

  static int _cellFor(double value) => (value / _cellSize).floor();
}
