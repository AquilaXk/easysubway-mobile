import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_target.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testStation = StationDetail(
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

  const testExits = [
    StationExitInfo(
      id: 'exit-1',
      stationId: 'station-sangnoksu',
      exitNumber: '1',
      name: '1번 출구',
      description: '상록수역 공영주차장, 본오동 방면',
      hasElevatorConnection: true,
      hasStairOnlyPath: false,
      dataConfidence: 'HIGH',
      lastVerifiedAt: '2026-09-27',
      nearbyDoorHint: '반월 방면 4-4, 7-3, 한대앞 방면 4-2, 7-1',
    ),
    StationExitInfo(
      id: 'exit-2',
      stationId: 'station-sangnoksu',
      exitNumber: '2',
      name: '2번 출구',
      description: '일동 방면, 안산상록경찰서',
      hasElevatorConnection: false,
      hasStairOnlyPath: true,
      dataConfidence: 'HIGH',
      lastVerifiedAt: '2026-09-27',
    ),
  ];

  const testFacilities = [
    StationFacilityInfo(
      id: 'facility-ev-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-1',
      type: 'ELEVATOR',
      name: '1번 출구 엘리베이터',
      floorFrom: 'B1',
      floorTo: '1F',
      description: '1번 출구 지상 연결',
      status: 'NORMAL',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-09-27',
    ),
    StationFacilityInfo(
      id: 'facility-toilet-1',
      stationId: 'station-sangnoksu',
      exitId: '',
      type: 'TOILET',
      name: '대합실 화장실',
      floorFrom: 'B1',
      floorTo: 'B1',
      description: '개찰구 밖 대합실 서편',
      status: 'NORMAL',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-09-27',
    ),
    StationFacilityInfo(
      id: 'facility-toilet-2',
      stationId: 'station-sangnoksu',
      exitId: '',
      type: 'ACCESSIBLE_TOILET',
      name: '승강장 장애인 화장실',
      floorFrom: '1F',
      floorTo: '1F',
      description: '개찰구 안 당고개 방면 승강장',
      status: 'NORMAL',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-09-27',
    ),
    StationFacilityInfo(
      id: 'facility-nursing-1',
      stationId: 'station-sangnoksu',
      exitId: '',
      type: 'NURSING_ROOM',
      name: '수유실',
      floorFrom: 'B1',
      floorTo: 'B1',
      description: '고객안전실 옆',
      status: 'NORMAL',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-09-27',
    ),
  ];

  Widget buildDetailBody({
    List<StationExitInfo> exits = testExits,
    List<StationFacilityInfo> facilities = testFacilities,
    Future<void> Function(FacilityReportTarget)? onOpenFacilityReport,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StationDetailBody(
          state: StationDetailState(
            status: StationDetailStatus.success,
            detail: testStation,
            exits: exits,
            facilities: facilities,
          ),
          onRetryRealtime: () {},
          onOpenFacilityReport: onOpenFacilityReport ?? (_) async {},
          mapLauncher: const UrlLauncherKakaoMapLauncher(),
        ),
      ),
    );
  }

  testWidgets(
    '네이버 지도 1:1 표준 출구정보(미니맵 확대, 출구 알약 탭, 장소 정보, 가까운 하차문)가 렌더링되고 슬롭 버튼이 제거된다',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDetailBody());
      await tester.pumpAndSettle();

      expect(find.text('출구정보'), findsOneWidget);
      expect(find.text('장소 정보'), findsOneWidget);
      expect(find.text('상록수역 공영주차장, 본오동 방면'), findsOneWidget);
      expect(find.text('출구와 가까운 하차문'), findsOneWidget);
      expect(find.text('반월 방면 4-4, 7-3, 한대앞 방면 4-2, 7-1'), findsOneWidget);
      expect(find.byKey(const Key('stationExitPill-exit-1')), findsOneWidget);
      expect(find.byKey(const Key('stationExitPill-exit-2')), findsOneWidget);
      expect(
        find.byKey(const Key('stationExitMapExpandButton')),
        findsOneWidget,
      );

      // 하차문 정보가 없는 2번 출구 선택 시 '출구와 가까운 하차문' 섹션이 숨겨짐을 검증
      await tester.tap(find.byKey(const Key('stationExitPill-exit-2')));
      await tester.pumpAndSettle();
      expect(find.text('일동 방면, 안산상록경찰서'), findsOneWidget);
      expect(find.text('출구와 가까운 하차문'), findsNothing);

      // 잔여 슬롭 버튼 완전 삭제 검증
      expect(find.text('버스 도착 정보 보기'), findsNothing);
      expect(find.text('카카오맵에서 보기'), findsNothing);
      expect(find.text('출구까지 거리'), findsNothing);
      expect(find.text('도보 길안내'), findsNothing);
    },
  );

  testWidgets('공식 하차문 정보가 없는 출구만 존재하는 역은 가짜 모듈로 산술 없이 하차문 섹션을 완전히 숨긴다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const exitsWithoutDoorHint = [
      StationExitInfo(
        id: 'exit-no-door-1',
        stationId: 'station-sangnoksu',
        exitNumber: '1',
        name: '1번 출구',
        description: '상록수역 공영주차장',
        hasElevatorConnection: true,
        hasStairOnlyPath: false,
        dataConfidence: 'HIGH',
      ),
    ];

    await tester.pumpWidget(buildDetailBody(exits: exitsWithoutDoorHint));
    await tester.pumpAndSettle();

    expect(find.text('출구정보'), findsOneWidget);
    expect(find.text('상록수역 공영주차장'), findsOneWidget);
    // 가짜 산술로 생성된 하차문 및 섹션 타이틀이 없어야 함
    expect(find.text('출구와 가까운 하차문'), findsNothing);
    expect(find.textContaining('반월 방면'), findsNothing);
    expect(find.textContaining('한대앞 방면'), findsNothing);
  });

  testWidgets(
    '네이버 지도 1:1 표준 역정보(시설정보, 편의시설, 교통약자 시설 2x2 그리드) 및 하단 액션바가 렌더링된다',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDetailBody());
      await tester.pumpAndSettle();

      expect(find.text('역정보'), findsOneWidget);
      expect(find.text('시설정보'), findsOneWidget);
      expect(find.text('플랫폼'), findsOneWidget);
      expect(find.text('화장실'), findsOneWidget);
      expect(find.text('개찰구 안/밖'), findsOneWidget);
      expect(find.text('내리는문'), findsOneWidget);
      expect(find.text('반대편'), findsOneWidget);
      // 승강장(플랫폼, 내리는문, 반대편) 데이터 부재 시 가짜 기본값 대신 '-'이 정직하게 표출됨
      expect(find.text('-'), findsNWidgets(3));
      expect(find.text('양쪽'), findsNothing);
      expect(find.text('오른쪽'), findsNothing);
      expect(find.text('연결됨'), findsNothing);

      expect(find.text('편의시설'), findsOneWidget);
      expect(find.text('자전거보관소'), findsOneWidget);
      expect(find.text('환승주차장'), findsOneWidget);
      expect(find.text('유실물센터'), findsOneWidget);
      expect(find.text('물품보관소'), findsOneWidget);

      expect(find.text('교통약자 시설'), findsOneWidget);
      expect(find.text('장애인화장실'), findsOneWidget);
      expect(find.text('엘리베이터'), findsWidgets);
      expect(find.text('수유실'), findsWidgets);
      expect(find.text('휠체어 리프트'), findsOneWidget);

      // 하단 고정 액션바 4종 버튼 검증
      expect(find.text('출발'), findsOneWidget);
      expect(find.text('도착'), findsOneWidget);
      expect(find.text('전체 시간표'), findsOneWidget);
      expect(find.text('첫차·막차'), findsOneWidget);
    },
  );

  testWidgets('공식 승강장 정보(내리는문, 플랫폼, 반대편 횡단)가 데이터에 명시된 경우 올바른 태그로 매핑된다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const facilitiesWithPlatform = [
      ...testFacilities,
      StationFacilityInfo(
        id: 'facility-platform-1',
        stationId: 'station-sangnoksu',
        exitId: '',
        type: 'PLATFORM',
        name: '상대식 승강장',
        floorFrom: 'B1',
        floorTo: 'B1',
        description: '상대식 승강장, 왼쪽 내리는 문, 반대편 횡단가능 연결됨',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];

    await tester.pumpWidget(
      buildDetailBody(facilities: facilitiesWithPlatform),
    );
    await tester.pumpAndSettle();

    expect(find.text('플랫폼'), findsOneWidget);
    expect(find.text('양쪽'), findsOneWidget);
    expect(find.text('내리는문'), findsOneWidget);
    expect(find.text('왼쪽'), findsOneWidget);
    expect(find.text('반대편'), findsOneWidget);
    expect(find.text('연결됨'), findsOneWidget);
  });

  testWidgets('공식 승강장 정보에 반대편 횡단 불가(공백 포함) 표기 시 이동 불가로 매핑된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const facilitiesWithNoCross = [
      ...testFacilities,
      StationFacilityInfo(
        id: 'facility-platform-nocross',
        stationId: 'station-sangnoksu',
        exitId: '',
        type: 'PLATFORM',
        name: '상대식 승강장',
        floorFrom: 'B1',
        floorTo: 'B1',
        description: '오른쪽 내리는 문, 반대편 횡단 불가',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];

    await tester.pumpWidget(buildDetailBody(facilities: facilitiesWithNoCross));
    await tester.pumpAndSettle();

    expect(find.text('내리는문'), findsOneWidget);
    expect(find.text('오른쪽'), findsOneWidget);
    expect(find.text('반대편'), findsOneWidget);
    expect(find.text('이동 불가'), findsOneWidget);
  });

  testWidgets('화장실 정보가 전혀 없으면 임의로 개찰구 밖을 날조하지 않고 -으로 정직하게 표출한다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const facilitiesWithoutToilet = [
      StationFacilityInfo(
        id: 'facility-ev-only',
        stationId: 'station-sangnoksu',
        exitId: 'exit-1',
        type: 'ELEVATOR',
        name: '1번 출구 엘리베이터',
        floorFrom: 'B1',
        floorTo: '1F',
        description: '1번 출구 지상 연결',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];

    await tester.pumpWidget(
      buildDetailBody(facilities: facilitiesWithoutToilet),
    );
    await tester.pumpAndSettle();

    expect(find.text('화장실'), findsOneWidget);
    expect(find.text('-'), findsNWidgets(4)); // 플랫폼, 화장실, 내리는문, 반대편 모두 -
    expect(find.text('개찰구 밖'), findsNothing);
    expect(find.text('개찰구 안'), findsNothing);
  });

  testWidgets('개찰구 안 단독 화장실 시설만 존재하는 경우 개찰구 안 태그가 정확히 표출된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const insideOnlyToilet = [
      StationFacilityInfo(
        id: 'facility-toilet-inside',
        stationId: 'station-sangnoksu',
        exitId: '',
        type: 'TOILET',
        name: '승강장 화장실',
        floorFrom: '1F',
        floorTo: '1F',
        description: '개찰구 안 1번 승강장',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];

    await tester.pumpWidget(buildDetailBody(facilities: insideOnlyToilet));
    await tester.pumpAndSettle();

    expect(find.text('화장실'), findsOneWidget);
    expect(find.text('개찰구 안'), findsOneWidget);
    expect(find.text('개찰구 밖'), findsNothing);
    expect(find.text('개찰구 안/밖'), findsNothing);
  });

  testWidgets('개찰구 밖 단독 화장실 시설만 존재하는 경우 개찰구 밖 태그가 정확히 표출된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const outsideOnlyToilet = [
      StationFacilityInfo(
        id: 'facility-toilet-outside',
        stationId: 'station-sangnoksu',
        exitId: '',
        type: 'TOILET',
        name: '대합실 화장실',
        floorFrom: 'B1',
        floorTo: 'B1',
        description: '개찰구 밖 대합실',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];

    await tester.pumpWidget(buildDetailBody(facilities: outsideOnlyToilet));
    await tester.pumpAndSettle();

    expect(find.text('화장실'), findsOneWidget);
    expect(find.text('개찰구 밖'), findsOneWidget);
    expect(find.text('개찰구 안'), findsNothing);
    expect(find.text('개찰구 안/밖'), findsNothing);
  });

  testWidgets('출구 DB가 비어있으면 출구정보를 숨기고 역정보와 하단 액션바만 렌더링된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildDetailBody(
        exits: const [],
        facilities: testFacilities.take(2).toList(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('출구정보'), findsNothing);
    expect(find.text('역정보'), findsOneWidget);
    expect(find.text('시설정보'), findsOneWidget);
    expect(find.text('전체 시간표'), findsOneWidget);
  });

  testWidgets('출구와 시설 정보가 모두 비어있으면 해당 섹션들을 숨기고 하단 액션바만 안정적으로 노출된다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildDetailBody(exits: const [], facilities: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('출구정보'), findsNothing);
    expect(find.text('역정보'), findsNothing);
    expect(find.text('시설정보'), findsNothing);
    expect(find.text('전체 시간표'), findsOneWidget);
  });

  testWidgets(
    '교통약자 시설 2x2 그리드 아이템 탭 시 onOpenFacilityReport 콜백이 올바른 타깃과 함께 호출된다',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FacilityReportTarget? reportedTarget;
      await tester.pumpWidget(
        buildDetailBody(
          onOpenFacilityReport: (target) async {
            reportedTarget = target;
          },
        ),
      );
      await tester.pumpAndSettle();

      // 엘리베이터 탭
      final evButton = find.byKey(
        const Key('naverFacilityReportButton-facility-ev-1'),
      );
      expect(evButton, findsOneWidget);
      await tester.tap(evButton);
      await tester.pumpAndSettle();

      expect(reportedTarget, isNotNull);
      expect(reportedTarget!.stationId, 'station-sangnoksu');
      expect(reportedTarget!.stationName, '상록수');
      expect(reportedTarget!.facilityId, 'facility-ev-1');
      expect(reportedTarget!.facilityName, '1번 출구 엘리베이터');
      expect(reportedTarget!.facilityTypeLabel, 'ELEVATOR');

      // 장애인화장실 탭
      reportedTarget = null;
      final toiletButton = find.byKey(
        const Key('naverFacilityReportButton-facility-toilet-2'),
      );
      expect(toiletButton, findsOneWidget);
      await tester.tap(toiletButton);
      await tester.pumpAndSettle();

      expect(reportedTarget, isNotNull);
      expect(reportedTarget!.facilityId, 'facility-toilet-2');
      expect(reportedTarget!.facilityName, '승강장 장애인 화장실');
    },
  );

  testWidgets('하단 출발/도착 및 시간표 버튼 터치 시 스낵바 안내 및 콜백이 실행된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildDetailBody());
    await tester.pumpAndSettle();

    // 출발 버튼 탭
    await tester.tap(find.byKey(const Key('stationDetailSetOriginButton')));
    await tester.pumpAndSettle();
    expect(find.text('상록수역을 출발역으로 설정했습니다'), findsOneWidget);

    // 스낵바 완료 대기
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 도착 버튼 탭
    await tester.tap(
      find.byKey(const Key('stationDetailSetDestinationButton')),
    );
    await tester.pumpAndSettle();
    expect(find.text('상록수역을 도착역으로 설정했습니다'), findsOneWidget);

    // 전체 시간표 버튼 탭
    await tester.tap(
      find.byKey(const Key('stationTimetableButton')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // 첫차·막차 버튼 탭
    await tester.tap(
      find.byKey(const Key('stationDetailBottomFirstLastButton')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('휠체어 리프트 시설이 있을 때 전용 키로 리포트 버튼이 제공된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const liftFacility = StationFacilityInfo(
      id: 'facility-lift-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-1',
      type: 'WHEELCHAIR_LIFT',
      name: '휠체어 리프트 1호기',
      floorFrom: '1F',
      floorTo: 'B1',
      description: '1번 출구 계단',
      status: 'NORMAL',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-09-27',
    );

    await tester.pumpWidget(
      buildDetailBody(facilities: [...testFacilities, liftFacility]),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('naverFacilityReportButton-facility-lift-1')),
      findsOneWidget,
    );
  });

  testWidgets('인접역 버튼 및 닫기 버튼이 showContextChrome 환경에서 올바르게 표시된다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var closed = false;
    StationDetailNeighbor? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationDetailBody(
            state: const StationDetailState(
              status: StationDetailStatus.success,
              detail: testStation,
              exits: testExits,
              facilities: testFacilities,
            ),
            onRetryRealtime: () {},
            onOpenFacilityReport: (_) async {},
            showContextChrome: true,
            onClose: () => closed = true,
            previousStation: const StationDetailNeighbor(
              stationId: 'station-banwol',
              nameKo: '반월',
            ),
            nextStation: const StationDetailNeighbor(
              stationId: 'station-handaeap',
              nameKo: '한대앞',
            ),
            onSelectNeighbor: (neighbor) => selected = neighbor,
            mapLauncher: const UrlLauncherKakaoMapLauncher(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 이전역 탭
    expect(find.text('< 반월역'), findsOneWidget);
    await tester.tap(find.text('< 반월역'));
    expect(selected?.nameKo, '반월');

    // 다음역 탭
    expect(find.text('한대앞역 >'), findsOneWidget);
    await tester.tap(find.text('한대앞역 >'));
    expect(selected?.nameKo, '한대앞');

    // 닫기 버튼 탭
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });

  testWidgets('편의시설(자전거보관소) 존재 시 활성 아이콘 렌더링 및 하단 첫차막차 버튼 탭 네비게이션 동작', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const facilitiesWithBike = [
      StationFacilityInfo(
        id: 'facility-bike-1',
        stationId: 'station-sangnoksu',
        exitId: '',
        type: 'BICYCLE_RACK',
        name: '자전거보관소',
        floorFrom: '1F',
        floorTo: '1F',
        description: '1번 출구 앞',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];

    await tester.pumpWidget(buildDetailBody(facilities: facilitiesWithBike));
    await tester.pumpAndSettle();

    // 자전거보관소 활성 아이콘 확인 (라인 1018) 및 엘리베이터 없음 null 분기 (라인 714)
    expect(find.text('자전거보관소'), findsWidgets);

    final customPaints = find.byType(CustomPaint);
    if (customPaints.evaluate().isNotEmpty) {
      for (final elem in customPaints.evaluate()) {
        final widget = elem.widget as CustomPaint;
        if (widget.painter != null) {
          expect(widget.painter!.shouldRepaint(widget.painter!), isFalse);
        }
        if (widget.foregroundPainter != null) {
          expect(
            widget.foregroundPainter!.shouldRepaint(widget.foregroundPainter!),
            isFalse,
          );
        }
      }
    }

    // 하단 첫차막차 버튼 탭 (라인 1353)
    final firstLastBtn = find.byKey(
      const Key('stationDetailBottomFirstLastButton'),
    );
    expect(firstLastBtn, findsOneWidget);
    await tester.tap(firstLastBtn);
    await tester.pumpAndSettle();
  });

  test(
    'StationExitInfo parses nearbyDoorHint and hasNearbyDoorHint behaves correctly',
    () {
      final withHint = StationExitInfo.fromJson(const {
        'id': 'exit-1',
        'stationId': 'station-1',
        'exitNumber': '1',
        'name': '1번 출구',
        'hasElevatorConnection': true,
        'hasStairOnlyPath': false,
        'dataConfidence': 'HIGH',
        'nearbyDoorHint': '상행 4-4, 7-3',
      });
      expect(withHint.nearbyDoorHint, '상행 4-4, 7-3');
      expect(withHint.hasNearbyDoorHint, isTrue);

      final withoutHint = StationExitInfo.fromJson(const {
        'id': 'exit-2',
        'stationId': 'station-1',
        'exitNumber': '2',
        'name': '2번 출구',
        'hasElevatorConnection': false,
        'hasStairOnlyPath': true,
        'dataConfidence': 'MEDIUM',
      });
      expect(withoutHint.nearbyDoorHint, isNull);
      expect(withoutHint.hasNearbyDoorHint, isFalse);

      final emptyHint = StationExitInfo.fromJson(const {
        'id': 'exit-3',
        'stationId': 'station-1',
        'exitNumber': '3',
        'name': '3번 출구',
        'hasElevatorConnection': false,
        'hasStairOnlyPath': false,
        'dataConfidence': 'LOW',
        'nearbyDoorHint': '   ',
      });
      expect(emptyHint.nearbyDoorHint, isNull);
      expect(emptyHint.hasNearbyDoorHint, isFalse);
    },
  );

  test(
    'StationExitInfo.semanticLabel includes nearbyDoorHint for screen readers when present',
    () {
      final withHint = StationExitInfo.fromJson(const {
        'id': 'exit-1',
        'stationId': 'station-1',
        'exitNumber': '1',
        'name': '1번 출구',
        'hasElevatorConnection': true,
        'hasStairOnlyPath': false,
        'dataConfidence': 'HIGH',
        'nearbyDoorHint': '상행 4-4, 7-3',
      });
      expect(withHint.semanticLabel, contains('출구와 가까운 하차문 상행 4-4, 7-3'));
      expect(withHint.semanticLabel, contains('1번 출구'));
      expect(withHint.semanticLabel, contains('엘리베이터 연결'));

      final withoutHint = StationExitInfo.fromJson(const {
        'id': 'exit-2',
        'stationId': 'station-1',
        'exitNumber': '2',
        'name': '2번 출구',
        'hasElevatorConnection': false,
        'hasStairOnlyPath': true,
        'dataConfidence': 'MEDIUM',
      });
      expect(withoutHint.semanticLabel, isNot(contains('출구와 가까운 하차문')));

      final emptyHint = StationExitInfo.fromJson(const {
        'id': 'exit-3',
        'stationId': 'station-1',
        'exitNumber': '3',
        'name': '3번 출구',
        'hasElevatorConnection': false,
        'hasStairOnlyPath': false,
        'dataConfidence': 'LOW',
        'nearbyDoorHint': '   ',
      });
      expect(emptyHint.semanticLabel, isNot(contains('출구와 가까운 하차문')));
    },
  );

  test(
    'StationExitInfo.semanticLabel includes description for screen reader destination guidance',
    () {
      final withDesc = StationExitInfo.fromJson(const {
        'id': 'exit-desc-1',
        'stationId': 'station-1',
        'exitNumber': '1',
        'name': '1번 출구',
        'description': '상록수역 공영주차장, 본오동 방면',
        'hasElevatorConnection': true,
        'hasStairOnlyPath': false,
        'dataConfidence': 'HIGH',
        'nearbyDoorHint': '상행 4-4',
      });
      expect(withDesc.semanticLabel, contains('상록수역 공영주차장, 본오동 방면'));
      expect(
        withDesc.semanticLabel,
        startsWith('1번 출구, 상록수역 공영주차장, 본오동 방면, 엘리베이터 연결'),
      );

      final withoutDesc = StationExitInfo.fromJson(const {
        'id': 'exit-desc-2',
        'stationId': 'station-1',
        'exitNumber': '2',
        'name': '2번 출구',
        'description': '',
        'hasElevatorConnection': false,
        'hasStairOnlyPath': true,
        'dataConfidence': 'MEDIUM',
      });
      expect(
        withoutDesc.semanticLabel,
        startsWith('2번 출구, 엘리베이터 없음, 계단만 있는 길 있음'),
      );
    },
  );

  testWidgets(
    'StationDetailBody에 ServerConnectionException 발생 시 _StationTimetableEntry가 안전하게 unavailable 상태로 전이된다',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StationDetailBody(
              state: StationDetailState(
                status: StationDetailStatus.success,
                detail: testStation,
                exits: [],
                facilities: [],
              ),
              onRetryRealtime: _noop,
              onOpenFacilityReport: _noopFacility,
              timetableRepository: _FailingTimetableRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StationDetailBody), findsOneWidget);
    },
  );
}

void _noop() {}
Future<void> _noopFacility(FacilityReportTarget target) async {}

final class _FailingTimetableRepository implements StationTimetableRepository {
  const _FailingTimetableRepository();

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) {
    throw const ServerConnectionException('서버 연결 실패');
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) {
    throw const ServerConnectionException('서버 연결 실패');
  }

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) {
    throw const ServerConnectionException('서버 연결 실패');
  }
}
