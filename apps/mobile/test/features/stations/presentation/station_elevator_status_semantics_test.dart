import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_facility_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../user_copy_guard.dart';

/// 엘리베이터 가동 상태가 화면 낭독기 라벨로 읽히는지 고정한다(#464).
/// 행 하나가 상태 하나다. 라벨 끝의 `최근 확인 …`은 현재 시각에 따라 달라 패턴으로 확인한다.
class _ElevatorStatusContract {
  const _ElevatorStatusContract(this.status, this.label);

  final String status;
  final Pattern label;
}

final _contracts = <_ElevatorStatusContract>[
  _ElevatorStatusContract(
    'BROKEN',
    RegExp(r'^1번 출구 엘리베이터, 엘리베이터, 이용할 수 없어요, 1번 출구, 최근 확인 .+, 대체 출구 보기$'),
  ),
  _ElevatorStatusContract(
    'NORMAL',
    RegExp(r'^1번 출구 엘리베이터, 엘리베이터, 정상 운행, 1번 출구, 최근 확인 .+, 시설 제보$'),
  ),
];

void main() {
  const station = StationDetail(
    id: 'station-gangnam',
    nameKo: '강남',
    nameEn: 'Gangnam',
    region: '수도권',
    dataQualityLevel: 'VERIFIED',
    lastVerifiedAt: '2026-08-12T00:00:00Z',
    lines: [],
  );

  for (final contract in _contracts) {
    testWidgets('엘리베이터 ${contract.status} 상태가 낭독 라벨로 읽힌다', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StationFacilityCard(
                facility: StationFacilityInfo(
                  id: 'facility-elevator-1',
                  stationId: station.id,
                  exitId: 'exit-1',
                  type: 'ELEVATOR',
                  name: '1번 출구 엘리베이터',
                  floorFrom: 'B1',
                  floorTo: '1F',
                  description: '1번 출구',
                  status: contract.status,
                  dataConfidence: 'HIGH',
                  lastUpdatedAt: '2026-06-12',
                ),
                station: station,
                onReportTap: () {},
              ),
            ),
          ),
        );

        expect(find.bySemanticsLabel(contract.label), findsOneWidget);
        expectNoForbiddenUserCopy(tester);
      } finally {
        semantics.dispose();
      }
    });
  }
}
