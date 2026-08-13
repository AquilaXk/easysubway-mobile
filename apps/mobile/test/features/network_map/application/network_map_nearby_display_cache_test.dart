import 'dart:io';

import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_display_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nearby realtime display cache preserves key and payload identity', () {
    final snapshot = Object();
    final display = NetworkMapNearbyRealtimeDisplay<Object>(
      stationId: 'station-a',
      lineId: 'line-1',
      snapshot: snapshot,
    );

    expect(display.stationId, 'station-a');
    expect(display.lineId, 'line-1');
    expect(identical(display.snapshot, snapshot), isTrue);
  });

  test('nearby timetable display cache preserves key and payload identity', () {
    final timetable = Object();
    final display = NetworkMapNearbyTimetableDisplay<Object>(
      stationId: 'station-b',
      lineId: 'line-2',
      timetable: timetable,
    );

    expect(display.stationId, 'station-b');
    expect(display.lineId, 'line-2');
    expect(identical(display.timetable, timetable), isTrue);
  });

  test('network map root no longer declares private nearby display caches', () {
    final root = File('lib/network_map.dart').readAsStringSync();

    expect(root, contains('NetworkMapNearbyRealtimeDisplay'));
    expect(root, contains('NetworkMapNearbyTimetableDisplay'));
    expect(root, isNot(contains('class _NearbyRealtimeDisplay')));
    expect(root, isNot(contains('class _NearbyTimetableDisplay')));
  });
}
