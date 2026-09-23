import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/easy_subway_app_fixture.dart';

OnboardingState _completedOnboardingState() {
  return OnboardingState.completed(
    result: OnboardingResult(
      preset: MobilityPreset.slow,
      preferences: const OnboardingViewPreferences.defaults(),
    ),
  );
}

void main() {
  test('AppBootstrap은 isUsingBundledDataPack 플래그를 제공한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = UserDatabase.memory();
    addTearDown(() async {
      await catalogDatabase.close();
      await userDatabase.close();
    });
    final bootstrap = AppBootstrap(
      dependencies: AppDependencies.resolve(
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
        enablePushNotifications: false,
      ),
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      dataPackUpdate: Future<void>.value(),
      resumeDataPackUpdate: () async {},
      acceptMeteredDataPackUpdate: () async {},
      bundledDataPackFreshness: null,
      isUsingBundledDataPack: true,
    );
    expect(bootstrap.isUsingBundledDataPack, isTrue);
  });

  testWidgets('EasySubwayApp은 번들 DB 기동 시 영구 고정 오프라인 경고 배너를 렌더링한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        initialOnboardingState: _completedOnboardingState(),
        isUsingBundledDataPack: true,
      ),
    );
    await tester.pump();

    final bannerFinder = find.byKey(const Key('bundledDataPackOfflineBanner'));
    expect(bannerFinder, findsOneWidget);
    expect(
      find.text(
        '⚠️ 오프라인 모드: 앱에 내장된 초기 노선도를 사용 중입니다. 최신 정보 반영을 위해 네트워크 연결을 확인해주세요.',
      ),
      findsOneWidget,
    );

    final banner = tester.widget<MaterialBanner>(bannerFinder);
    expect(
      banner.backgroundColor,
      EasySubwayAccessibleColors.statusWarningSurface,
    );
  });

  testWidgets('isUsingBundledDataPack이 false이면 오프라인 배너를 렌더링하지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        initialOnboardingState: _completedOnboardingState(),
        isUsingBundledDataPack: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('bundledDataPackOfflineBanner')), findsNothing);
  });
}
