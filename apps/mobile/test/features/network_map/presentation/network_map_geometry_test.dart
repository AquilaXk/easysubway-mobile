import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkMapStation _station(
  String id,
  int x,
  int y, {
  String upPath = '',
  String downPath = '',
  String labelPolygon = '',
}) {
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
      y: y,
      labelDx: 0,
      labelDy: 0,
      upPath: upPath,
      downPath: downPath,
      sourceId: 'test',
      labelPolygon: labelPolygon,
    ),
  );
}

NetworkMapGeometry _geometry(
  List<NetworkMapStation> stations, {
  List<Rect> ownerLabelSourceRects = const [],
}) {
  return NetworkMapGeometry.fromStations(
    stations,
    ownerLabelSourceRects: ownerLabelSourceRects,
    stationSourceBoundsFor: (station, geometry) => Rect.fromCenter(
      center: Offset(geometry.x(station), geometry.y(station)),
      width: 48,
      height: 48,
    ),
    stationKeyFor: (station) => '${station.id}:${station.lineId}',
  );
}

void main() {
  test('빈 geometry는 기존 default bounds와 empty index를 보존한다', () {
    final geometry = _geometry(const []);

    expect(geometry.origin, Offset.zero);
    expect(geometry.focus, const Offset(430, 280));
    expect(geometry.width, 860);
    expect(geometry.height, 560);
    expect(geometry.initialBounds, const Rect.fromLTWH(0, 0, 860, 560));
    expect(geometry.stationIndex.query(Rect.zero), isEmpty);
    expect(geometry.copyWith().stationIndex, same(geometry.stationIndex));
  });

  test('owner label만 있는 geometry도 empty median fallback을 보존한다', () {
    final geometry = _geometry(
      const [],
      ownerLabelSourceRects: const [Rect.fromLTRB(100, 200, 300, 400)],
    );

    expect(geometry.origin, const Offset(46, 146));
    expect(geometry.focus, const Offset(-46, -146));
    expect(geometry.width, 860);
    expect(geometry.height, 560);
    expect(geometry.stationIndex.query(Rect.zero), isEmpty);
  });

  test('station path·label polygon·owner label extents와 index를 결속한다', () {
    final station = _station(
      'station-a',
      100,
      200,
      upPath: 'M 10 20 L 300 420',
      labelPolygon: '[{"x":5,"y":10},{"x":80,"y":10},{"x":80,"y":90}]',
    );
    final geometry = _geometry(
      [station],
      ownerLabelSourceRects: const [Rect.fromLTRB(-200, -100, 1000, 900)],
    );

    expect(geometry.origin, const Offset(-254, -154));
    expect(geometry.focus, const Offset(354, 354));
    expect(geometry.width, 1308);
    expect(geometry.height, 1108);
    expect(geometry.initialBounds, const Rect.fromLTWH(0, 0, 1308, 1108));
    expect(geometry.stationIndex.query(const Rect.fromLTWH(0, 0, 1308, 1108)), [
      same(station),
    ]);
  });

  test('large region은 38% readable bounds를 적용한다', () {
    final stations = [
      for (var index = 0; index < 41; index += 1)
        _station('station-$index', index * 10, index * 5),
    ];

    final geometry = _geometry(stations);

    expect(geometry.width, 860);
    expect(geometry.height, 560);
    expect(geometry.initialBounds.width, closeTo(326.8, 0.001));
    expect(geometry.initialBounds.height, 320);
    expect(geometry.initialBounds, isNot(const Rect.fromLTWH(0, 0, 860, 560)));
  });

  test('polygon bounds와 root public owner 결속을 단일 source로 유지한다', () {
    expect(NetworkMapCanvas, isNotNull);
    expect(
      networkMapPolygonBounds(const [
        Offset(10, 20),
        Offset(40, 5),
        Offset(25, 60),
      ]),
      const Rect.fromLTRB(10, 5, 40, 60),
    );

    final root = File('lib/network_map.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_geometry.dart';",
      ),
    );
    expect(root, contains('NetworkMapGeometry.fromStations('));
    expect(root, isNot(contains('class _MapGeometry')));
    expect(root, isNot(contains('Rect _boundsForPolygon(')));
  });
}
