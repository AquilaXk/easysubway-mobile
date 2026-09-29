import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_realtime_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, RealtimeSnapshot snapshot) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRealtimeSummary(snapshot: snapshot, onRetry: () {}),
        ),
      ),
    );
  }

  testWidgets('실시간 요약 title은 상태별로 구분된 문구를 보여준다 (#2078)', (tester) async {
    // unsupported: 미지원 노선은 사실형으로 안내하고, 준비 중 진행형을 쓰지 않는다.
    await pump(
      tester,
      const RealtimeSnapshot(status: RealtimeSnapshotStatus.unsupported),
    );
    expect(find.text('실시간 정보 미지원'), findsOneWidget);
    expect(find.text('지원 준비 중'), findsNothing);

    // loading: 실제 진행 중이라 진행형 title을 유지한다.
    await pump(
      tester,
      const RealtimeSnapshot(status: RealtimeSnapshotStatus.loading),
    );
    expect(find.text('실시간 정보 확인 중'), findsOneWidget);

    // unavailable: 조회 실패는 재시도 대상이라 별도 문구로 구분한다.
    await pump(
      tester,
      const RealtimeSnapshot(status: RealtimeSnapshotStatus.unavailable),
    );
    expect(find.text('실시간 정보 확인 불가'), findsOneWidget);

    // 세 상태 title이 서로 다른 문구로 구분된다.
    expect('실시간 정보 미지원', isNot(equals('실시간 정보 확인 중')));
    expect('실시간 정보 확인 중', isNot(equals('실시간 정보 확인 불가')));
    expect('실시간 정보 미지원', isNot(equals('실시간 정보 확인 불가')));
  });

  testWidgets('인접역이 주어지면 방면 헤더가 인접역 방면으로 정규화되고 행선지가 표시된다', (tester) async {
    const arrivals = [
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '사당',
        direction: '상행',
        trainNo: '4012',
        message: '전역 도착',
        positionMessage: '상록수',
        etaSeconds: 120,
      ),
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '오이도',
        direction: '하행',
        trainNo: '4015',
        message: '전역 출발',
        positionMessage: '중앙',
        etaSeconds: 720,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRealtimeSummary(
            snapshot: const RealtimeSnapshot(
              status: RealtimeSnapshotStatus.fresh,
              arrivals: arrivals,
            ),
            previousStation: '반월',
            nextStation: '한대앞',
            onRetry: () {},
          ),
        ),
      ),
    );

    // 인접역 기준 방면 헤더 확인
    expect(find.text('반월 방면'), findsOneWidget);
    expect(find.text('한대앞 방면'), findsOneWidget);

    // 열차 종착역 행선지 확인
    expect(find.text('사당행'), findsOneWidget);
    expect(find.text('오이도행'), findsOneWidget);

    // 도착 시간 및 위치 확인 (임의 시각 전환 없이 분 뒤 도착으로 통일)
    expect(find.text('2분 뒤 도착'), findsOneWidget);
    expect(find.text('12분 뒤 도착'), findsOneWidget);
  });

  testWidgets('공공 API가 하행으로 내려준 사당행 열차가 상행으로 왜곡되지 않고 하행(한대앞 방면)으로 정확히 분류된다', (
    tester,
  ) async {
    const arrivals = [
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '사당',
        direction: '하행',
        trainNo: '4020',
        message: '전역 도착',
        positionMessage: '반월',
        etaSeconds: 180,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRealtimeSummary(
            snapshot: const RealtimeSnapshot(
              status: RealtimeSnapshotStatus.fresh,
              arrivals: arrivals,
            ),
            previousStation: '반월',
            nextStation: '한대앞',
            onRetry: () {},
          ),
        ),
      ),
    );

    // 하행 사당행 열차는 previousStation(반월 방면, 상행)이 아닌 nextStation(한대앞 방면, 하행)으로 매핑되어야 함
    expect(find.text('한대앞 방면'), findsOneWidget);
    expect(find.text('반월 방면'), findsNothing);
    expect(find.text('사당행'), findsOneWidget);
    expect(find.text('3분 뒤 도착'), findsOneWidget);
  });

  testWidgets('도착 임박(당역 도착, 진입)은 곧 도착 빨간 강조이고, 전역 도착은 빨간 위험이 아닌 전역 상태로 표시된다', (
    tester,
  ) async {
    const arrivals = [
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '오이도',
        direction: '하행',
        trainNo: '4010',
        message: '당역 도착',
        positionMessage: '상록수',
        etaSeconds: 0,
      ),
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '사당',
        direction: '상행',
        trainNo: '4012',
        message: '전역 도착',
        positionMessage: '반월',
        etaSeconds: 0,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRealtimeSummary(
            snapshot: const RealtimeSnapshot(
              status: RealtimeSnapshotStatus.fresh,
              arrivals: arrivals,
            ),
            previousStation: '반월',
            nextStation: '한대앞',
            onRetry: () {},
          ),
        ),
      ),
    );

    // 당역 도착 열차는 '곧 도착' 텍스트로 치환되고 빨간색 강조 (statusDanger)
    expect(find.text('곧 도착'), findsOneWidget);
    final soonText = tester.widget<Text>(find.text('곧 도착'));
    expect(soonText.style?.color, EasySubwayColorPrimitives.statusDanger);

    // 전역 도착 열차는 '전역 도착' 텍스트를 유지하고, 빨간색이 아닌 브랜드 컬러(primary)
    expect(find.text('전역 도착'), findsOneWidget);
    final prevStationText = tester.widget<Text>(find.text('전역 도착'));
    expect(prevStationText.style?.color, EasySubwayAccessibleColors.primary);
  });

  testWidgets('다양한 ETA, 위치메시지, 인접역 및 방면 분기가 정확히 매핑된다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var retried = false;
    const arrivals = [
      // 1. eta < 60 -> 곧 도착
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '사당',
        direction: '상행',
        trainNo: '4001',
        message: '',
        positionMessage: '',
        etaSeconds: 30,
      ),
      // 2. eta 150 -> 3분 뒤 도착 (isWarning)
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '안산',
        direction: '하행',
        trainNo: '4002',
        message: '운행중',
        positionMessage: '반월출발',
        etaSeconds: 150,
      ),
      // 3. eta > 3600 (시간, 분)
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '청량리',
        direction: '내선',
        trainNo: '4003',
        message: '',
        positionMessage: '',
        etaSeconds: 3660, // 1시간 1분
      ),
      // 4. eta > 3600 (정각 시간)
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '신창',
        direction: '외선',
        trainNo: '4004',
        message: '',
        positionMessage: '',
        etaSeconds: 7200, // 2시간
      ),
      // 5. destination/direction 없는 fallback -> 열차 도착
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '',
        direction: '',
        trainNo: '4005',
        message: '',
        positionMessage: '3역전',
        etaSeconds: null,
      ),
      // 6. rawDir 기반 매핑 (상행 -> prev, 하행 -> next)
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '진접행',
        direction: '상행',
        trainNo: '4006',
        message: '진입',
        positionMessage: '상록수진입',
        etaSeconds: 0,
      ),
      RealtimeArrival(
        lineId: 'seoul-4',
        stationName: '상록수',
        destination: '인천',
        direction: '하행',
        trainNo: '4007',
        message: '도착',
        positionMessage: '상록수',
        etaSeconds: 0,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StationRealtimeSummary(
              snapshot: const RealtimeSnapshot(
                status: RealtimeSnapshotStatus.fresh,
                arrivals: arrivals,
              ),
              previousStation: '반월',
              nextStation: '한대앞',
              onRetry: () => retried = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('반월 방면'), findsWidgets);
    expect(find.text('한대앞 방면'), findsWidgets);
    expect(find.text('열차 도착'), findsOneWidget);
    expect(find.text('1시간 1분 뒤 도착'), findsOneWidget);
    expect(find.text('2시간 뒤 도착'), findsOneWidget);
    expect(find.text('반월출발 (운행중)'), findsOneWidget);
    expect(retried, isFalse);
  });

  testWidgets('인접역 없이 단독 방면 및 목적지 분기 테스트', (tester) async {
    const arrivals = [
      RealtimeArrival(
        lineId: 'line-1',
        stationName: '역',
        destination: '수원행',
        direction: '',
        trainNo: '101',
        message: '',
        positionMessage: '',
        etaSeconds: null,
      ),
      RealtimeArrival(
        lineId: 'line-1',
        stationName: '역',
        destination: '',
        direction: '소요산',
        trainNo: '102',
        message: '전역',
        positionMessage: '',
        etaSeconds: null,
      ),
      RealtimeArrival(
        lineId: 'line-1',
        stationName: '역',
        destination: '',
        direction: '상행',
        trainNo: '103',
        message: '전역',
        positionMessage: '',
        etaSeconds: null,
      ),
      RealtimeArrival(
        lineId: 'line-1',
        stationName: '역',
        destination: '',
        direction: '하행',
        trainNo: '104',
        message: '전역',
        positionMessage: '',
        etaSeconds: null,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRealtimeSummary(
            snapshot: const RealtimeSnapshot(
              status: RealtimeSnapshotStatus.fresh,
              arrivals: arrivals,
            ),
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('수원 방면'), findsOneWidget);
    expect(find.text('소요산 방면'), findsOneWidget);
    expect(find.text('상행 방면'), findsOneWidget);
    expect(find.text('하행 방면'), findsOneWidget);
  });
}
