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

  test('network map root no longer declares its private station tap score', () {
    final root = File('lib/network_map.dart').readAsStringSync();

    expect(root, contains('NetworkMapStationTapScore'));
    expect(root, isNot(contains('class _StationTapScore')));
  });
}
