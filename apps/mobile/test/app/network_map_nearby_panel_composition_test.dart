import 'dart:io';

import 'package:easysubway_mobile/app/network_map_nearby_panel_composition.dart';
import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_panel_state.dart';
import 'package:easysubway_mobile/features/network_map/domain/nearby_adjacent_stations.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_arrival_panel.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_timetable_panel.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/service_pattern_badge.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalogLine = StationSearchLine(
  id: 'line-1',
  name: '수도권 1호선',
  color: '#0052A4',
  stationCode: '101',
);

const _fallbackLine = StationSearchLine(
  id: 'line-2',
  name: '수도권 2호선',
  color: '',
  stationCode: '201',
);

StationSearchResult _station(List<StationSearchLine> lines) {
  return StationSearchResult(
    id: 'station-center',
    nameKo: '가운데',
    nameEn: 'Center',
    region: '수도권',
    dataQualityLevel: 'VERIFIED',
    lastVerifiedAt: '2026-08-13T00:00:00Z',
    lines: lines,
  );
}

const _adjacentStations = NearbyAdjacentStations(
  leftName: '이전',
  rightName: '다음',
  leftStationId: 'station-left',
  rightStationId: 'station-right',
);

RealtimeSnapshot _realtime(RealtimeSnapshotStatus status) {
  return RealtimeSnapshot(
    status: status,
    receivedAt: '2026-08-13T00:01:00Z',
    arrivals: const [
      RealtimeArrival(
        lineId: 'line-1',
        stationName: '가운데',
        destination: '종점',
        direction: '상행',
        trainNo: 'T1',
        etaSeconds: 90,
        message: '곧 도착',
      ),
    ],
  );
}

const _timetable = StationTimetable(
  stationId: 'station-center',
  lineId: 'line-1',
  dayType: StationTimetableDayType.weekday,
  directions: [
    StationTimetableDirection(
      name: '상행',
      departures: [
        StationTimetableDeparture(
          directionName: '상행',
          seconds: 8 * 60 * 60,
          servicePattern: 'EXPRESS',
        ),
      ],
    ),
  ],
);

void main() {
  test('인접역 identity와 selected-line fallback을 그대로 변환한다', () {
    expect(networkMapStationDetailNeighbor(null), isNull);
    final neighbor = networkMapStationDetailNeighbor(
      _adjacentStations.previousNeighbor,
    );
    expect(neighbor?.stationId, 'station-left');
    expect(neighbor?.nameKo, '이전');

    expect(networkMapNearbySelectedLine(_station(const []), 'line-1'), isNull);
    expect(
      networkMapNearbySelectedLine(
        _station(const [_catalogLine, _fallbackLine]),
        'line-2',
      ),
      same(_fallbackLine),
    );
    expect(
      networkMapNearbySelectedLine(
        _station(const [_catalogLine, _fallbackLine]),
        'unknown',
      ),
      same(_catalogLine),
    );
  });

  test('realtime 조합은 line color·arrival·neighbor callback을 보존한다', () {
    for (final entry in const [
      (RealtimeSnapshotStatus.fresh, NearbyArrivalPanelStatus.fresh),
      (RealtimeSnapshotStatus.stale, NearbyArrivalPanelStatus.stale),
      (
        RealtimeSnapshotStatus.unavailable,
        NearbyArrivalPanelStatus.unavailable,
      ),
    ]) {
      final selectedNeighbors = <String>[];
      var detailTaps = 0;
      final content = buildNetworkMapNearbyPanelSuccessContent(
        results: [
          _station(const [_catalogLine]),
        ],
        realtime: _realtime(entry.$1),
        selectedLineId: 'line-1',
        dataSource: NetworkMapNearbyPanelDataSource.realtime,
        timetable: null,
        adjacentStations: _adjacentStations,
        onOpenStationDetail: () => detailTaps += 1,
        onSelectNeighbor: (neighbor) => selectedNeighbors.add(neighbor.nameKo),
      );

      final stationBar = content.stationBar as NearbyStationLineBar;
      final arrivalPanel = content.dataPanel as NearbyArrivalPanel;
      expect(stationBar.stationName, '가운데');
      expect(stationBar.badgeText, '1');
      expect(stationBar.lineColor, stationLineColor('#0052A4'));
      expect(arrivalPanel.data.status, entry.$2);
      expect(arrivalPanel.data.receivedAt, '2026-08-13T00:01:00Z');
      expect(arrivalPanel.data.arrivals.single.direction, '상행');
      expect(arrivalPanel.data.arrivals.single.destination, '종점');
      expect(arrivalPanel.data.arrivals.single.etaSeconds, 90);
      expect(arrivalPanel.data.arrivals.single.message, '곧 도착');

      stationBar.onStationNameTap?.call();
      stationBar.onLeftNameTap?.call();
      stationBar.onRightNameTap?.call();
      expect(detailTaps, 1);
      expect(selectedNeighbors, ['이전', '다음']);
    }
  });

  test('line과 callback 부재 및 timetable projection을 보존한다', () {
    final withoutLine = buildNetworkMapNearbyPanelSuccessContent(
      results: [_station(const [])],
      realtime: _realtime(RealtimeSnapshotStatus.loading),
      selectedLineId: null,
      dataSource: NetworkMapNearbyPanelDataSource.timetable,
      timetable: null,
      adjacentStations: const NearbyAdjacentStations(),
    );
    final fallbackBar = withoutLine.stationBar as NearbyStationLineBar;
    final emptyTimetable = withoutLine.dataPanel as NearbyTimetablePanel;
    expect(
      fallbackBar.lineColor,
      stationLineColor(stationLineFallbackBrandHex),
    );
    expect(fallbackBar.onLeftNameTap, isNull);
    expect(fallbackBar.onRightNameTap, isNull);
    expect(emptyTimetable.data, isNull);

    final withTimetable = buildNetworkMapNearbyPanelSuccessContent(
      results: [
        _station(const [_fallbackLine]),
      ],
      realtime: _realtime(RealtimeSnapshotStatus.loading),
      selectedLineId: 'line-2',
      dataSource: NetworkMapNearbyPanelDataSource.timetable,
      timetable: _timetable,
      adjacentStations: _adjacentStations,
    );
    final timetableBar = withTimetable.stationBar as NearbyStationLineBar;
    final timetablePanel = withTimetable.dataPanel as NearbyTimetablePanel;
    expect(
      timetableBar.lineColor,
      stationLineColor(
        fallbackLineColorHex(lineId: 'line-2', lineName: '수도권 2호선'),
      ),
    );
    final direction = timetablePanel.data!.directions.single;
    expect(direction.name, '상행');
    final departure = direction.departures.single;
    expect(departure.directionName, '상행');
    expect(departure.seconds, 8 * 60 * 60);
    expect(departure.timeLabel, '08:00');
    expect(departure.semanticLabel, '상행, 급행, 08시 00분 출발');
    expect(departure.isExpress, isTrue);
    expect(timetablePanel.expressBadgeBuilder(), isA<ServicePatternBadge>());
  });

  test('root는 app composition owner만 쓰고 private helper cluster가 없다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    expect(
      root,
      contains("import 'app/network_map_nearby_panel_composition.dart';"),
    );
    expect(root, contains('buildNetworkMapNearbyPanelSuccessContent('));
    for (final privateHelper in [
      '_stationDetailNeighbor(',
      '_nearbySelectedLineColor(',
      '_nearbySelectedLine(',
      '_networkMapNearbySuccessContent(',
      '_nearbyTimetablePanelData(',
    ]) {
      expect(root, isNot(contains(privateHelper)));
    }
  });
}
