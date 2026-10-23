import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:flutter/material.dart';
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

final _geumnamnoFacilities = [
  _installed('ELEVATOR', '금남로4가역 엘리베이터 설치 정보'),
  _installed('ESCALATOR', '금남로4가역 에스컬레이터 설치 정보'),
];

const _uncoveredLabels = ['장애인화장실', '수유실', '자전거보관소', '환승주차장', '유실물센터', '물품보관소'];

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
      expect(
        find.bySemanticsLabel(RegExp('^$label 없음')),
        findsNothing,
        reason: label,
      );
    }
    expect(find.text('편의시설'), findsNothing);
    expect(find.text('역정보'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^엘리베이터 있음')), findsOneWidget);
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
