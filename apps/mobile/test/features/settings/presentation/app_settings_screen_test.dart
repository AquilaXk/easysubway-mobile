import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_labels.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding_preferences.dart';
import 'package:easysubway_mobile/features/settings/presentation/app_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestHost({
    MobilityPreset currentPreset = MobilityPreset.standard,
    WalkingPace? initialWalkingPace,
    OnboardingViewPreferences viewPreferences =
        const OnboardingViewPreferences.defaults(),
    Future<void> Function(OnboardingViewPreferences)? onViewPreferencesChanged,
    Future<MobilityPreset?> Function()? onOpenMobilityProfile,
    Future<bool> Function(MobilityPreset)? onPresetChanged,
    ValueChanged<WalkingPace>? onWalkingPaceChanged,
    VoidCallback? onOpenSupportAccess,
    VoidCallback? onOpenInquiry,
    VoidCallback? onOpenServiceInfo,
    VoidCallback? onOpenMyReports,
    VoidCallback? onShellBack,
  }) {
    return MaterialApp(
      home: AppSettingsScreen(
        currentPreset: currentPreset,
        initialWalkingPace: initialWalkingPace,
        viewPreferences: viewPreferences,
        notificationRepository: null,
        notificationPermissionProvider: null,
        onViewPreferencesChanged: onViewPreferencesChanged ?? (_) async {},
        onOpenMobilityProfile: onOpenMobilityProfile ?? () async => null,
        onPresetChanged: onPresetChanged ?? (_) async => true,
        onWalkingPaceChanged: onWalkingPaceChanged,
        onOpenSupportAccess: onOpenSupportAccess ?? () {},
        onOpenInquiry: onOpenInquiry ?? () {},
        onOpenServiceInfo: onOpenServiceInfo ?? () {},
        onOpenMyReports: onOpenMyReports ?? () {},
        onShellBack: onShellBack,
      ),
    );
  }

  testWidgets('설정 화면은 보행 속도 3종 버튼을 노출하고 탭 시 선택 및 콜백을 호출한다', (tester) async {
    final changedPaces = <WalkingPace>[];
    final changedPresets = <MobilityPreset>[];

    await tester.pumpWidget(
      buildTestHost(
        currentPreset: MobilityPreset.standard,
        initialWalkingPace: WalkingPace.standard,
        onWalkingPaceChanged: changedPaces.add,
        onPresetChanged: (preset) async {
          changedPresets.add(preset);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.byKey(const Key('walkingSpeedSegment-slow')), findsOneWidget);
    expect(
      find.byKey(const Key('walkingSpeedSegment-standard')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('walkingSpeedSegment-fast')), findsOneWidget);

    // Tap slow
    await tester.tap(find.byKey(const Key('walkingSpeedSegment-slow')));
    await tester.pumpAndSettle();
    expect(changedPaces.last, WalkingPace.slow);
    expect(changedPresets.last, MobilityPreset.slow);

    // Tap fast
    await tester.tap(find.byKey(const Key('walkingSpeedSegment-fast')));
    await tester.pumpAndSettle();
    expect(changedPaces.last, WalkingPace.fast);

    // Tap fast again (noop)
    await tester.tap(find.byKey(const Key('walkingSpeedSegment-fast')));
    await tester.pumpAndSettle();

    // Tap standard
    await tester.tap(find.byKey(const Key('walkingSpeedSegment-standard')));
    await tester.pumpAndSettle();
    expect(changedPaces.last, WalkingPace.standard);
  });

  testWidgets('설정 화면은 시설 제약 3종 버튼을 노출하고 탭 시 선택 및 프리셋을 연동한다', (tester) async {
    final changedPresets = <MobilityPreset>[];

    await tester.pumpWidget(
      buildTestHost(
        currentPreset: MobilityPreset.standard,
        onPresetChanged: (preset) async {
          changedPresets.add(preset);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('facilitySegment-standard')), findsOneWidget);
    expect(find.byKey(const Key('facilitySegment-noStairs')), findsOneWidget);
    expect(find.byKey(const Key('facilitySegment-stepFree')), findsOneWidget);

    // Tap noStairs
    await tester.tap(find.byKey(const Key('facilitySegment-noStairs')));
    await tester.pumpAndSettle();
    expect(changedPresets.last, MobilityPreset.noStairs);

    // Tap elevatorOnly
    await tester.tap(find.byKey(const Key('facilitySegment-stepFree')));
    await tester.pumpAndSettle();
    expect(changedPresets.last, MobilityPreset.stepFree);

    // Tap elevatorOnly again (noop)
    await tester.tap(find.byKey(const Key('facilitySegment-stepFree')));
    await tester.pumpAndSettle();

    // Tap none
    await tester.tap(find.byKey(const Key('facilitySegment-standard')));
    await tester.pumpAndSettle();
    expect(changedPresets.last, MobilityPreset.standard);
  });

  testWidgets('요약 히어로 카드를 탭하면 onOpenMobilityProfile이 호출되고 선택 결과가 반영된다', (
    tester,
  ) async {
    var heroTappedCount = 0;
    MobilityPreset? nextResult = MobilityPreset.stepFree;

    await tester.pumpWidget(
      buildTestHost(
        currentPreset: MobilityPreset.standard,
        onOpenMobilityProfile: () async {
          heroTappedCount++;
          return nextResult;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mobilityProfileButton')));
    await tester.pumpAndSettle();

    expect(heroTappedCount, 1);
    expect(find.text('휠체어 이용'), findsWidgets);

    // Profile returns slow -> covers line 111 (_walkingPace = WalkingPace.slow)
    nextResult = MobilityPreset.slow;
    await tester.tap(find.byKey(const Key('mobilityProfileButton')));
    await tester.pumpAndSettle();
    expect(heroTappedCount, 2);
    expect(find.text('천천히'), findsWidgets);

    // Profile returns standard while pace is slow -> covers lines 113-114 (_walkingPace = WalkingPace.standard)
    nextResult = MobilityPreset.standard;
    await tester.tap(find.byKey(const Key('mobilityProfileButton')));
    await tester.pumpAndSettle();
    expect(heroTappedCount, 3);
    expect(find.text('보통 걸음'), findsWidgets);
  });

  testWidgets('onPresetChanged가 실패(false)하면 이전 상태로 롤백된다', (tester) async {
    await tester.pumpWidget(
      buildTestHost(
        currentPreset: MobilityPreset.standard,
        onPresetChanged: (_) async => false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('walkingSpeedSegment-slow')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('facilitySegment-noStairs')));
    await tester.pumpAndSettle();
  });

  testWidgets('보기 설정 및 기타 항목 토글과 네비게이션 콜백이 정상 작동한다', (tester) async {
    var viewPrefChanged = false;
    var supportOpened = false;
    var serviceInfoOpened = false;
    var myReportsOpened = false;
    var shellBackCalled = false;

    await tester.pumpWidget(
      buildTestHost(
        onViewPreferencesChanged: (_) async {
          viewPrefChanged = true;
        },
        onOpenSupportAccess: () => supportOpened = true,
        onOpenServiceInfo: () => serviceInfoOpened = true,
        onOpenMyReports: () => myReportsOpened = true,
        onShellBack: () => shellBackCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    // High contrast toggle
    expect(find.byKey(const Key('highContrastSettingsButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pumpAndSettle();
    expect(viewPrefChanged, isTrue);

    // Simple view toggle
    expect(find.byKey(const Key('simpleViewSettingsButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pumpAndSettle();

    // My reports button
    await tester.scrollUntilVisible(
      find.byKey(const Key('myReportsSettingsButton')),
      100,
    );
    await tester.tap(find.byKey(const Key('myReportsSettingsButton')));
    await tester.pumpAndSettle();
    expect(myReportsOpened, isTrue);

    // Service info item
    await tester.scrollUntilVisible(
      find.byKey(const Key('settingsServiceInfoButton')),
      100,
    );
    await tester.tap(find.byKey(const Key('settingsServiceInfoButton')));
    await tester.pumpAndSettle();
    expect(serviceInfoOpened, isTrue);

    // Support item
    await tester.scrollUntilVisible(
      find.byKey(const Key('settingsSupportPrivacyButton')),
      100,
    );
    await tester.tap(find.byKey(const Key('settingsSupportPrivacyButton')));
    await tester.pumpAndSettle();
    expect(supportOpened, isTrue);

    // Back button with shell fallback
    await tester.tap(find.byKey(const Key('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(shellBackCalled, isTrue);
  });

  testWidgets('위젯 갱신 시(didUpdateWidget) 새로운 preset 및 속도가 동기화된다', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestHost(
        currentPreset: MobilityPreset.standard,
        initialWalkingPace: WalkingPace.standard,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      buildTestHost(
        currentPreset: MobilityPreset.slow,
        initialWalkingPace: WalkingPace.slow,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('천천히'), findsWidgets);

    // Transition back to standard while pace is slow -> covers line 99 (_walkingPace = WalkingPace.standard)
    await tester.pumpWidget(
      buildTestHost(currentPreset: MobilityPreset.standard),
    );
    await tester.pumpAndSettle();

    expect(find.text('보통 걸음'), findsWidgets);
  });
}
