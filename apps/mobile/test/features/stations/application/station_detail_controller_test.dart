import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StationDetailController는 실시간 폴링 틱으로 도착 정보를 주기적으로 갱신한다', () async {
    final searchRepo = _FakeSearchRepo();
    final realtimeRepo = _CountingRealtimeRepo();
    final controller = StationDetailController(
      repository: searchRepo,
      realtimeRepository: realtimeRepo,
      realtimePollingInterval: const Duration(milliseconds: 10),
    );

    expect(controller.isRealtimePolling, isFalse);

    await controller.load('station-sangnoksu');
    expect(controller.state.status, StationDetailStatus.success);
    expect(controller.isRealtimePolling, isTrue);

    // 10ms 폴링 대기
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(realtimeRepo.callCount, greaterThanOrEqualTo(2));
    expect(
      controller.state.realtimeSnapshot.status,
      RealtimeSnapshotStatus.stale,
    );

    controller.stopRealtimePolling();
    expect(controller.isRealtimePolling, isFalse);
    controller.dispose();
  });
}

class _FakeSearchRepo implements StationSearchRepository {
  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    return const StationDetail(
      id: 'station-sangnoksu',
      nameKo: '상록수',
      nameEn: 'Sangnoksu',
      region: '수도권',
      dataQualityLevel: 'LEVEL_1',
      lastVerifiedAt: '2026-09-27',
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
  Future<List<StationExitInfo>> listStationExits(String stationId) async => [];

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async => [];

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

class _CountingRealtimeRepo implements RealtimeRepository {
  int callCount = 0;

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    callCount++;
    return RealtimeSnapshot(
      status: callCount >= 2
          ? RealtimeSnapshotStatus.stale
          : RealtimeSnapshotStatus.fresh,
      receivedAt: '12:00:00',
      arrivals: [
        RealtimeArrival(
          lineId: query.lineId,
          stationName: query.stationQueryName,
          destination: '오이도',
          direction: '하행',
          trainNo: '4501',
          message: '곧 도착',
          etaSeconds: 60,
        ),
      ],
    );
  }
}
