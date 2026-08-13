import 'dart:io';

import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_panel_state.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nearby panel state는 idle loading success를 closed state로 보존한다', () {
    const idle = NetworkMapNearbyPanelData.idle();
    const loading = NetworkMapNearbyPanelData.loading();
    final results = <StationSearchResult>[];
    final success = NetworkMapNearbyPanelData.success(results);

    expect(idle.status, NetworkMapNearbyPanelStatus.idle);
    expect(idle.results, isEmpty);
    expect(loading.status, NetworkMapNearbyPanelStatus.loading);
    expect(loading.results, isEmpty);
    expect(success.status, NetworkMapNearbyPanelStatus.success);
    expect(identical(success.results, results), isTrue);
    expect(NetworkMapNearbyPanelDataSource.values, [
      NetworkMapNearbyPanelDataSource.realtime,
      NetworkMapNearbyPanelDataSource.timetable,
    ]);
  });

  test('network map root는 nearby panel state를 다시 선언하지 않는다', () {
    final root = File('lib/network_map.dart').readAsStringSync();

    expect(root, contains('NetworkMapNearbyPanelData'));
    expect(root, contains('NetworkMapNearbyPanelDataSource'));
    expect(root, isNot(contains('_NetworkMapNearbyPanelStatus')));
    expect(root, isNot(contains('_NearbyPanelDataSource')));
    expect(root, isNot(contains('class _NetworkMapNearbyPanelData')));
  });
}
