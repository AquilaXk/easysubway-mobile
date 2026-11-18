import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/flatbush_spatial_index.dart';
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
      sourceBoundsForStation: (station) =>
          Rect.fromLTWH(station.position.x.toDouble(), 0, 48, 48),
      stationKeyFor: (station) => station.id,
    );

    final result = index.query(const Rect.fromLTWH(0, 0, 100, 100));
    expect(result, hasLength(1));
    expect(result.single, same(last));
    expect(index.query(const Rect.fromLTWH(1000, 1000, 10, 10)), isEmpty);
    expect(NetworkMapStationSpatialIndex.empty.query(Rect.zero), isEmpty);
  });

  test('64비트 워드 경계(인덱스 63, 127 포함 150개 역)에서도 손실·오프바이원 없이 입력 순서를 보존한다', () {
    final stations = List<NetworkMapStation>.generate(
      150,
      (i) => _station('st_$i', (149 - i) * 20),
    );
    final index = NetworkMapStationSpatialIndex.fromStations(
      stations,
      sourceBoundsForStation: (station) =>
          Rect.fromLTWH(station.position.x.toDouble(), 0, 16, 16),
      stationKeyFor: (station) => station.id,
    );

    final allHits = index.query(const Rect.fromLTWH(0, 0, 4000, 50));
    expect(allHits, hasLength(150));
    for (var i = 0; i < 150; i++) {
      expect(allHits[i], same(stations[i]));
    }

    // 인덱스 63(x = 86 * 20 = 1720)과 인덱스 127(x = 22 * 20 = 440) 단독 조회 검증
    final hit63 = index.query(const Rect.fromLTWH(1720, 0, 10, 10));
    expect(hit63.single, same(stations[63]));
    final hit127 = index.query(const Rect.fromLTWH(440, 0, 10, 10));
    expect(hit127.single, same(stations[127]));
  });

  test(
    'FlatbushSpatialIndex 상태 가드(isBuilt, add 초과, 미완성 finish)와 다층 레벨 탐색을 검증한다',
    () {
      final tree = FlatbushSpatialIndex(2);
      expect(tree.isBuilt, isFalse);

      final preFinishHits = <int>[];
      tree.search(0, 0, 100, 100, preFinishHits.add);
      expect(preFinishHits, isEmpty);

      tree.add(0, 0, 10, 10);
      expect(tree.finish, throwsStateError);

      tree.add(double.nan, double.infinity, 30, 30);
      expect(() => tree.add(40, 40, 50, 50), throwsStateError);

      tree.finish();
      expect(tree.isBuilt, isTrue);
      tree.finish(); // 중복 호출 멱등성

      final hits = <int>[];
      tree.search(0, 0, 35, 35, hits.add);
      expect(hits, unorderedEquals(<int>[0, 1]));

      // 3단계 이상 다층 레벨(nodeSize=2, 9개 항목 -> levelBounds [9, 14, 17, 19, 20]) 탐색 검증
      final deepTree = FlatbushSpatialIndex(9, nodeSize: 2);
      for (var i = 0; i < 9; i++) {
        final x = (i * 10).toDouble();
        deepTree.add(x, x, x + 5, x + 5);
      }
      deepTree.finish();
      final deepHits = <int>[];
      deepTree.search(0, 0, 100, 100, deepHits.add);
      expect(deepHits, unorderedEquals(List<int>.generate(9, (i) => i)));
    },
  );

  test('canvas는 geometry owner를 조립하고 root private spatial-index를 두지 않는다', () {
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    final canvas = File(
      'lib/features/network_map/presentation/network_map_canvas.dart',
    ).readAsStringSync();
    final geometry = File(
      'lib/features/network_map/presentation/network_map_geometry.dart',
    ).readAsStringSync();

    expect(
      root,
      contains(
        "import '../features/network_map/presentation/network_map_canvas.dart';",
      ),
    );
    expect(
      canvas,
      isNot(
        contains(
          "import 'features/network_map/domain/network_map_station_spatial_index.dart';",
        ),
      ),
    );
    expect(canvas, contains("import 'network_map_geometry.dart';"));
    expect(canvas, contains('NetworkMapGeometry.fromStations('));
    expect(
      geometry,
      contains("import '../domain/network_map_station_spatial_index.dart';"),
    );
    expect(geometry, contains('NetworkMapStationSpatialIndex.fromStations('));
    expect(root, isNot(contains('class _StationSpatialIndex')));
    expect(root, isNot(contains('class _StationSpatialCell')));
  });
}
