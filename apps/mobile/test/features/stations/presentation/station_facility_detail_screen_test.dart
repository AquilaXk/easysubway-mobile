import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_facility_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FacilityDetailScreen은 UNKNOWN 상태 시 중복 상태 문구를 표시하지 않는다', (
    tester,
  ) async {
    const facility = StationFacilityInfo(
      id: 'facility-sangnoksu-unknown-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-sangnoksu-1',
      type: 'ELEVATOR',
      name: '1번 출구 엘리베이터',
      floorFrom: 'B1',
      floorTo: '1F',
      description: '1번 출구 앞',
      status: 'UNKNOWN',
      dataConfidence: 'LOW',
      lastUpdatedAt: '2026-06-12',
    );

    const station = StationDetail(
      id: 'station-sangnoksu',
      nameKo: '상록수',
      nameEn: 'Sangnoksu',
      region: '수도권',
      dataQualityLevel: 'VERIFIED',
      lastVerifiedAt: '2026-08-12T00:00:00Z',
      lines: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityDetailScreen(
          station: station,
          facility: facility,
          onReportTap: () {},
        ),
      ),
    );

    // 상태 타이틀이 정확히 1번만 노출되어야 한다.
    expect(find.text('설치 확인 · 운행상태 미확인'), findsOneWidget);
    // 중복되던 보조 라벨 '미확인 · 설치 확인 · 운행상태 미확인'은 노출되지 않아야 한다.
    expect(find.text('미확인 · 설치 확인 · 운행상태 미확인'), findsNothing);

    // Semantics에서도 중복 없이 단일 상태 문구만 포함해야 한다.
    final statusNoticeFinder = find.byKey(
      const Key('facilityDetailStatusNotice-facility-sangnoksu-unknown-1'),
    );
    expect(statusNoticeFinder, findsOneWidget);
    final semantics = tester.getSemantics(statusNoticeFinder);
    expect(semantics.label, '설치 확인 · 운행상태 미확인, 현장 안내와 다르면 시설 제보로 알려 주세요.');
  });

  testWidgets('FacilityDetailScreen은 BROKEN 상태 시 중복 상태 문구를 표시하지 않는다', (
    tester,
  ) async {
    const facility = StationFacilityInfo(
      id: 'facility-sangnoksu-broken-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-sangnoksu-1',
      type: 'ELEVATOR',
      name: '1번 출구 엘리베이터',
      floorFrom: 'B1',
      floorTo: '1F',
      description: '1번 출구 앞',
      status: 'BROKEN',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-06-12',
    );

    const station = StationDetail(
      id: 'station-sangnoksu',
      nameKo: '상록수',
      nameEn: 'Sangnoksu',
      region: '수도권',
      dataQualityLevel: 'VERIFIED',
      lastVerifiedAt: '2026-08-12T00:00:00Z',
      lines: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityDetailScreen(
          station: station,
          facility: facility,
          onReportTap: () {},
        ),
      ),
    );

    // 상태 타이틀 확인
    expect(find.text('이용할 수 없어요'), findsOneWidget);
    // 중복되던 보조 라벨 '고장·폐쇄 · 고장'은 노출되지 않아야 한다.
    expect(find.text('고장·폐쇄 · 고장'), findsNothing);
  });
}
