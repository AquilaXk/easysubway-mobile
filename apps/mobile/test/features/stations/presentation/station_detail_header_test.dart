import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const line2 = StationSearchLine(
    id: 'seoul-2',
    name: '2호선',
    color: '#00A84D',
    stationCode: '211',
  );

  const lineBundang = StationSearchLine(
    id: 'suin-bundang',
    name: '수인분당선',
    color: '#FABE00',
    stationCode: 'K210',
  );

  group('StationDetailHeader', () {
    testWidgets('부역명이 없는 단일 노선 역 헤더를 올바르게 렌더링한다', (tester) async {
      const station = StationDetail(
        id: 'station-seongsu',
        nameKo: '성수',
        nameEn: 'Seongsu',
        nameSub: '',
        region: '수도권',
        dataQualityLevel: 'VERIFIED',
        lastVerifiedAt: '2026-08-12T00:00:00Z',
        lines: [line2],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StationDetailHeader(detail: station),
          ),
        ),
      );

      expect(find.text('성수역'), findsOneWidget);
      expect(find.text('2호선'), findsOneWidget);
      expect(find.text('마지막 확인'), findsOneWidget);
    });

    testWidgets('부역명이 있는 환승역 헤더를 부역명 및 다중 노선 라벨과 함께 렌더링한다', (tester) async {
      const station = StationDetail(
        id: 'station-wangsimni',
        nameKo: '왕십리',
        nameEn: 'Wangsimni',
        nameSub: '성동구청',
        region: '수도권',
        dataQualityLevel: 'VERIFIED',
        lastVerifiedAt: '2026-08-12T00:00:00Z',
        lines: [line2, lineBundang],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StationDetailHeader(detail: station),
          ),
        ),
      );

      expect(find.text('왕십리역'), findsOneWidget);
      expect(find.text('성동구청'), findsOneWidget);
      expect(find.text('2호선, 수인분당선'), findsOneWidget);
      expect(find.text('마지막 확인'), findsOneWidget);
    });
  });
}
