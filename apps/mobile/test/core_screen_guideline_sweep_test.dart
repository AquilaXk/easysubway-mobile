import 'dart:async' show unawaited;

import 'package:easysubway_mobile/app/accessibility_theme.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/easy_subway_app_fixture.dart';
import 'support/journey_result_fixture.dart';

/// 핵심 화면 x 테마 x 글자 크기 x 접근성 가이드라인 전수 검사(#464).
///
/// 화면은 [_screens] 표의 한 줄로 추가한다. 가이드라인 4종은 [_guidelines]
/// 표 하나로 모든 조합에 같은 방식으로 적용한다. 위반은 예외 목록 없이 그대로
/// 실패로 드러난다.
///
/// 번들 폰트는 일부러 로드하지 않는다. `textContrastGuideline`은 화면 캡처의 색
/// 빈도로 글자색을 추정하므로, 얇은 실제 글꼴은 플랫폼별 안티앨리어싱 차이로
/// 같은 코드에서도 macOS와 Linux 결과가 갈린다. 테스트 기본 폰트(Ahem)는 글자가
/// 단색 사각형이라 색 추정이 플랫폼과 무관하게 같다.

/// 앱에 다크 테마는 없다(`darkTheme` 미정의). 시스템 다크 모드에서도 같은
/// 테마로 그려지는지 `systemDark` 조합으로 함께 검사해, 다크 테마를 도입하면
/// 이 표가 바로 새 테마를 검사하게 한다.
enum _AppTheme {
  standard('기본 테마'),
  highContrast('고대비'),
  systemDark('시스템 다크 모드');

  const _AppTheme(this.label);

  final String label;

  OnboardingViewPreferences get preferences => OnboardingViewPreferences(
    largeTextEnabled: false,
    highContrastEnabled: this == highContrast,
    simpleViewEnabled: false,
  );

  Brightness get platformBrightness =>
      this == systemDark ? Brightness.dark : Brightness.light;
}

const _textScales = <double>[1.0, 1.5];

/// 긴 목록도 화면 안에 모두 그려 가이드라인이 끝까지 검사하도록 세로를 길게 둔다.
const _logicalViewport = Size(360, 2000);
const _devicePixelRatio = 3.0;

final _guidelines = <String, AccessibilityGuideline>{
  'Android 탭 영역 48dp': androidTapTargetGuideline,
  'iOS 탭 영역 44pt': iOSTapTargetGuideline,
  '탭 가능한 요소의 라벨': labeledTapTargetGuideline,
  '글자 대비': textContrastGuideline,
};

class _ScreenContext {
  const _ScreenContext({
    required this.tester,
    required this.navigatorKey,
    required this.theme,
  });

  final WidgetTester tester;
  final GlobalKey<NavigatorState> navigatorKey;
  final _AppTheme theme;

  BuildContext get navigatorContext => navigatorKey.currentContext!;
}

class _Screen {
  const _Screen(this.name, this.open, this.shown);

  final String name;
  final Future<void> Function(_ScreenContext context) open;

  /// 화면이 실제로 열렸음을 보이는 요소. 열리지 않은 화면이 가이드라인을
  /// 통과하는 일을 막는다.
  final Finder shown;
}

final _screens = <_Screen>[
  _Screen(
    '홈(노선도)',
    (context) async {},
    find.byKey(const Key('networkMapMenuButton')),
  ),
  _Screen('좌측 메뉴', _openMenu, find.byKey(const Key('networkMapMenuPanel'))),
  _Screen(
    '경로 검색',
    (context) => _openJourney(context, search: false),
    find.widgetWithText(FilledButton, '경로 찾기'),
  ),
  _Screen(
    '경로 결과·상세',
    (context) => _openJourney(context, search: true),
    find.byKey(const Key('selected-journey-detail')),
  ),
  _Screen(
    '역 상세',
    _openStationDetail,
    find.byKey(const Key('stationDetailSheet')),
  ),
  _Screen('설정', _openSettings, find.byKey(const Key('settingsScreen'))),
];

Future<void> _openSettings(_ScreenContext context) async {
  await _openMenu(context);
  await context.tester.tap(
    find.byKey(const Key('networkMapMenuSettingsButton')),
  );
  await context.tester.pumpAndSettle();
}

Future<void> _openMenu(_ScreenContext context) async {
  await context.tester.tap(find.byKey(const Key('networkMapMenuButton')));
  await context.tester.pumpAndSettle();
}

Future<void> _openJourney(
  _ScreenContext context, {
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

Future<void> _openStationDetail(_ScreenContext context) async {
  unawaited(
    showStationDetailSheet<void>(
      context: context.navigatorContext,
      repository: _SweepRepository(),
      reportRepository: const UnavailableFacilityReportRepository(),
      stationId: _sweepStationId,
    ),
  );
  await context.tester.pumpAndSettle();
}

void main() {
  for (final screen in _screens) {
    for (final theme in _AppTheme.values) {
      for (final textScale in _textScales) {
        testWidgets('${screen.name} - ${theme.label} - 글자 $textScale배', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            final navigatorKey = GlobalKey<NavigatorState>();
            await _pumpApp(tester, navigatorKey, theme, textScale);
            await screen.open(
              _ScreenContext(
                tester: tester,
                navigatorKey: navigatorKey,
                theme: theme,
              ),
            );

            expect(screen.shown, findsOneWidget);
            expect(tester.takeException(), isNull);
            expect(await _violations(tester), isEmpty);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}

/// 화면 하나에 모든 가이드라인을 적용하고 위반한 요소마다 한 줄씩 모은다.
Future<List<String>> _violations(WidgetTester tester) async {
  final violations = <String>[];
  for (final MapEntry(:key, :value) in _guidelines.entries) {
    final evaluation = await value.evaluate(tester);
    if (!evaluation.passed) {
      violations.addAll(
        _violatingNodes(evaluation.reason).map((n) => '$key | $n'),
      );
    }
  }
  return violations;
}

final _nodeLabelPattern = RegExp(r'label: "([^"]*)"');
final _nodeRectPattern = RegExp(r'Rect\.fromLTRB\(([^)]*)\)');

/// 가이드라인이 돌려준 여러 줄 사유를 요소 단위 한 줄(라벨, 영역, 사유)로 줄인다.
List<String> _violatingNodes(String? reason) {
  final text = reason ?? '';
  final nodes = text.split('SemanticsNode#').skip(1).map((chunk) {
    final label = _nodeLabelPattern.firstMatch(chunk)?[1] ?? '';
    final rect = _nodeRectPattern.firstMatch(chunk)?[1] ?? '';
    final detail = chunk.split('):\n').skip(1).join().split('\n').first;
    return '"$label" [$rect] $detail';
  }).toList();
  return nodes.isEmpty ? [text] : nodes;
}

Future<void> _pumpApp(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigatorKey,
  _AppTheme theme,
  double textScale,
) async {
  tester.view.devicePixelRatio = _devicePixelRatio;
  tester.view.physicalSize = _logicalViewport * _devicePixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue =
      theme.platformBrightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
  await tester.pumpWidget(
    buildEasySubwayTestApp(
      repository: _SweepRepository(),
      reportRepository: const UnavailableFacilityReportRepository(),
      navigatorKey: navigatorKey,
      initialOnboardingState: OnboardingState.completed(
        result: OnboardingResult(
          preset: MobilityPreset.standard,
          preferences: theme.preferences,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _sweepStationId = 'station-gangnam';

/// 홈 노선도와 역 상세가 쓰는 고정 응답. 역 검색 포트와 노선도 포트를 함께 구현한다.
class _SweepRepository
    implements StationSearchRepository, NetworkMapRepository {
  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return const NetworkMapData(
      regions: [NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: [
        NetworkMapLine(
          id: 'seoul-2',
          name: '수도권 2호선',
          color: '#00A84D',
          region: '수도권',
        ),
      ],
      stations: [
        NetworkMapStation(
          id: _sweepStationId,
          nameKo: '강남',
          nameEn: 'Gangnam',
          region: '수도권',
          lineId: 'seoul-2',
          stationCode: '222',
          sequence: 1,
          position: NetworkMapPosition(
            x: 100,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'sweep-fixture',
          ),
        ),
      ],
      edges: [],
      positionSources: [],
    );
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    return const StationDetail(
      id: _sweepStationId,
      nameKo: '강남',
      nameEn: 'Gangnam',
      region: '수도권',
      dataQualityLevel: 'LEVEL_1',
      lastVerifiedAt: '2026-09-27',
      lines: [
        StationSearchLine(
          id: 'seoul-2',
          name: '수도권 2호선',
          color: '#00A84D',
          stationCode: '222',
        ),
      ],
    );
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    return const [
      StationExitInfo(
        id: 'exit-1',
        stationId: _sweepStationId,
        exitNumber: '1',
        name: '1번 출구',
        description: '강남역 광장',
        hasElevatorConnection: true,
        hasStairOnlyPath: StairOnlyPathStatus.absent,
        dataConfidence: 'HIGH',
        lastVerifiedAt: '2026-09-27',
      ),
    ];
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    return const [
      StationFacilityInfo(
        id: 'facility-elevator-1',
        stationId: _sweepStationId,
        exitId: 'exit-1',
        type: 'ELEVATOR',
        name: '1번 출구 엘리베이터',
        floorFrom: '지상',
        floorTo: '대합실',
        description: '1번 출구',
        status: 'BROKEN',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];
  }

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async => const [];

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async => const [];
}
