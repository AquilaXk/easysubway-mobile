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
    expect(find.text('시설정보'), findsNothing);
    expect(find.text('-'), findsNothing);
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

  testWidgets('확인된 칸이 하나도 없으면 역정보 제목까지 뺀다', (tester) async {
    await _pumpDetail(
      tester,
      facilities: [_installed('ESCALATOR', '금남로4가역 에스컬레이터 설치 정보')],
    );

    expect(find.text('역정보'), findsNothing);
    expect(find.text('시설 상세 및 고장 신고'), findsOneWidget);
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

  testWidgets('주차장·유실물센터·물품보관소도 원천이 확인한 경우에만 있음으로 그린다', (tester) async {
    await _pumpDetail(
      tester,
      facilities: [
        _installed('PARKING', '환승 주차장'),
        _installed('LOST_ITEM', '유실물 센터'),
        _installed('LOCKER', '물품 보관함'),
      ],
    );

    expect(_announced('환승주차장 있음'), findsOneWidget);
    expect(_announced('유실물센터 있음'), findsOneWidget);
    expect(_announced('물품보관소 있음'), findsOneWidget);
    expect(find.text('자전거보관소'), findsNothing);
    expect(find.text('교통약자 시설'), findsNothing);
  });

  testWidgets('칸은 이름을 한 번만 읽는다', (tester) async {
    await _pumpDetail(
      tester,
      detail: _withAbsences(const {'WHEELCHAIR_LIFT'}),
      facilities: [
        _installed('ELEVATOR', '금남로4가역 엘리베이터 설치 정보'),
        _installed('BICYCLE', '자전거 보관대'),
        _installed('ACCESSIBLE_TOILET', '장애인 화장실'),
        _installed('NURSING_ROOM', '수유실'),
      ],
    );

    for (final label in ['엘리베이터', '자전거보관소', '장애인화장실', '수유실']) {
      expect(_announced('$label 있음'), findsOneWidget, reason: label);
      expect(_announced(label), findsNothing, reason: label);
      expect(
        tester.getSemantics(_announced('$label 있음')).label,
        '$label 있음',
        reason: label,
      );
    }
    expect(_announced('휠체어 리프트 없음'), findsOneWidget);
    expect(_announced('휠체어 리프트'), findsNothing);
    expect(tester.getSemantics(_announced('휠체어 리프트 없음')).label, '휠체어 리프트 없음');
  });

  testWidgets('화면에 그릴 칸이 없는 미설치 증거만 있는 역은 역정보 구역과 여백을 두지 않는다', (tester) async {
    await _pumpDetail(tester, facilities: const []);
    final noEvidenceTop = tester.getTopLeft(find.text('안내')).dy;

    await _pumpDetail(
      tester,
      detail: _withAbsences(const {'ESCALATOR'}),
      facilities: const [],
    );

    expect(find.text('역정보'), findsNothing);
    expect(tester.getTopLeft(find.text('안내')).dy, noEvidenceTop);
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

  testWidgets('장애인 리프트 이름과 안내·대합실·출구 설명만으로 장애인화장실이나 개찰구 안/밖을 오판하지 않는다', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      facilities: const [
        StationFacilityInfo(
          id: 'facility-lift-1',
          stationId: 'station-geumnamno-4ga',
          exitId: '',
          type: 'WHEELCHAIR_LIFT',
          name: '장애인 휠체어 리프트 1호기',
          floorFrom: 'B1',
          floorTo: 'B2',
          description: '승강장 이동용',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-09-09',
        ),
        StationFacilityInfo(
          id: 'facility-toilet-1',
          stationId: 'station-geumnamno-4ga',
          exitId: '',
          type: 'TOILET',
          name: '화장실',
          floorFrom: 'B1',
          floorTo: 'B1',
          description: '개찰구 밖 역무실 안내 표지 옆 (1번 출구 대합실 방향)',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-09-09',
        ),
      ],
    );

    expect(_announced('휠체어 리프트 있음'), findsOneWidget);
    expect(find.text('장애인화장실'), findsNothing);
    expect(_announced('장애인화장실 있음'), findsNothing);
    expect(find.text('화장실 개찰구 밖'), findsOneWidget);
    expect(find.text('화장실 개찰구 안/밖'), findsNothing);
    expect(find.text('화장실 개찰구 안'), findsNothing);
  });

  testWidgets('원천 facilityType 코드가 명시된 경우 이름·설명 키워드보다 원천 유형을 최우선으로 판정한다', (
    tester,
  ) async {
    const cases =
        <
          ({
            String name,
            List<StationFacilityInfo> facilities,
            List<String> expectedPresent,
            List<String> expectedAbsentLabels,
            String? expectedReportButtonId,
          })
        >[
          (
            name: 'BICYCLE_RACK 코드는 키워드가 없어도 자전거보관소로 판정',
            facilities: [
              StationFacilityInfo(
                id: 'f-bike-rack',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'BICYCLE_RACK',
                name: '보관대 1호',
                floorFrom: '1F',
                floorTo: '1F',
                description: '1번 출구 옆',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedPresent: ['자전거보관소 있음'],
            expectedAbsentLabels: ['물품보관소', '환승주차장', '유실물센터'],
            expectedReportButtonId: null,
          ),
          (
            name: 'ELEVATOR 설명에 주차장·자전거·보관함이 있어도 다른 시설로 오분류하지 않음',
            facilities: [
              StationFacilityInfo(
                id: 'f-elev-1',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'ELEVATOR',
                name: '승강기 1호기',
                floorFrom: 'B1',
                floorTo: '1F',
                description: '환승 주차장 및 자전거 보관함 연결 통로',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedPresent: ['엘리베이터 있음'],
            expectedAbsentLabels: ['환승주차장', '자전거보관소', '물품보관소'],
            expectedReportButtonId: 'f-elev-1',
          ),
          (
            name: 'ACCESSIBLE_TOILET 코드가 TOILET 키워드 행보다 우선 선택됨',
            facilities: [
              StationFacilityInfo(
                id: 'f-toilet-keyword',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'TOILET',
                name: '장애인 화장실 겸용',
                floorFrom: 'B1',
                floorTo: 'B1',
                description: '개찰구 내',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
              StationFacilityInfo(
                id: 'f-acc-toilet-explicit',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'ACCESSIBLE_TOILET',
                name: '전용 화장실',
                floorFrom: 'B1',
                floorTo: 'B1',
                description: '개찰구 내',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedPresent: ['장애인화장실 있음'],
            expectedAbsentLabels: ['엘리베이터', '휠체어 리프트'],
            expectedReportButtonId: 'f-acc-toilet-explicit',
          ),
          (
            name: 'TOILET 행에 장애인 화장실 이름이 있으면 장애인화장실로 분류',
            facilities: [
              StationFacilityInfo(
                id: 'f-toilet-acc-name',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'TOILET',
                name: '장애인 화장실',
                floorFrom: 'B1',
                floorTo: 'B1',
                description: '개찰구 내',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedPresent: ['장애인화장실 있음'],
            expectedAbsentLabels: ['수유실'],
            expectedReportButtonId: 'f-toilet-acc-name',
          ),
          (
            name: '비명시 유형(OTHER)에서는 주차장 설명·화장실 이름 키워드 폴백이 동작',
            facilities: [
              StationFacilityInfo(
                id: 'f-other-parking',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'OTHER',
                name: '역세권 환승시설',
                floorFrom: '1F',
                floorTo: '1F',
                description: '공영 주차장 연계',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
              StationFacilityInfo(
                id: 'f-other-toilet',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'OTHER',
                name: '공중 화장실',
                floorFrom: 'B1',
                floorTo: 'B1',
                description: '개찰구 안',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedPresent: ['환승주차장 있음'],
            expectedAbsentLabels: ['자전거보관소', '유실물센터'],
            expectedReportButtonId: null,
          ),
        ];

    for (final c in cases) {
      await _pumpDetail(tester, facilities: c.facilities);
      for (final present in c.expectedPresent) {
        expect(_announced(present), findsOneWidget, reason: c.name);
      }
      for (final absent in c.expectedAbsentLabels) {
        expect(find.text(absent), findsNothing, reason: '${c.name} / $absent');
      }
      if (c.expectedReportButtonId != null) {
        expect(
          find.byKey(
            Key('stationFacilityReportButton-${c.expectedReportButtonId}'),
          ),
          findsOneWidget,
          reason: c.name,
        );
      }
    }
  });

  testWidgets('역정보 시설정보 태그 규칙(_TagRule)을 표 기반으로 검증한다', (tester) async {
    const cases =
        <
          ({
            String name,
            List<StationFacilityInfo> facilities,
            List<String> expectedTags,
            List<String> unexpectedTags,
          })
        >[
          (
            name: '단선 플랫폼 키워드와 왼쪽 내리는문, 반대편 이동불가 판정',
            facilities: [
              StationFacilityInfo(
                id: 'f-platform-single',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'PLATFORM',
                name: '승강장',
                floorFrom: 'B2',
                floorTo: 'B2',
                description: '단선 승강장, 내리는문 왼쪽, 반대편 이동불가',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedTags: ['플랫폼 단선', '내리는문 왼쪽', '반대편 이동 불가'],
            unexpectedTags: ['플랫폼 섬식', '플랫폼 양쪽', '내리는문 오른쪽', '반대편 연결됨'],
          ),
          (
            name: '한 텍스트 안에서는 _TagRule 정의 순서대로 뒤 규칙이 앞 규칙을 덮어쓴다',
            facilities: [
              StationFacilityInfo(
                id: 'f-rule-order',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'PLATFORM',
                name: '승강장 안내',
                floorFrom: 'B2',
                floorTo: 'B2',
                description: '단선 구간 및 섬식·상대식 복합, 왼쪽/오른쪽 문, 횡단불가 및 횡단가능',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedTags: ['플랫폼 양쪽', '내리는문 오른쪽', '반대편 연결됨'],
            unexpectedTags: ['플랫폼 단선', '플랫폼 섬식', '내리는문 왼쪽', '반대편 이동 불가'],
          ),
          (
            name: '명시적 PLATFORM 행이 비-PLATFORM 행의 부수 설명보다 우선한다',
            facilities: [
              StationFacilityInfo(
                id: 'f-platform-island',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'PLATFORM',
                name: '승강장',
                floorFrom: 'B2',
                floorTo: 'B2',
                description: '섬식 승강장',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
              StationFacilityInfo(
                id: 'f-elev-later',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'ELEVATOR',
                name: '엘리베이터',
                floorFrom: 'B1',
                floorTo: 'B2',
                description: '상대식 환승 통로 인근',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedTags: ['플랫폼 섬식'],
            unexpectedTags: ['플랫폼 양쪽'],
          ),
          (
            name:
                '화장실 개찰구 안과 개찰구 밖이 모두 확인되면 개찰구 안/밖으로 표시하고 출구 키워드만으로는 판정하지 않는다',
            facilities: [
              StationFacilityInfo(
                id: 'f-toilet-inside',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'TOILET',
                name: '화장실 1',
                floorFrom: 'B1',
                floorTo: 'B1',
                description: '운임구역 내 대합실',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
              StationFacilityInfo(
                id: 'f-toilet-outside',
                stationId: 'station-geumnamno-4ga',
                exitId: '',
                type: 'ACCESSIBLE_TOILET',
                name: '장애인 화장실',
                floorFrom: 'B1',
                floorTo: 'B1',
                description: '게이트 밖 2번 출구 방향',
                status: 'NORMAL',
                dataConfidence: 'HIGH',
                lastUpdatedAt: '2026-09-09',
              ),
            ],
            expectedTags: ['화장실 개찰구 안/밖'],
            unexpectedTags: ['화장실 개찰구 안', '화장실 개찰구 밖'],
          ),
        ];

    for (final c in cases) {
      await _pumpDetail(tester, facilities: c.facilities);
      for (final tag in c.expectedTags) {
        expect(find.text(tag), findsOneWidget, reason: '${c.name} / $tag');
      }
      for (final tag in c.unexpectedTags) {
        expect(find.text(tag), findsNothing, reason: '${c.name} / $tag');
      }
    }
  });
}
