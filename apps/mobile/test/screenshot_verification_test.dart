import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/favorites/favorite_facility.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_menu_panel.dart';
import 'package:easysubway_mobile/features/notifications/notification_settings.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/easy_subway_app_fixture.dart';
import 'support/pretendard_test_font.dart';
import 'widget_test.dart' as wt;

Future<void> _loadTestFonts() async {
  await loadPretendardTestFont();

  const iconFontPaths = [
    '/Volumes/MACSSD/Android/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/Volumes/MACSSD/Android/flutter/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/MaterialIcons-Regular.otf',
  ];

  for (final path in iconFontPaths) {
    final file = File(path);
    if (file.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
      await loader.load();
      break;
    }
  }
}

Future<void> _captureBoundaryToFile(
  WidgetTester tester,
  GlobalKey key,
  String filePath,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    File(filePath).writeAsBytesSync(byteData!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadTestFonts();
  });

  testWidgets('메인 화면 스크린샷 캡처 (알림 좌측, 메뉴 우측)', (tester) async {
    final screenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notificationRepository = wt.FakeNotificationSettingsRepository();

    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: buildEasySubwayTestApp(
          repository: wt.FakeStationSearchRepository(),
          reportRepository: wt.FakeFacilityReportRepository(),
          favoriteRepository: wt.FakeFavoriteStationRepository(),
          favoriteFacilityRepository: wt.FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: wt.FakeFavoriteRouteRepository(),
          notificationRepository: notificationRepository,
          initialOnboardingState: const OnboardingState.completed(
            result: OnboardingResult(
              preset: MobilityPreset.slow,
              preferences: OnboardingViewPreferences.defaults(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _captureBoundaryToFile(
      tester,
      screenshotKey,
      '/tmp/screenshot_main_screen.png',
    );
  });

  testWidgets('메인 화면 스크린샷 캡처 (알림 배지 활성화 상태)', (tester) async {
    final badgeScreenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const facilityWithIssue = FavoriteFacility(
      userId: 'test-user',
      facilityId: 'facility-sangnoksu-elevator-1',
      stationId: 'station-sangnoksu',
      stationNameKo: '상록수',
      stationNameEn: 'Sangnoksu',
      exitId: 'exit-sangnoksu-1',
      type: 'ELEVATOR',
      name: '1번 출구 엘리베이터',
      floorFrom: '지상',
      floorTo: '대합실',
      description: '1번 출구 앞',
      status: 'USER_REPORTED',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-09-24',
      addedAt: '2026-09-24T00:00:00Z',
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: badgeScreenshotKey,
        child: buildEasySubwayTestApp(
          repository: wt.FakeStationSearchRepository(),
          reportRepository: wt.FakeFacilityReportRepository(),
          favoriteRepository: wt.FakeFavoriteStationRepository(),
          favoriteFacilityRepository: wt.FakeFavoriteFacilityRepository(
            favorites: const [facilityWithIssue],
          ),
          favoriteRouteRepository: wt.FakeFavoriteRouteRepository(),
          notificationRepository: wt.FakeNotificationSettingsRepository(),
          initialOnboardingState: const OnboardingState.completed(
            result: OnboardingResult(
              preset: MobilityPreset.slow,
              preferences: OnboardingViewPreferences.defaults(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _captureBoundaryToFile(
      tester,
      badgeScreenshotKey,
      '/tmp/screenshot_main_screen_with_badge.png',
    );
  });

  testWidgets('우측 메뉴 패널 스크린샷 캡처 (오른쪽 정렬)', (tester) async {
    final screenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Pretendard',
            colorScheme: ColorScheme.fromSeed(
              seedColor: EasySubwayAccessibleColors.primary,
            ),
          ),
          home: Scaffold(
            backgroundColor: const Color(0x99000000),
            body: Align(
              alignment: Alignment.centerRight,
              child: NetworkMapMenuPanel(
                bottomBanner: const SizedBox(
                  key: Key('networkMapMenuAdBanner'),
                  height: 50,
                ),
                onOpenStationSearch: () {},
                onOpenSavedItems: () {},
                onOpenTrainSearch: () {},
                onOpenServiceNotices: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _captureBoundaryToFile(
      tester,
      screenshotKey,
      '/tmp/screenshot_menu_panel_right.png',
    );
  });

  testWidgets('알림 설정 화면 스크린샷 캡처 (마스터 토글 ON / OFF)', (tester) async {
    final settingsScreenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notificationRepository = wt.FakeNotificationSettingsRepository();

    await tester.pumpWidget(
      RepaintBoundary(
        key: settingsScreenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Pretendard',
            colorScheme: ColorScheme.fromSeed(
              seedColor: EasySubwayAccessibleColors.primary,
            ),
          ),
          home: NotificationSettingsScreen(repository: notificationRepository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _captureBoundaryToFile(
      tester,
      settingsScreenshotKey,
      '/tmp/screenshot_notification_settings.png',
    );

    // 마스터 토글 끄기 -> 하위 토글 비활성화/딤 처리 확인용 스크린샷
    await tester.tap(
      find.byKey(const Key('notificationSwitch-masterPushAlerts')),
    );
    await tester.pumpAndSettle();

    await _captureBoundaryToFile(
      tester,
      settingsScreenshotKey,
      '/tmp/screenshot_notification_settings_disabled.png',
    );
  });
}
