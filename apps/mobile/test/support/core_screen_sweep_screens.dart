// 핵심 화면 접근성 전수 검사의 화면 표. 화면은 [sweepScreens]의 한 줄로 추가한다.
import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:io' show File;

import 'package:easysubway_mobile/app/accessibility_theme.dart';
import 'package:easysubway_mobile/core/error/error_feedback.dart';
import 'package:easysubway_mobile/core/ui/region_menu.dart';
import 'package:easysubway_mobile/features/attribution/presentation/data_source_attribution_screen.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_target.dart';
import 'package:easysubway_mobile/features/facility_report/presentation/facility_report_screen.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/notifications/notification_settings.dart';
import 'package:easysubway_mobile/features/notifications/presentation/notification_inbox_screen.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_screen_sweep_fixtures.dart';
import 'journey_result_fixture.dart';

/// 앱에 다크 테마는 없다(`darkTheme` 미정의). 시스템 다크 모드에서도 같은
/// 테마로 그려지는지 `systemDark` 조합으로 함께 검사해, 다크 테마를 도입하면
/// 이 표가 바로 새 테마를 검사하게 한다.
enum SweepTheme {
  standard('기본 테마'),
  highContrast('고대비'),
  systemDark('시스템 다크 모드');

  const SweepTheme(this.label);

  final String label;

  OnboardingViewPreferences get preferences => OnboardingViewPreferences(
    largeTextEnabled: false,
    highContrastEnabled: this == highContrast,
    simpleViewEnabled: false,
  );

  Brightness get platformBrightness =>
      this == systemDark ? Brightness.dark : Brightness.light;
}

class SweepScreenContext {
  const SweepScreenContext({
    required this.tester,
    required this.navigatorKey,
    required this.theme,
    this.onDevice = false,
  });

  final WidgetTester tester;
  final GlobalKey<NavigatorState> navigatorKey;
  final SweepTheme theme;

  /// 에뮬레이터 실기에서 열면 true. 호스트와 달리 번들 asset을 비동기로 읽어도 테스트 시계가 끝난다.
  final bool onDevice;

  BuildContext get navigatorContext => navigatorKey.currentContext!;
}

class SweepScreen {
  const SweepScreen(
    this.name,
    this.open,
    this.shown, {
    this.stationResults = const [],
    this.onboarded = true,
    this.inboxLoad = SweepInboxLoad.normal,
  });

  final String name;
  final Future<void> Function(SweepScreenContext context) open;

  /// 화면이 실제로 열렸음을 보이는 요소. 열리지 않은 화면이 가이드라인을
  /// 통과하는 일을 막는다.
  final Finder shown;

  /// 역 검색 포트가 돌려줄 결과. 지도에서 역을 누르면 같은 포트로 역 정보 패널을
  /// 함께 여므로, 팬 메뉴 행은 비워 두어 팬 메뉴만 검사한다.
  final List<StationSearchResult> stationResults;

  /// false면 온보딩을 마치지 않은 첫 실행 상태로 앱을 연다.
  final bool onboarded;

  /// 알림함이 읽는 시설·제보 조회의 성공·실패 조합.
  final SweepInboxLoad inboxLoad;

  OnboardingState onboardingState(SweepTheme theme) => onboarded
      ? OnboardingState.completed(
          result: OnboardingResult(
            preset: MobilityPreset.standard,
            preferences: theme.preferences,
          ),
        )
      : const OnboardingState.initial();
}

/// 검사 대상 화면 표.
final sweepScreens = <SweepScreen>[
  SweepScreen(
    '홈(노선도)',
    (context) async {},
    find.byKey(const Key('networkMapMenuButton')),
  ),
  SweepScreen('좌측 메뉴', _openMenu, find.byKey(const Key('networkMapMenuPanel'))),
  SweepScreen(
    '경로 검색',
    (context) => _openJourney(context, search: false),
    find.widgetWithText(FilledButton, '경로 찾기'),
  ),
  SweepScreen(
    '경로 결과·상세',
    (context) => _openJourney(context, search: true),
    find.byKey(const Key('selected-journey-detail')),
  ),
  SweepScreen(
    '역 상세(출구 지도 안내)',
    _openStationDetail,
    find.byKey(const Key('stationExitMapPreview')),
  ),
  SweepScreen('설정', _openSettings, find.byKey(const Key('settingsScreen'))),
  SweepScreen(
    '역 검색',
    _openStationSearch,
    find.byKey(const Key('stationSearchScreen')),
  ),
  SweepScreen(
    '역 검색 결과',
    _openStationSearchResults,
    find.byKey(Key('stationSearchResult-$sweepStationId-seoul-2')),
    stationResults: [sweepSearchResult, sweepSecondSearchResult],
  ),
  SweepScreen(
    '역 시간표',
    _openStationTimetable,
    find.byKey(const Key('stationTimetableDay-weekday')),
  ),
  SweepScreen(
    '서비스 정보',
    (context) => _openSettingsEntry(context, _settingsServiceInfoKey),
    find.byKey(const Key('serviceInfoScreen')),
  ),
  SweepScreen(
    '데이터 출처',
    _openDataSourceAttribution,
    find.byKey(const Key('dataSourceAttributionScreen')),
  ),
  SweepScreen(
    '오픈소스 라이선스',
    (context) =>
        _openServiceInfoEntry(context, const Key('openSourceLicensesItem')),
    find.byKey(const Key('openSourceLicensesScreen')),
  ),
  SweepScreen(
    '도움말',
    (context) =>
        _openSettingsEntry(context, const Key('settingsSupportPrivacyButton')),
    find.byKey(const Key('supportAccessScreen')),
  ),
  SweepScreen(
    '문의',
    (context) =>
        _openSettingsEntry(context, const Key('settingsInquiryButton')),
    find.byKey(const Key('inquiryScreen')),
  ),
  SweepScreen(
    '알림 설정',
    (context) =>
        _openSettingsEntry(context, const Key('notificationSettingsButton')),
    find.byType(NotificationSettingsScreen),
  ),
  SweepScreen(
    '알림함',
    (context) => _openMenuEntry(context, 'networkMapMenuNotificationsButton'),
    find.byType(NotificationInboxScreen),
  ),
  SweepScreen(
    '알림함(조회 실패)',
    (context) => _openMenuEntry(context, 'networkMapMenuNotificationsButton'),
    find.byKey(const Key('notificationInboxErrorState')),
    inboxLoad: SweepInboxLoad.failedNoItems,
  ),
  SweepScreen(
    '알림함(부분 조회 실패)',
    (context) => _openMenuEntry(context, 'networkMapMenuNotificationsButton'),
    find.byKey(const Key('notificationInboxReportErrorRow')),
    inboxLoad: SweepInboxLoad.reportsFailed,
  ),
  SweepScreen(
    '내 제보',
    (context) =>
        _openSettingsEntry(context, const Key('myReportsSettingsButton')),
    find.byKey(const Key('myReportsScreen')),
  ),
  SweepScreen(
    '즐겨찾기',
    (context) => _openMenuEntry(context, 'networkMapMenuSavedButton'),
    find.byKey(const Key('favoriteHomeScreen')),
  ),
  SweepScreen(
    '공지사항',
    (context) => _openMenuEntry(context, 'networkMapMenuServiceNoticesButton'),
    find.byKey(const Key('serviceNoticeAppBar')),
  ),
  SweepScreen(
    '시작 화면',
    (context) async {},
    find.byKey(const Key('startScreenStartButton')),
    onboarded: false,
  ),
  SweepScreen(
    '온보딩',
    (context) async {
      await context.tester.tap(find.byKey(const Key('startScreenStartButton')));
      await context.tester.pumpAndSettle();
    },
    find.byType(OnboardingScreen),
    onboarded: false,
  ),
  SweepScreen(
    '기차 조회',
    (context) => _openMenuEntry(context, 'networkMapMenuTrainSearchButton'),
    find.byKey(const Key('trainSearchScrollView')),
  ),
  SweepScreen(
    '제보 작성',
    _openFacilityReport,
    find.byKey(const Key('facilityReportScreen')),
  ),
  SweepScreen('제보 상세', (context) async {
    await _openSettingsEntry(context, const Key('myReportsSettingsButton'));
    await context.tester.tap(find.byKey(const Key('myReport-report-1')));
    await context.tester.pumpAndSettle();
  }, find.byKey(const Key('myReportDetailScreen'))),
  SweepScreen('지역 메뉴', (context) async {
    await context.tester.tap(find.byKey(const Key('networkMapRegionDropdown')));
    await context.tester.pumpAndSettle();
  }, find.byType(EasySubwayRegionMenuPanel)),
  SweepScreen(
    '지도 역 정보 패널',
    _openFanMenu,
    find.byKey(const Key('networkMapNearbyStationPanel')),
    stationResults: [sweepSearchResult],
  ),
  SweepScreen(
    '지도 역 정보 패널(상세 펼침)',
    (context) async {
      await _openFanMenu(context);
      await context.tester.tap(
        find.byKey(const Key('nearbyStationLineBarStationName')),
      );
      await context.tester.pumpAndSettle();
    },
    find.byKey(const Key('networkMapNearbyStationPanelExpanded')),
    stationResults: [sweepSearchResult],
  ),
  SweepScreen(
    '보행 프로필 선택',
    (context) =>
        _openSettingsEntry(context, const Key('mobilityProfileButton')),
    find.byKey(const Key('presetSheetDragHandle')),
  ),
  SweepScreen(
    '사용자 정보 삭제',
    _openUserDataDeletion,
    find.byKey(const Key('userDataDeletionScreen')),
  ),
  SweepScreen('사용자 정보 삭제 확인 창', (context) async {
    await _openUserDataDeletion(context);
    await context.tester.tap(find.byKey(const Key('dataDeletionStartButton')));
    await context.tester.pumpAndSettle();
  }, find.byKey(const Key('dataDeletionConfirmButton'))),
  SweepScreen('시설 상세', (context) async {
    await _openStationDetail(context);
    // 큰 글자에서는 시설 카드가 화면 밖에 있어 지연 생성 목록을 스크롤해 연다.
    final card = find.byKey(
      const Key('stationFacilityCard-facility-elevator-1'),
    );
    await scrollStationDetailTo(context.tester, card);
    await context.tester.ensureVisible(card);
    await context.tester.pumpAndSettle();
    await context.tester.tap(card);
    await context.tester.pumpAndSettle();
  }, find.byKey(const Key('facilityDetailAppBar'))),
  SweepScreen('오류 참조 번호 시트', (context) async {
    unawaited(
      showErrorReferenceSheet(
        context.navigatorContext,
        message: '잠시 후 다시 시도해 주세요.',
        correlationId: 'req-20261018-0001',
      ),
    );
    await context.tester.pumpAndSettle();
  }, find.byKey(const Key('errorReferenceExpansion'))),
  SweepScreen('지도 역 팬 메뉴', _openFanMenu, find.byType(StationFanMenu)),
  // 역을 지정하면 상단바가 경로 입력 칸으로 바뀌므로 이 행들은 그 상단바도 함께 검사한다.
  for (final role in _fanMenuRoles)
    SweepScreen(
      '지도 역 팬 메뉴(${role.name} 지정됨, 경로 입력 상단바)',
      (context) async {
        await _openFanMenuWithSelected(context, role);
        _expectNoticeBarBelowTopBar(context.tester);
      },
      // 그 역할 칸이 채워져 지우기 버튼이 있어야 지정이 실제로 일어난 것이다.
      find.byKey(role.clearKey),
    ),
  SweepScreen('경로 입력 상단바(경유 포함 3줄) + 알림 바', (context) async {
    await _selectFanMenuRole(context, _waypointRole);
    _expectNoticeBarBelowTopBar(context.tester);
  }, find.byKey(_waypointRole.clearKey)),
];

/// 팬 메뉴 섹터. 낭독 라벨로 섹터를 눌러 지정 상태를 만든다.
class _FanMenuRole {
  const _FanMenuRole(this.slot, this.name, this.semanticsLabel, this.clearKey);

  final RouteDraftSlot slot;
  final String name;
  final String semanticsLabel;

  /// 경로 입력 상단바에서 이 역할 칸의 지우기 버튼.
  final Key clearKey;
}

const _waypointRole = _FanMenuRole(
  RouteDraftSlot.waypoint,
  '경유',
  '경유지로 추가',
  Key('networkMapRouteDraftClearWaypoint'),
);

const _fanMenuRoles = <_FanMenuRole>[
  _FanMenuRole(
    RouteDraftSlot.origin,
    '출발',
    '출발역으로 설정',
    Key('networkMapRouteDraftClearOrigin'),
  ),
  _waypointRole,
  _FanMenuRole(
    RouteDraftSlot.destination,
    '도착',
    '도착역으로 설정',
    Key('networkMapRouteDraftClearDestination'),
  ),
];

const _sweepMapStationKey = Key('networkMapStation-gangnam-seoul-2');

/// 지도의 역을 눌러 팬 메뉴를 연다. 지도는 탭 좌표를 캔버스 제스처에서 역으로
/// 해석하므로 히트 타깃 위젯이 직접 맞지 않아도 정상이다.
Future<void> _openFanMenu(SweepScreenContext context) async {
  await context.tester.tap(
    find.byKey(_sweepMapStationKey),
    warnIfMissed: false,
  );
  await context.tester.pumpAndSettle();
}

/// 알림 바가 보이고, 경로 입력 상단바와 세로로 겹치지 않는지 단언한다.
void _expectNoticeBarBelowTopBar(WidgetTester tester) {
  final noticeBar = find.byKey(const Key('newNotificationBar'));
  expect(noticeBar, findsOneWidget);
  final topBarRect = tester.getRect(find.byKey(const Key('networkMapTopBar')));
  final noticeBarRect = tester.getRect(noticeBar);
  expect(
    topBarRect.overlaps(noticeBarRect),
    isFalse,
    reason: '알림 바 $noticeBarRect가 경로 입력 상단바 $topBarRect를 가립니다.',
  );
}

/// 팬 메뉴를 열고 낭독 기술이 쓰는 접근성 탭으로 [role]에 역을 지정한다. 지정하면
/// 상단바가 경로 입력 칸으로 바뀐다.
Future<void> _selectFanMenuRole(
  SweepScreenContext context,
  _FanMenuRole role,
) async {
  await _openFanMenu(context);
  context.tester.semantics.tap(find.semantics.byLabel(role.semanticsLabel));
  await context.tester.pumpAndSettle();
}

/// [role]에 역을 지정한 뒤 같은 역을 다시 눌러, 지정된 섹터가 채워진 면으로
/// 그려지는 팬 메뉴를 연다.
Future<void> _openFanMenuWithSelected(
  SweepScreenContext context,
  _FanMenuRole role,
) async {
  await _selectFanMenuRole(context, role);
  await _openFanMenu(context);
  // 다시 연 팬 메뉴가 지정한 역할을 채워진 면으로 그리는지 확인한다.
  expect(
    context.tester
        .widget<StationFanMenu>(find.byType(StationFanMenu))
        .selectedSlots,
    contains(role.slot),
  );
}

/// 출처 화면은 번들 자산을 비동기로 읽는다. 호스트에서는 테스트 시계가 끝나지 않으므로 같은 자산
/// 파일을 동기로 읽어 넘기고, 실기에서는 화면이 자산을 직접 읽도록 하고 읽기가 끝나길 기다린다.
Future<void> _openDataSourceAttribution(SweepScreenContext context) async {
  Map<String, Object?> readAsset(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  final onDevice = context.onDevice;
  unawaited(
    context.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => DataSourceAttributionScreen(
          initialManifest: onDevice
              ? null
              : readAsset('assets/datapacks/metro_map_pack/manifest.json'),
          initialInventory: onDevice
              ? null
              : readAsset('assets/datapacks/source-inventory.json'),
          transferGuideRepository: const FixtureTransferGuideRepository(),
        ),
      ),
    ),
  );
  if (onDevice) {
    // 읽는 동안 진행 표시가 계속 그려지므로 pumpAndSettle은 끝나지 않는다.
    await _pumpUntilGone(
      context.tester,
      find.byType(CircularProgressIndicator),
    );
  } else {
    await context.tester.pumpAndSettle();
  }
}

/// 비동기 읽기가 끝나 [finder]가 사라질 때까지 화면을 다시 그린다.
Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  const step = Duration(milliseconds: 100);
  const limit = 100;
  await tester.pump(step);
  for (var i = 0; i < limit && finder.evaluate().isNotEmpty; i++) {
    await tester.pump(step);
  }
  expect(finder, findsNothing);
  await tester.pumpAndSettle();
}

Future<void> _openUserDataDeletion(SweepScreenContext context) async {
  await _openSettingsEntry(context, const Key('settingsSupportPrivacyButton'));
  await context.tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
  await context.tester.pumpAndSettle();
}

Future<void> _openFacilityReport(SweepScreenContext context) async {
  unawaited(
    context.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityReportScreen(
          repository: SweepReportRepository(),
          target: const FacilityReportTarget(
            stationId: sweepStationId,
            stationName: '강남',
            facilityId: 'facility-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
        ),
      ),
    ),
  );
  await context.tester.pumpAndSettle();
}

Future<void> _openStationSearch(SweepScreenContext context) async {
  await _openMenu(context);
  await context.tester.tap(
    find.byKey(const Key('networkMapMenuStationSearchButton')),
  );
  await context.tester.pumpAndSettle();
}

Future<void> _openStationSearchResults(SweepScreenContext context) async {
  await _openStationSearch(context);
  await context.tester.enterText(
    find.byKey(const Key('stationSearchInput')),
    sweepSearchResult.nameKo,
  );
  await context.tester.pumpAndSettle(const Duration(seconds: 1));
}

/// 역 상세 시트의 지연 생성 목록을 스크롤해 [target]을 화면에 올린다.
Future<void> scrollStationDetailTo(
  WidgetTester tester,
  Finder target, {
  double delta = 300,
}) => tester.scrollUntilVisible(
  target,
  delta,
  scrollable: find
      .descendant(
        of: find.byKey(const Key('stationDetailSheet')),
        matching: find.byType(Scrollable),
      )
      .first,
);

/// 역 상세의 하단 `전체 시간표` 버튼으로 시간표 화면을 연다.
Future<void> _openStationTimetable(SweepScreenContext context) async {
  await _openStationDetail(context);
  final button = find.byKey(const Key('stationTimetableButton'));
  await scrollStationDetailTo(context.tester, button, delta: 250);
  await context.tester.tap(button);
  await context.tester.pumpAndSettle();
}

Future<void> _openSettings(SweepScreenContext context) async {
  await _openMenu(context);
  await context.tester.tap(
    find.byKey(const Key('networkMapMenuSettingsButton')),
  );
  await context.tester.pumpAndSettle();
}

const _settingsServiceInfoKey = Key('settingsServiceInfoButton');

/// 설정 화면의 항목 하나를 눌러 그 화면을 연다.
Future<void> _openSettingsEntry(SweepScreenContext context, Key entry) async {
  await _openSettings(context);
  await context.tester.tap(find.byKey(entry));
  await context.tester.pumpAndSettle();
}

/// 서비스 정보 화면의 항목 하나를 눌러 그 화면을 연다.
Future<void> _openServiceInfoEntry(
  SweepScreenContext context,
  Key entry,
) async {
  await _openSettingsEntry(context, _settingsServiceInfoKey);
  await context.tester.tap(find.byKey(entry));
  await context.tester.pumpAndSettle();
}

/// 좌측 메뉴의 항목 하나를 눌러 그 화면을 연다.
Future<void> _openMenuEntry(SweepScreenContext context, String entryKey) async {
  await _openMenu(context);
  await context.tester.tap(find.byKey(Key(entryKey)));
  await context.tester.pumpAndSettle();
}

Future<void> _openMenu(SweepScreenContext context) async {
  await context.tester.tap(find.byKey(const Key('networkMapMenuButton')));
  await context.tester.pumpAndSettle();
}

Future<void> _openJourney(
  SweepScreenContext context, {
  required bool search,
}) async {
  final tester = context.tester;
  unawaited(
    context.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingPreferenceScope(
          preferences: context.theme.preferences,
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
  if (search) {
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
  }
}

Future<void> _openStationDetail(SweepScreenContext context) async {
  unawaited(
    showStationDetailSheet<void>(
      context: context.navigatorContext,
      repository: SweepRepository(),
      reportRepository: SweepReportRepository(),
      realtimeRepository: SweepRealtimeRepository(),
      enableRealtimePolling: false,
      timetableRepository: SweepRepository(),
      stationId: sweepStationId,
      previousStation: const StationDetailNeighbor(
        stationId: 'station-gyodae',
        nameKo: '교대',
      ),
      nextStation: const StationDetailNeighbor(
        stationId: 'station-yeoksam',
        nameKo: '역삼',
      ),
    ),
  );
  await context.tester.pumpAndSettle();
}
