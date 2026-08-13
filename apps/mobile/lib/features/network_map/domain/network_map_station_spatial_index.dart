import 'package:flutter/widgets.dart';

import 'network_map_models.dart';

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

  final Map<_NetworkMapStationSpatialCell, List<NetworkMapStation>> _buckets;
  final Map<String, int> _stationOrder;
  final String Function(NetworkMapStation station)? _stationKeyFor;

  factory NetworkMapStationSpatialIndex.fromStations(
    List<NetworkMapStation> stations, {
    required Rect Function(NetworkMapStation station) sourceBoundsForStation,
    required String Function(NetworkMapStation station) stationKeyFor,
  }) {
    final buckets = <_NetworkMapStationSpatialCell, List<NetworkMapStation>>{};
    final stationOrder = <String, int>{};
    for (var index = 0; index < stations.length; index += 1) {
      final station = stations[index];
      stationOrder[stationKeyFor(station)] = index;
      for (final cell in _cellsFor(sourceBoundsForStation(station))) {
        buckets.putIfAbsent(cell, () => []).add(station);
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
    for (final cell in _cellsFor(sourceBounds)) {
      for (final station in _buckets[cell] ?? const <NetworkMapStation>[]) {
        byKey[stationKeyFor(station)] = station;
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

  static Iterable<_NetworkMapStationSpatialCell> _cellsFor(Rect bounds) sync* {
    final left = _cellFor(bounds.left);
    final right = _cellFor(bounds.right);
    final top = _cellFor(bounds.top);
    final bottom = _cellFor(bounds.bottom);
    for (var x = left; x <= right; x += 1) {
      for (var y = top; y <= bottom; y += 1) {
        yield _NetworkMapStationSpatialCell(x, y);
      }
    }
  }

  static int _cellFor(double value) => (value / _cellSize).floor();
}

@immutable
class _NetworkMapStationSpatialCell {
  const _NetworkMapStationSpatialCell(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) {
    return other is _NetworkMapStationSpatialCell &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}
