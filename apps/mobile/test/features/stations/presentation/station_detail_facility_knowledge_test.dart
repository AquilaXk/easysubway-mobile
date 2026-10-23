import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _geumnamno = StationDetail(
  id: 'station-geumnamno-4ga',
  nameKo: '금남로4가',
  nameEn: 'Geumnamno 4-ga',
  region: '광주권',
  dataQualityLevel: 'LEVEL_1',
  lastVerifiedAt: '2026-09-09',
  lines: [
    StationSearchLine(
      id: 'gwangju-1',
      name: '광주 1호선',
      color: '#009088',
      stationCode: '105',
    ),
  ],
);

StationFacilityInfo _installed(String type, String name) {
  return StationFacilityInfo(
    id: 'facility-geumnamno-$type',
    stationId: _geumnamno.id,
    exitId: '',
    type: type,
    name: name,
    floorFrom: '',
    floorTo: '',
    description: '',
    status: 'UNKNOWN',
    dataConfidence: 'HIGH',
    lastUpdatedAt: '2026-09-09',
  );
}

StationDetail _withAbsences(Set<String> absentTypes) {
  return StationDetail(
    id: _geumnamno.id,
    nameKo: _geumnamno.nameKo,
    nameEn: _geumnamno.nameEn,
    region: _geumnamno.region,
    dataQualityLevel: _geumnamno.dataQualityLevel,
    lastVerifiedAt: _geumnamno.lastVerifiedAt,
    lines: _geumnamno.lines,
    confirmedAbsentFacilityTypes: absentTypes,
  );
}

final _geumnamnoFacilities = [
  _installed('ELEVATOR', '금남로4가역 엘리베이터 설치 정보'),
  _installed('ESCALATOR', '금남로4가역 에스컬레이터 설치 정보'),
];

const _uncoveredLabels = ['장애인화장실', '수유실', '자전거보관소', '환승주차장', '유실물센터', '물품보관소'];

/// 칸 라벨은 역정보 묶음의 합친 낭독 라벨 안에서 한 줄을 차지한다.
Finder _announced(String line) {
  return find.bySemanticsLabel(
    RegExp('^${RegExp.escape(line)}\$', multiLine: true),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  StationDetail detail = _geumnamno,
  List<StationFacilityInfo>? facilities,
  List<StationExitInfo> exits = const [],
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StationDetailBody(
          state: StationDetailState(
            status: StationDetailStatus.success,
            detail: detail,
            exits: exits,
            facilities: facilities ?? _geumnamnoFacilities,
          ),
          onRetryRealtime: () {},
          onOpenFacilityReport: (_) async {},
          mapLauncher: const UrlLauncherKakaoMapLauncher(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('원천이 다루지 않는 시설 유형은 없음으로 그리지도 읽지도 않는다', (tester) async {
    await _pumpDetail(tester);

    for (final label in _uncoveredLabels) {
      expect(find.text(label), findsNothing, reason: label);
      expect(_announced('$label 없음'), findsNothing, reason: label);
    }
    expect(find.text('편의시설'), findsNothing);
    expect(find.text('역정보'), findsOneWidget);
    expect(_announced('엘리베이터 있음'), findsOneWidget);
  });

  testWidgets('원천이 미설치를 확인한 유형만 없음으로 그리고 읽는다', (tester) async {
    await _pumpDetail(tester, detail: _withAbsences(const {'WHEELCHAIR_LIFT'}));

    expect(find.text('휠체어 리프트'), findsOneWidget);
    expect(_announced('휠체어 리프트 없음'), findsOneWidget);
    expect(_announced('휠체어 리프트 있음'), findsNothing);
    expect(_announced('엘리베이터 있음'), findsOneWidget);
  });

  testWidgets('신고할 수 있는 시설 칸만 탭 동작을 가지고 역정보 묶음은 탭되지 않는다', (tester) async {
    await _pumpDetail(tester, detail: _withAbsences(const {'WHEELCHAIR_LIFT'}));

    final heading = tester.getSemantics(find.text('역정보'));
    final elevatorCell = tester.getSemantics(_announced('엘리베이터 있음'));
    final liftCell = tester.getSemantics(_announced('휠체어 리프트 없음'));

    expect(heading.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(
      elevatorCell.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(liftCell.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
  });

  testWidgets('설치 기록이 있는 유형은 미설치 증거보다 있음이 앞선다', (tester) async {
    await _pumpDetail(tester, detail: _withAbsences(const {'ELEVATOR'}));

    expect(_announced('엘리베이터 있음'), findsOneWidget);
    expect(_announced('엘리베이터 없음'), findsNothing);
  });

  testWidgets('시설 행도 미설치 증거도 없는 유형은 칸을 그리지 않는다', (tester) async {
    await _pumpDetail(tester, facilities: const []);

    expect(find.text('역정보'), findsNothing);
    expect(find.text('교통약자 시설'), findsNothing);
    expect(find.text('엘리베이터'), findsNothing);
    expect(find.text('휠체어 리프트'), findsNothing);
  });

  testWidgets('시설 행이 없어도 미설치 증거가 있는 역은 없음 칸을 보인다', (tester) async {
    await _pumpDetail(
      tester,
      detail: _withAbsences(const {'ELEVATOR', 'WHEELCHAIR_LIFT'}),
      facilities: const [],
    );

    expect(find.text('교통약자 시설'), findsOneWidget);
    expect(_announced('엘리베이터 없음'), findsOneWidget);
    expect(_announced('휠체어 리프트 없음'), findsOneWidget);
    for (final label in _uncoveredLabels) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('원천이 확인한 편의시설과 교통약자 시설은 있음으로 그린다', (tester) async {
    await _pumpDetail(
      tester,
      facilities: [
        _installed('BICYCLE', '자전거 보관대'),
        _installed('ACCESSIBLE_TOILET', '장애인 화장실'),
        _installed('NURSING_ROOM', '수유실'),
      ],
    );

    expect(find.text('편의시설'), findsOneWidget);
    expect(_announced('자전거보관소 있음'), findsOneWidget);
    expect(_announced('장애인화장실 있음'), findsOneWidget);
    expect(_announced('수유실 있음'), findsOneWidget);
    for (final label in ['환승주차장', '유실물센터', '물품보관소', '엘리베이터', '휠체어 리프트']) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('엘리베이터 연결이 확인되지 않은 출구는 엘리베이터 없음을 읽지 않는다', (tester) async {
    const exit = StationExitInfo(
      id: 'exit-geumnamno-1',
      stationId: 'station-geumnamno-4ga',
      exitNumber: '1',
      name: '1번 출구',
      description: '금남로 방면',
      hasElevatorConnection: false,
      hasStairOnlyPath: StairOnlyPathStatus.unknown,
      dataConfidence: 'HIGH',
    );

    await _pumpDetail(tester, exits: const [exit]);

    expect(find.text('1번 출구'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('엘리베이터 없음')), findsNothing);
    expect(exit.semanticLabel, isNot(contains('엘리베이터')));
  });
}
