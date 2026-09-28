import 'package:easysubway_mobile/features/realtime/realtime_controller.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime controller는 repository 실패를 unavailable 상태로 낮춘다', () async {
    final controller = RealtimeStationController(
      repository: const ThrowingRealtimeRepository(),
    );

    await controller.load(
      const RealtimeStationQuery(
        stationId: 'station-sangnoksu',
        lineId: '4',
        stationQueryName: '상록수',
      ),
    );

    expect(controller.state.status, RealtimeSnapshotStatus.unavailable);
    expect(controller.state.message, contains('역 정보와 경로 검색은 계속 이용'));
    controller.dispose();
  });

  test('startPolling은 15초 주기 타이머로 도착 정보를 반복 갱신하고 stopPolling으로 중단한다', () {
    final countingRepo = CountingRealtimeRepository();
    final controller = RealtimeStationController(
      repository: countingRepo,
      defaultPollingInterval: const Duration(seconds: 15),
    );

    const query = RealtimeStationQuery(
      stationId: 'station-gangnam',
      lineId: '2',
      stationQueryName: '강남',
    );

    expect(controller.isPolling, isFalse);

    controller.startPolling(query, interval: const Duration(seconds: 15));
    expect(controller.isPolling, isTrue);

    // loadImmediately 로 첫 호출 수행됨
    expect(countingRepo.callCount, 1);

    controller.stopPolling();
    expect(controller.isPolling, isFalse);
    controller.dispose();
  });

  test('dispose 시 실행 중인 폴링 타이머가 안전하게 해제된다', () {
    final countingRepo = CountingRealtimeRepository();
    final controller = RealtimeStationController(repository: countingRepo);

    controller.startPolling(
      const RealtimeStationQuery(
        stationId: 'station-gangnam',
        lineId: '2',
        stationQueryName: '강남',
      ),
    );
    expect(controller.isPolling, isTrue);

    controller.dispose();
    expect(controller.isPolling, isFalse);
  });

  test('startPolling 타이머 틱은 비동기로 _pollTick을 실행하고 스냅샷을 갱신한다', () async {
    final countingRepo = CountingRealtimeRepository();
    final controller = RealtimeStationController(
      repository: countingRepo,
      defaultPollingInterval: const Duration(milliseconds: 10),
    );

    const query = RealtimeStationQuery(
      stationId: 'station-gangnam',
      lineId: '2',
      stationQueryName: '강남',
    );

    controller.startPolling(
      query,
      interval: const Duration(milliseconds: 10),
      loadImmediately: false,
    );
    expect(controller.isPolling, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(countingRepo.callCount, greaterThanOrEqualTo(1));
    expect(controller.state.status, RealtimeSnapshotStatus.fresh);

    controller.stopPolling();
    controller.dispose();
  });
}

class ThrowingRealtimeRepository implements RealtimeRepository {
  const ThrowingRealtimeRepository();

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    throw const RealtimeException('network failed');
  }
}

class CountingRealtimeRepository implements RealtimeRepository {
  int callCount = 0;

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    callCount++;
    return RealtimeSnapshot(
      status: RealtimeSnapshotStatus.fresh,
      receivedAt: '12:00:00',
      arrivals: [
        RealtimeArrival(
          lineId: query.lineId,
          stationName: query.stationQueryName,
          destination: '성수',
          direction: '내선',
          trainNo: '2026',
          message: '전역 출발',
          etaSeconds: 120,
        ),
      ],
    );
  }
}
