import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'flatbush_spatial_index.dart';
import 'network_map_models.dart';

/// 2D 정수 격자 좌표 `(gx, gy)`를 64비트 정수로 패킹한다.
int packRouteMapGridKey(int gx, int gy) => (gx << 32) | (gy & 0xFFFFFFFF);

class NetworkMapStationSpatialIndex {
  NetworkMapStationSpatialIndex._({
    required this.stations,
    required this.flatbush,
    required this._scratchBitset,
  });

  static final empty = NetworkMapStationSpatialIndex._(
    stations: const [],
    flatbush: FlatbushSpatialIndex.empty,
    scratchBitset: Uint64List(0),
  );

  final List<NetworkMapStation> stations;
  final FlatbushSpatialIndex flatbush;
  final Uint64List _scratchBitset;

  factory NetworkMapStationSpatialIndex.fromStations(
    List<NetworkMapStation> stations, {
    required Rect Function(NetworkMapStation station) sourceBoundsForStation,
    required String Function(NetworkMapStation station) stationKeyFor,
  }) {
    if (stations.isEmpty) {
      return empty;
    }

    final uniqueStations = <NetworkMapStation>[];
    final keyToIndex = <String, int>{};
    for (var index = 0; index < stations.length; index += 1) {
      final station = stations[index];
      final key = stationKeyFor(station);
      final existing = keyToIndex[key];
      if (existing != null) {
        uniqueStations[existing] = station;
      } else {
        keyToIndex[key] = uniqueStations.length;
        uniqueStations.add(station);
      }
    }

    final flatbush = FlatbushSpatialIndex(uniqueStations.length);
    for (var index = 0; index < uniqueStations.length; index += 1) {
      final bounds = sourceBoundsForStation(uniqueStations[index]);
      flatbush.add(bounds.left, bounds.top, bounds.right, bounds.bottom);
    }
    flatbush.finish();

    return NetworkMapStationSpatialIndex._(
      stations: List.unmodifiable(uniqueStations),
      flatbush: flatbush,
      scratchBitset: Uint64List((uniqueStations.length + 63) >> 6),
    );
  }

  List<NetworkMapStation> query(Rect sourceBounds) {
    if (stations.isEmpty || sourceBounds.isEmpty) {
      return const [];
    }

    final bitset = _scratchBitset;
    bitset.fillRange(0, bitset.length, 0);
    flatbush.searchWithBitset(
      sourceBounds.left,
      sourceBounds.top,
      sourceBounds.right,
      sourceBounds.bottom,
      bitset,
    );

    final result = <NetworkMapStation>[];
    FlatbushSpatialIndex.scanBits(bitset, (index) {
      result.add(stations[index]);
    });
    return result;
  }
}
