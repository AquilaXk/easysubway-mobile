import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
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

  test('root와 existing helper는 public owner만 직접 참조한다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    final existingTest = File('test/widget_test.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/station_hit_target.dart';",
      ),
    );
    expect(root, contains('NetworkMapStationHitTarget('));
    expect(root, isNot(contains('class _StationHitTarget')));
    expect(existingTest, contains('NetworkMapStationHitTarget의'));
    expect(existingTest, isNot(contains('_StationHitTarget의')));
  });
}
