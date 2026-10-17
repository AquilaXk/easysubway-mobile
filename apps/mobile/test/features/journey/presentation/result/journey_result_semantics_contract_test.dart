import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/journey_result_fixture.dart';
import '../../../../user_copy_guard.dart';

/// 길안내 결과의 접근성 상태·엘리베이터 안내·환승 안내가 화면 낭독기 라벨로
/// 읽히는지 고정한다(#464). 행 하나가 낭독기 계약 하나다.
class _SemanticsContract {
  const _SemanticsContract(
    this.name, {
    required this.labels,
    this.stairFreeAlternative = _stairFreeIncluded,
    this.expandTransferGuide = false,
  });

  final String name;

  /// `find.bySemanticsLabel`로 정확히 하나가 있어야 하는 낭독 문구.
  final List<String> labels;
  final JourneyStairFreeAlternative stairFreeAlternative;
  final bool expandTransferGuide;
}

const _stairFreeIncluded = JourneyStairFreeAlternative(
  status: JourneyStairFreeAlternativeStatus.included,
  facilityStatus: JourneyStairFreeFacilityStatus.applied,
);

const _stairFreeNotFound = JourneyStairFreeAlternative(
  status: JourneyStairFreeAlternativeStatus.notFound,
  facilityStatus: JourneyStairFreeFacilityStatus.applied,
);

final _contracts = <_SemanticsContract>[
  const _SemanticsContract(
    '경로 접근성 상태: 계단 없는 경로가 탭과 요약에서 읽힌다',
    labels: [
      '빠른 경로, 계단 없는 경로, 35분, 환승 1회, 09:35 도착',
      '환승 적은 경로, 41분, 환승 1회, 09:41 도착',
      '계단 없는 경로',
    ],
  ),
  const _SemanticsContract(
    '경로 접근성 상태: 계단 없는 경로가 없으면 이유가 읽힌다',
    stairFreeAlternative: _stairFreeNotFound,
    labels: ['계단 없이 갈 수 있는 경로가 없어요. 찾은 경로는 모두 환승할 때 계단을 지나요.'],
  ),
  const _SemanticsContract(
    '엘리베이터 안내: 엘리베이터와 가까운 하차 칸·문이 탑승 안내에서 읽힌다',
    labels: [
      '2호선 교대 방면 탑승, 09:03 출발, 빠른 환승 3호차 2번 문, '
          '엘리베이터 가까운 4호차 1번 문, 2개 역 이동, 12분',
    ],
  ),
  _SemanticsContract(
    '환승 안내: 환승역과 도보 시간, 펼친 이동 방법이 읽힌다',
    expandTransferGuide: true,
    labels: ['교대 환승, 도보 3분', '이동 방법 3단계', ...fixtureTransferGuideSteps],
  ),
];

void main() {
  for (final contract in _contracts) {
    testWidgets(contract.name, (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(1080, 6000);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: JourneySearchScreen(
              repository: FixtureJourneyRepository(
                stairFreeAlternative: contract.stairFreeAlternative,
              ),
              attestor: const FixtureIntegrityAttestor(),
              draft: fixtureRouteDraft(),
              mobilityType: 'WHEELCHAIR',
              onShellBackToHome: () {},
              stationNameResolver: fixtureStationName,
              transferGuideRepository: const FixtureTransferGuideRepository(),
              journeyNow: () => DateTime.utc(2026, 8, 12),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
        await tester.pumpAndSettle();
        if (contract.expandTransferGuide) {
          await tester.tap(
            find.byKey(const Key('journey-transfer-guide-toggle-2')),
          );
          await tester.pumpAndSettle();
        }

        for (final label in contract.labels) {
          expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
        }
        expectNoForbiddenUserCopy(tester);
      } finally {
        semantics.dispose();
      }
    });
  }
}
