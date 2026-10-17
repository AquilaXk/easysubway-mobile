import 'dart:async';

import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/easy_subway_app_fixture.dart';

const _koreanLocale = Locale('ko', 'KR');
const _pushedScreenKey = Key('localizationProbeScreen');

OnboardingState _completedOnboardingState() {
  return OnboardingState.completed(
    result: OnboardingResult(
      preset: MobilityPreset.slow,
      preferences: const OnboardingViewPreferences.defaults(),
    ),
  );
}

/// 앱 루트 navigator 위에 AppBar 화면을 올려 기본 뒤로가기 버튼을 만든다.
Future<BuildContext> _pumpPushedScreen(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    buildEasySubwayTestApp(
      initialOnboardingState: _completedOnboardingState(),
      navigatorKey: navigatorKey,
    ),
  );
  await tester.pump();

  unawaited(
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          key: _pushedScreenKey,
          appBar: AppBar(title: const Text('probe')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.byKey(_pushedScreenKey));
}

void main() {
  testWidgets('MaterialLocalizations가 기기 언어와 무관하게 한국어다', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final context = await _pumpPushedScreen(tester);

    expect(Localizations.localeOf(context), _koreanLocale);
    expect(MaterialLocalizations.of(context).backButtonTooltip, '뒤로');
  });

  testWidgets('뒤로가기 버튼의 툴팁과 semantics 라벨이 한국어로 낭독된다', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final semantics = tester.ensureSemantics();

    await _pumpPushedScreen(tester);

    expect(find.byTooltip('뒤로'), findsOneWidget);
    expect(
      tester.getSemantics(find.byTooltip('뒤로')),
      matchesSemantics(
        label: '뒤로',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        tooltip: '뒤로',
      ),
    );
    semantics.dispose();
  });
}
