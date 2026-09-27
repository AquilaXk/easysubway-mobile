import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
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
          onOpenFacilityReport: (_) async {},
          mapLauncher: const UrlLauncherKakaoMapLauncher(),
        ),
      ),
    );
  }

  testWidgets('네이버 지도 1:1 표준 출구정보(미니맵 확대, 출구 알약 탭, 장소 정보, 가까운 하차문)가 렌더링되고 슬롭 버튼이 제거된다', (
    tester,
  ) async {
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

    // 잔여 슬롭 버튼 완전 삭제 검증
    expect(find.text('버스 도착 정보 보기'), findsNothing);
    expect(find.text('카카오맵에서 보기'), findsNothing);
    expect(find.text('출구까지 거리'), findsNothing);
    expect(find.text('도보 길안내'), findsNothing);
  });

  testWidgets('네이버 지도 1:1 표준 역정보(시설정보, 편의시설, 교통약자 시설 2x2 그리드) 및 하단 액션바가 렌더링된다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildDetailBody());
    await tester.pumpAndSettle();

    expect(find.text('역정보'), findsOneWidget);
    expect(find.text('시설정보'), findsOneWidget);
    expect(find.text('플랫폼'), findsOneWidget);
    expect(find.text('양쪽'), findsWidgets);
    expect(find.text('화장실'), findsOneWidget);
    expect(find.text('개찰구 안/밖'), findsOneWidget);
    expect(find.text('내리는문'), findsOneWidget);
    expect(find.text('오른쪽'), findsOneWidget);
    expect(find.text('반대편'), findsOneWidget);
    expect(find.text('연결됨'), findsOneWidget);

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
}
