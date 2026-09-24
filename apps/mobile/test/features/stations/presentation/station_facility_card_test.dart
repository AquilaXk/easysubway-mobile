import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_facility_card.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_facility_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testStation = StationDetail(
    id: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    dataQualityLevel: 'VERIFIED',
    lastVerifiedAt: '2026-08-12T00:00:00Z',
    lines: [],
  );

  testWidgets('StationFacilityCard은 정상 엘리베이터를 전용 아이콘 컨테이너와 함께 조용히 렌더링한다', (
    tester,
  ) async {
    const normalElevator = StationFacilityInfo(
      id: 'facility-elevator-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-1',
      type: 'ELEVATOR',
      name: '1번 출구 엘리베이터',
      floorFrom: 'B1',
      floorTo: '1F',
      description: '1번 출구 앞',
      status: 'NORMAL',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-06-12',
    );

    var reported = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationFacilityCard(
            facility: normalElevator,
            station: testStation,
            onReportTap: () => reported = true,
          ),
        ),
      ),
    );

    // 엘리베이터 아이콘 컨테이너
    expect(find.byIcon(Icons.elevator), findsOneWidget);
    expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
    expect(find.text('1번 출구 앞'), findsOneWidget);

    // 단독 시설명 텍스트 및 정상 상태 배지는 표시되지 않는다
    expect(find.text('엘리베이터'), findsNothing);
    expect(find.text('이용 가능'), findsNothing);

    // 접근성 가이드라인 준수 확인
    final semanticsHandle = tester.ensureSemantics();
    try {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }

    // 제보 버튼 상호작용
    final reportButton = find.byKey(
      const Key('facilityReportButton-facility-elevator-1'),
    );
    expect(reportButton, findsOneWidget);
    await tester.tap(reportButton);
    expect(reported, isTrue);
  });

  testWidgets('StationFacilityCard은 에스컬레이터 및 주의 상태 뱃지를 올바르게 렌더링하고 상세로 진입한다', (
    tester,
  ) async {
    const cautionEscalator = StationFacilityInfo(
      id: 'facility-escalator-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-2',
      type: 'ESCALATOR',
      name: '2번 출구 에스컬레이터',
      floorFrom: 'B1',
      floorTo: '1F',
      description: '2번 출구 통로',
      status: 'UNKNOWN',
      dataConfidence: 'LOW',
      lastUpdatedAt: '2026-06-10',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationFacilityCard(
            facility: cautionEscalator,
            station: testStation,
            onReportTap: () {},
          ),
        ),
      ),
    );

    // 에스컬레이터 전용 아이콘
    expect(find.byIcon(Icons.escalator), findsOneWidget);
    expect(find.text('2번 출구 에스컬레이터'), findsOneWidget);

    // 주의/미확인 상태 뱃지 노출
    expect(find.text('설치 확인 · 운행상태 미확인'), findsOneWidget);
    expect(find.text('에스컬레이터'), findsNothing);

    // 카드 탭 시 상세 화면 진입
    await tester.tap(
      find.byKey(const Key('stationFacilityCard-facility-escalator-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FacilityDetailScreen), findsOneWidget);
  });

  testWidgets('StationFacilityCard은 휠체어 리프트 고장 상태를 경고 뱃지와 함께 렌더링한다', (
    tester,
  ) async {
    const brokenLift = StationFacilityInfo(
      id: 'facility-lift-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-3',
      type: 'WHEELCHAIR_LIFT',
      name: '3번 출구 휠체어 리프트',
      floorFrom: 'B1',
      floorTo: '1F',
      description: '3번 출구 계단',
      status: 'BROKEN',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-06-14',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationFacilityCard(
            facility: brokenLift,
            station: testStation,
            onReportTap: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.accessible_forward), findsOneWidget);
    expect(find.text('3번 출구 휠체어 리프트'), findsOneWidget);
    expect(find.text('이용할 수 없어요'), findsOneWidget);
    expect(find.text('휠체어 리프트'), findsNothing);
  });

  testWidgets(
    'StationFacilityCard은 초협소 화면(320dp) 및 접근성 3.0x 텍스트 스케일에서도 오버플로 없이 렌더링된다',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longFacility = StationFacilityInfo(
        id: 'facility-long-name',
        stationId: 'station-sangnoksu',
        exitId: 'exit-10',
        type: 'ESCALATOR',
        name: '10번 출구 환승통로 방면 내부 에스컬레이터 (상행/하행 전용)',
        floorFrom: 'B3',
        floorTo: '2F',
        description: '지하 3층 승강장에서 2층 대합실 및 환승 이동 통로 방면',
        status: 'UNKNOWN',
        dataConfidence: 'LOW',
        lastUpdatedAt: '2026-06-10',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(3.0),
            ),
            child: Scaffold(
              body: ListView(
                children: [
                  StationFacilityCard(
                    facility: longFacility,
                    station: testStation,
                    onReportTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.escalator), findsOneWidget);
      expect(find.text('10번 출구 환승통로 방면 내부 에스컬레이터 (상행/하행 전용)'), findsOneWidget);
      expect(find.text('설치 확인 · 운행상태 미확인'), findsOneWidget);
      expect(find.text('지하 3층 승강장에서 2층 대합실 및 환승 이동 통로 방면'), findsOneWidget);
    },
  );

  testWidgets(
    'StationFacilityCard은 경사로·화장실·수유실·고객센터 등 다양한 시설 유형 아이콘을 정확히 매핑한다',
    (tester) async {
      const types = [
        ('RAMP', Icons.accessible),
        ('ACCESSIBLE_TOILET', Icons.wc_outlined),
        ('TOILET', Icons.wc_outlined),
        ('NURSING_ROOM', Icons.baby_changing_station),
        ('CUSTOMER_CENTER', Icons.support_agent),
        ('STATION_OFFICE', Icons.support_agent),
        ('UNKNOWN_TYPE', Icons.info_outline),
      ];

      for (final (type, expectedIcon) in types) {
        final facility = StationFacilityInfo(
          id: 'facility-$type',
          stationId: 'station-sangnoksu',
          exitId: 'exit-1',
          type: type,
          name: '$type 테스트 시설',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '테스트 위치',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StationFacilityCard(
                facility: facility,
                station: testStation,
                onReportTap: () {},
              ),
            ),
          ),
        );

        expect(find.byIcon(expectedIcon), findsOneWidget);
      }
    },
  );

  testWidgets(
    'StationFacilityCard은 Material 위젯으로 InkWell을 호스팅하여 잉크 반응과 둥근 모서리 클리핑을 보장한다',
    (tester) async {
      const elevator = StationFacilityInfo(
        id: 'facility-ink-test',
        stationId: 'station-sangnoksu',
        exitId: 'exit-1',
        type: 'ELEVATOR',
        name: '1번 출구 엘리베이터',
        floorFrom: 'B1',
        floorTo: '1F',
        description: '1번 출구 앞',
        status: 'NORMAL',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-06-12',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StationFacilityCard(
              facility: elevator,
              station: testStation,
              onReportTap: () {},
            ),
          ),
        ),
      );

      final materialFinder = find.descendant(
        of: find.byType(StationFacilityCard),
        matching: find.byType(Material),
      );
      expect(materialFinder, findsWidgets);

      final cardMaterial = tester.widget<Material>(materialFinder.first);
      expect(cardMaterial.clipBehavior, Clip.antiAlias);
      expect(cardMaterial.color, EasySubwayAccessibleColors.surface);

      final inkWellFinder = find.descendant(
        of: materialFinder.first,
        matching: find.byKey(
          const Key('stationFacilityCard-facility-ink-test'),
        ),
      );
      expect(inkWellFinder, findsOneWidget);
    },
  );
}
