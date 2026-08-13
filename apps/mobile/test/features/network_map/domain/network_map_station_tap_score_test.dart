import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/network_map_station_tap_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NetworkMapStationTapScore score({
    bool containsNode = false,
    bool containsShape = false,
    double screenDistance = 10,
    String stableKey = 'station-b',
  }) {
    return NetworkMapStationTapScore(
      containsNode: containsNode,
      containsShape: containsShape,
      screenDistance: screenDistance,
      stableKey: stableKey,
    );
  }

  test('station tap score orders node then shape then distance then key', () {
    expect(
      score(containsNode: true).compareTo(score(containsShape: true)),
      lessThan(0),
    );
    expect(score(containsShape: true).compareTo(score()), lessThan(0));
    expect(
      score(screenDistance: 4).compareTo(score(screenDistance: 8)),
      lessThan(0),
    );
    expect(
      score(stableKey: 'station-a').compareTo(score(stableKey: 'station-b')),
      lessThan(0),
    );
  });

  test(
    'network map hit-testing owner consumes the public station tap score',
    () {
      final root = File('lib/network_map.dart').readAsStringSync();
      final canvas = File(
        'lib/features/network_map/presentation/network_map_canvas.dart',
      ).readAsStringSync();
      final hitTestingOwner = File(
        'lib/features/network_map/presentation/station_hit_target.dart',
      ).readAsStringSync();

      expect(root, contains('NetworkMapCanvas('));
      expect(canvas, contains('NetworkMapStationHitGeometry'));
      expect(canvas, isNot(contains('NetworkMapStationTapScore')));
      expect(hitTestingOwner, contains('NetworkMapStationTapScore'));
      expect(root, isNot(contains('class _StationTapScore')));
    },
  );
}
