import 'dart:async' show unawaited;

import 'package:easysubway_mobile/app/accessibility_theme.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_screen_sweep_fixtures.dart';
import 'journey_result_fixture.dart';
import 'test_viewport.dart';

// 전수 검사 화면 표와 경로 검색 화면 단독 검사가 함께 쓰는 경로 검색 열기 도우미다.
// 화면 표(`core_screen_sweep_screens.dart`)를 통째로 끌어오지 않고 이 화면만 열 수 있다.
const _standardPreferences = OnboardingViewPreferences(
  largeTextEnabled: false,
  highContrastEnabled: false,
  simpleViewEnabled: false,
);

/// 기본 설정으로 전수 검사용 앱을 띄운 뒤 경로 검색 화면을 연다. [taps]의 키를
/// 차례로 누른다(출발 시각 시트 열기, 시트의 막차 칩 등).
Future<void> pumpSweepJourney(
  WidgetTester tester, {
  List<String> taps = const [],
}) async {
  useLogicalViewport(tester, const Size(360, 2000));
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    buildSweepApp(
      navigatorKey: navigatorKey,
      onboardingState: OnboardingState.completed(
        result: OnboardingResult(
          preset: MobilityPreset.standard,
          preferences: _standardPreferences,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openSweepJourney(
    tester: tester,
    navigatorKey: navigatorKey,
    preferences: _standardPreferences,
    search: false,
    taps: taps,
  );
}

/// 이미 떠 있는 앱의 [navigatorKey]로 경로 검색 화면을 연다. [search]면 "경로 찾기"까지
/// 눌러 결과 화면을 연다.
Future<void> openSweepJourney({
  required WidgetTester tester,
  required GlobalKey<NavigatorState> navigatorKey,
  required OnboardingViewPreferences preferences,
  required bool search,
  List<String> taps = const [],
}) async {
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingPreferenceScope(
          preferences: preferences,
          child: JourneySearchScreen(
            repository: FixtureJourneyRepository(),
            attestor: const FixtureIntegrityAttestor(),
            draft: fixtureRouteDraft(),
            mobilityType: 'WHEELCHAIR',
            onShellBackToHome: () {},
            stationNameResolver: fixtureStationName,
            transferGuideRepository: const FixtureTransferGuideRepository(),
            journeyNow: () => DateTime.utc(2026, 8, 12),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (final key in taps) {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }
  if (search) {
    // 큰 글자에서는 시간 줄·걷는 속도가 길어져 버튼이 첫 화면 아래로 내려간다.
    final submit = find.widgetWithText(FilledButton, '경로 찾기');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }
}
