import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StationDetailScreen은 앱 라이프사이클 변화 시 실시간 폴링을 중단 및 재개한다', (
    tester,
  ) async {
    final searchRepo = _FakeStationSearchRepository();
    const reportRepo = UnavailableFacilityReportRepository();
    final realtimeRepo = _FakeRealtimeRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationDetailScreen(
            repository: searchRepo,
            reportRepository: reportRepo,
            realtimeRepository: realtimeRepo,
            stationId: 'station-sangnoksu',
          ),
        ),
      ),
    );

    // Initial load
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stationDetailAppBar')), findsOneWidget);
    expect(find.text('상록수역'), findsOneWidget);

    // Lifecycle paused -> stop polling
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // Lifecycle inactive -> stop polling
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    // Lifecycle hidden -> stop polling
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    // Lifecycle resumed -> resume polling
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}

class _FakeStationSearchRepository implements StationSearchRepository {
  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    return const StationDetail(
      id: 'station-sangnoksu',
      nameKo: '상록수',
      nameEn: 'Sangnoksu',
      region: '수도권',
      dataQualityLevel: 'LEVEL_1',
      lastVerifiedAt: '2026-09-27',
      latitude: 37.302,
      longitude: 126.865,
      lines: [
        StationSearchLine(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A5DE',
          stationCode: '450',
        ),
      ],
    );
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    return const [
      StationExitInfo(
        id: 'exit-1',
        stationId: 'station-sangnoksu',
        exitNumber: '1',
        name: '1번 출구',
        description: '상록수역 광장',
        hasElevatorConnection: true,
        hasStairOnlyPath: StairOnlyPathStatus.unknown,
        dataConfidence: 'HIGH',
        lastVerifiedAt: '2026-09-27',
      ),
    ];
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    return const [];
  }

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async => [];

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async => [];
}

class _FakeRealtimeRepository implements RealtimeRepository {
  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    return const RealtimeSnapshot(
      status: RealtimeSnapshotStatus.fresh,
      receivedAt: '12:00:00',
      arrivals: [],
    );
  }
}
