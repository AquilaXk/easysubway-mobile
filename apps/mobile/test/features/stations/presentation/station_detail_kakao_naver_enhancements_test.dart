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

  testWidgets('무단차 수직이동동선 카드가 정상 렌더링되고 전 구간 무단차 이동을 안내한다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildDetailBody());
    await tester.pumpAndSettle();

    expect(find.text('지상 ↔ 대합실 ↔ 승강장 동선'), findsOneWidget);
    expect(find.text('전 구간 무단차 이동 가능'), findsOneWidget);
    expect(find.text('지상 (출구)'), findsOneWidget);
    expect(find.text('대합실 (개찰구)'), findsOneWidget);
    expect(find.text('승강장 (탑승)'), findsOneWidget);
  });

  testWidgets('편의시설 매트릭스가 화장실 개찰구 안·밖 구분을 정확히 표시한다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildDetailBody());
    await tester.pumpAndSettle();

    expect(find.text('주요 편의시설 한눈에 보기'), findsOneWidget);
    expect(find.text('화장실 위치'), findsOneWidget);
    expect(find.text('개찰구 안·밖 모두'), findsOneWidget);
    expect(find.text('장애인 화장실'), findsWidgets);
    expect(find.text('수유실'), findsWidgets);
    expect(find.text('이용 가능'), findsOneWidget);
  });

  testWidgets('출구 카드에 description 행선지 및 연계 안내가 렌더링된다', (tester) async {
    await tester.pumpWidget(buildDetailBody());
    await tester.pumpAndSettle();

    expect(find.text('상록수역 공영주차장, 본오동 방면'), findsOneWidget);
  });

  testWidgets('고객안전실 1-Tap 다이얼 카드가 전화번호와 함께 렌더링된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildDetailBody());
    await tester.pumpAndSettle();

    expect(find.text('고객안전실 · 역무실'), findsOneWidget);
    expect(find.text('고객안전실 (역무실)'), findsOneWidget);
    expect(
      find.byKey(const Key('stationSafetyOfficeCallButton-station-sangnoksu')),
      findsOneWidget,
    );
    expect(find.text('고객안전실 전화 걸기 (1577-1234)'), findsOneWidget);
  });

  testWidgets('출구가 없더라도 시설 정보가 있으면 무단차 동선·편의시설·고객안전실 카드가 정상 렌더링된다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildDetailBody(exits: const [], facilities: testFacilities.take(2).toList()),
    );
    await tester.pumpAndSettle();

    expect(find.text('출구 정보'), findsNothing);
    expect(find.text('시설 정보'), findsOneWidget);
    expect(find.text('지상 ↔ 대합실 ↔ 승강장 동선'), findsOneWidget);
    expect(find.text('주요 편의시설 한눈에 보기'), findsOneWidget);
    expect(find.text('고객안전실 · 역무실'), findsOneWidget);
    expect(
      find.byKey(const Key('stationSafetyOfficeCallButton-station-sangnoksu')),
      findsOneWidget,
    );
    expect(find.text('고객안전실 전화 걸기 (1577-1234)'), findsOneWidget);
  });

  testWidgets('출구와 시설 정보가 모두 비어 있으면 출구 및 시설 섹션을 숨긴다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildDetailBody(exits: const [], facilities: const []));
    await tester.pumpAndSettle();

    expect(find.text('출구 정보'), findsNothing);
    expect(find.text('시설 정보'), findsNothing);
  });
}

