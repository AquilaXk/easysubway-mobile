import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_geometry.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_hit_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _station = NetworkMapStation(
  id: 'station-city-hall',
  nameKo: '시청',
  nameEn: 'City Hall',
  region: '수도권',
  lineId: '1',
  stationCode: '132',
  sequence: 1,
  position: NetworkMapPosition(
    x: 0,
    y: 0,
    labelDx: 0,
    labelDy: 0,
    upPath: '',
    downPath: '',
    sourceId: 'test',
  ),
);

NetworkMapStation _positionedStation(
  String id,
  int x,
  int y, {
  String lineId = '1',
  String labelPolygon = '',
  String upPath = '',
  String downPath = '',
}) {
  return NetworkMapStation(
    id: id,
    nameKo: id,
    nameEn: id,
    region: '수도권',
    lineId: lineId,
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

NetworkMapStationHitGeometry _hitGeometry(List<NetworkMapStation> stations) {
  late NetworkMapStationHitGeometry hitGeometry;
  final geometry = NetworkMapGeometry.fromStations(
    stations,
    stationSourceBoundsFor: NetworkMapStationHitGeometry.sourceBoundsForStation,
    stationKeyFor: NetworkMapStationHitGeometry.stationKeyFor,
  );
  hitGeometry = NetworkMapStationHitGeometry(geometry: geometry);
  return hitGeometry;
}

void main() {
  testWidgets('station hit target은 exact button semantics와 tap action을 보존한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 48,
          height: 48,
          child: NetworkMapStationHitTarget(
            station: _station,
            onTap: () => tapCount += 1,
          ),
        ),
      ),
    );

    final target = find.byType(NetworkMapStationHitTarget);
    expect(
      tester.getSemantics(target),
      matchesSemantics(label: '시청역', isButton: true, hasTapAction: true),
    );
    expect(
      find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == double.infinity &&
              widget.height == double.infinity,
        ),
      ),
      findsOneWidget,
    );

    tester.semantics.tap(find.semantics.byLabel('시청역'));
    await tester.pump();
    expect(tapCount, 1);
    semantics.dispose();
  });

  test('canvas와 existing helper는 public hit owner만 직접 참조한다', () {
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    final canvas = File(
      'lib/features/network_map/presentation/network_map_canvas.dart',
    ).readAsStringSync();
    final existingTest = File('test/widget_test.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_canvas.dart';",
      ),
    );
    expect(canvas, contains("import 'station_hit_target.dart';"));
    expect(canvas, contains('NetworkMapStationHitTarget('));
    expect(root, isNot(contains('class _StationHitTarget')));
    expect(canvas, contains('NetworkMapStationHitGeometry('));
    expect(root, isNot(contains('Rect _stationHitRect(')));
    expect(root, isNot(contains('_stationAtViewportPosition(')));
    expect(root, isNot(contains('_visibleCanonicalStations(')));
    expect(existingTest, contains('NetworkMapStationHitTarget의'));
    expect(existingTest, isNot(contains('_StationHitTarget의')));
  });

  test('public hit geometry는 48dp node·label polygon source bounds를 보존한다', () {
    final station = _positionedStation(
      'station-a',
      100,
      200,
      labelPolygon: '[{"x":80,"y":180},{"x":160,"y":180},{"x":160,"y":240}]',
    );
    final hitGeometry = _hitGeometry([station]);

    expect(networkMapStationHitTargetLogicalSize, 48);
    expect(
      hitGeometry.sourceBoundsFor(station),
      const Rect.fromLTRB(50, 50, 134, 114),
    );
  });

  test(
    'visible canonical query는 겹친 ID의 higher-priority polygon station을 고른다',
    () {
      final plain = _positionedStation('station-a', 100, 100);
      final polygon = _positionedStation(
        'station-a',
        100,
        100,
        lineId: '2',
        labelPolygon: '[{"x":90,"y":90},{"x":140,"y":90},{"x":140,"y":130}]',
      );
      final hitGeometry = _hitGeometry([plain, polygon]);
      const camera = MapCameraState(
        sourceBounds: Rect.fromLTWH(0, 0, 860, 560),
        viewportSize: Size(860, 560),
        center: Offset(430, 280),
        scale: 1,
        minScale: 1,
        maxScale: 4,
        revision: 0,
      );

      expect(hitGeometry.visibleCanonicalStations(camera: camera), [polygon]);
    },
  );

  test('viewport tap은 node hit를 label-only 후보보다 우선한다', () {
    final node = _positionedStation('node', 100, 100);
    final label = _positionedStation('label', 125, 100);
    final hitGeometry = _hitGeometry([label, node]);
    const camera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 860, 560),
      viewportSize: Size(860, 560),
      center: Offset(430, 280),
      scale: 1,
      minScale: 1,
      maxScale: 4,
      revision: 0,
    );

    expect(
      hitGeometry.stationAtViewportPosition(
        camera.sourceToViewportPoint(
          Offset(hitGeometry.geometry.x(node), hitGeometry.geometry.y(node)),
        ),
        camera: camera,
      ),
      same(node),
    );
  });

  test('public hit geometry는 label·polygon·vertical path edge를 보존한다', () {
    const camera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 860, 560),
      viewportSize: Size(860, 560),
      center: Offset(430, 280),
      scale: 1,
      minScale: 1,
      maxScale: 4,
      revision: 0,
    );
    final labelStation = _positionedStation('label', 100, 100);
    final labelHitGeometry = _hitGeometry([labelStation]);
    final labelNodeCenter = camera.sourceToViewportPoint(
      Offset(
        labelHitGeometry.geometry.x(labelStation),
        labelHitGeometry.geometry.y(labelStation),
      ),
    );

    expect(
      labelHitGeometry.stationAtViewportPosition(
        labelNodeCenter + const Offset(0, -17.5),
        camera: camera,
      ),
      same(labelStation),
    );
    expect(
      labelHitGeometry.stationAtViewportPosition(
        labelNodeCenter + const Offset(0, 23.5),
        camera: camera,
      ),
      same(labelStation),
    );

    final duplicatePolygonStation = _positionedStation(
      'polygon',
      100,
      100,
      labelPolygon:
          '[{"x":100,"y":100},{"x":100,"y":100},{"x":110,"y":100},'
          '{"x":110,"y":110},{"x":100,"y":110}]',
    );
    final polygonHitGeometry = _hitGeometry([duplicatePolygonStation]);
    final polygonNodeCenter = camera.sourceToViewportPoint(
      Offset(
        polygonHitGeometry.geometry.x(duplicatePolygonStation),
        polygonHitGeometry.geometry.y(duplicatePolygonStation),
      ),
    );
    expect(
      polygonHitGeometry.stationAtViewportPosition(
        polygonNodeCenter + const Offset(-10, 0),
        camera: camera,
      ),
      same(duplicatePolygonStation),
    );

    final verticalPathStation = _positionedStation(
      'v',
      100,
      100,
      downPath: 'M 0 0 L 0 40',
    );
    final verticalHitGeometry = _hitGeometry([verticalPathStation]);
    final verticalNodeCenter = Offset(
      verticalHitGeometry.geometry.x(verticalPathStation),
      verticalHitGeometry.geometry.y(verticalPathStation),
    );
    final expectedVerticalBounds =
        Rect.fromCenter(
          center: verticalNodeCenter,
          width: 48,
          height: 48,
        ).expandToInclude(
          Rect.fromCenter(
            center: verticalNodeCenter + const Offset(9, 3),
            width: 64,
            height: 40,
          ),
        );
    expect(
      verticalHitGeometry.sourceBoundsFor(verticalPathStation),
      expectedVerticalBounds,
    );
  });
}
