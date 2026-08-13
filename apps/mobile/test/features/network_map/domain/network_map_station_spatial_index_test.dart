import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_spatial_index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkMapStation _station(String id, int x) {
  return NetworkMapStation(
    id: id,
    nameKo: id,
    nameEn: id,
    region: '수도권',
    lineId: '1',
    stationCode: id,
    sequence: x,
    position: NetworkMapPosition(
      x: x,
      y: 0,
      labelDx: 0,
      labelDy: 0,
      upPath: '',
      downPath: '',
      sourceId: 'test',
    ),
  );
}

void main() {
  test('여러 cell의 역을 중복 없이 원래 입력 순서로 반환한다', () {
    final right = _station('right', 520);
    final left = _station('left', 20);
    final middle = _station('middle', 270);
    final stations = [right, left, middle];
    final bounds = <String, Rect>{
      'right': const Rect.fromLTWH(500, 0, 48, 48),
      'left': const Rect.fromLTWH(0, 0, 48, 48),
      // 256px cell 경계를 걸쳐 같은 역이 두 bucket에서 발견된다.
      'middle': const Rect.fromLTWH(250, 0, 48, 48),
    };

    final index = NetworkMapStationSpatialIndex.fromStations(
      stations,
      sourceBoundsForStation: (station) => bounds[station.id]!,
      stationKeyFor: (station) => station.id,
    );

    final result = index.query(const Rect.fromLTWH(0, 0, 600, 80));
    expect(result, hasLength(stations.length));
    for (var index = 0; index < stations.length; index += 1) {
      expect(result[index], same(stations[index]));
    }
  });

  test('같은 geometry key는 마지막 역으로 deduplicate하고 빈 query는 닫힌다', () {
    final first = _station('same', 10);
    final last = _station('same', 20);
    final index = NetworkMapStationSpatialIndex.fromStations(
      [first, last],
      sourceBoundsForStation: (station) => Rect.fromLTWH(
        station.position.x.toDouble(),
        0,
        48,
        48,
      ),
      stationKeyFor: (station) => station.id,
    );

    final result = index.query(const Rect.fromLTWH(0, 0, 100, 100));
    expect(result, hasLength(1));
    expect(result.single, same(last));
    expect(index.query(const Rect.fromLTWH(1000, 1000, 10, 10)), isEmpty);
    expect(NetworkMapStationSpatialIndex.empty.query(Rect.zero), isEmpty);
  });

  test('root는 public spatial-index owner를 사용하고 private 사본을 제거한다', () {
    final root = File('lib/network_map.dart').readAsStringSync();

    expect(
      root,
      contains(
        "import 'features/network_map/domain/network_map_station_spatial_index.dart';",
      ),
    );
    expect(root, contains('NetworkMapStationSpatialIndex.fromStations('));
    expect(root, isNot(contains('class _StationSpatialIndex')));
    expect(root, isNot(contains('class _StationSpatialCell')));
  });
}
