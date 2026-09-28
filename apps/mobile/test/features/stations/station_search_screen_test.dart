import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_search_screen.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:easysubway_mobile/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/easy_subway_app_fixture.dart';

const _completedOnboardingState = OnboardingState.completed(
  result: OnboardingResult(
    preset: MobilityPreset.standard,
    preferences: OnboardingViewPreferences.defaults(),
  ),
);

void main() {
  testWidgets('#2083 역 검색 화면은 홈 편집 모드와 같은 40px 시각 박스·중앙 정렬 입력 필드를 렌더한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 홈 편집 모드와 동일한 공용 시각 박스(40px)를 렌더한다.
    expect(
      tester.getSize(find.byKey(const Key('heroStationSearchInputBox'))).height,
      easySubwaySearchFieldVisualHeight,
    );

    // pickSlot별 힌트가 placeholder(이자 TalkBack 라벨)로 렌더된다. #2083 오너
    // 확정: 슬롯 검색 진입 placeholder는 슬롯명 단독.
    expect(find.text('출발역'), findsOneWidget);

    // 입력 필드 탭 타깃(병합된 터치타겟 SizedBox)은 최소 탭 타깃(≥48)을 유지한다.
    final originInputTapTarget = find
        .ancestor(
          of: find.byKey(const Key('stationSearchInput')),
          matching: find.byType(SizedBox),
        )
        .first;
    expect(
      tester.getSize(originInputTapTarget).height,
      greaterThanOrEqualTo(48.0),
    );

    // 편집 텍스트가 40px 시각 박스 안에 렌더돼야 한다(#2082 수정을 공용 위젯이
    // 소비함을 검증). #2082 실기기 재작업: 중앙 정렬은 고유 높이 필드 + Center
    // 위젯으로 얻으며 실기기(Noto Sans KR)에서 오프셋 0으로 정합함을 픽셀 판독으로
    // 확인했다(docs/2082-qa, 정본). FlutterTest 테스트 폰트·AppBar toolbar 배치
    // 오차로 중심이 박스 중심에서 십수 px 벗어날 수 있으므로, 입력 글자가 박스
    // 세로 범위 안에 온전히 들어오는지를 폰트 메트릭 독립적으로 계약으로 잡는다.
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    final searchScreenBoxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    final searchScreenTextCenterDy = tester.getCenter(find.text('상록수')).dy;
    expect(searchScreenTextCenterDy, greaterThan(searchScreenBoxRect.top));
    expect(searchScreenTextCenterDy, lessThan(searchScreenBoxRect.bottom));

    final searchField = tester.widget<TextField>(
      find.byKey(const Key('stationSearchInput')),
    );
    expect(searchField.maxLines, 1);
    expect(searchField.expands, isFalse);
  });

  testWidgets('#2082 역 검색 화면은 지역 선택 버튼 없이 검색 필드가 상단바 우측 끝까지 100% 확장된다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 상단바에 별도 지역 선택기/드롭다운이 없어야 함
    expect(find.byKey(const Key('stationSearchRegionIndicator')), findsNothing);
    expect(find.byKey(const Key('stationSearchRegionDropdown')), findsNothing);

    // 뒤로가기 버튼과 검색 입력창이 정상 존재해야 함
    expect(find.byKey(const Key('stationSearchBackButton')), findsOneWidget);
    expect(find.byKey(const Key('heroStationSearchInputBox')), findsOneWidget);
  });

  testWidgets('역 검색어를 지우면 결과를 닫고 최근 검색 상태로 돌아간다', (tester) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult()],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('stationSearchInput'));
    await tester.enterText(input, '상록수');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('stationSearchResult-station-sangnoksu-seoul-4')),
      findsOneWidget,
    );

    await tester.enterText(input, '');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationSearchResult-station-sangnoksu-seoul-4')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('stationRecentSearchEmptyState')),
      findsOneWidget,
    );
  });

  testWidgets('역 검색 결과는 현재 주입된 regionLabel(수도권)에 맞춰 필터링된다', (tester) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '중앙': [
          _stationResult(),
          const StationSearchResult(
            id: 'station-busan-jungang',
            nameKo: '중앙',
            nameEn: 'Jungang',
            region: '부산권',
            dataQualityLevel: 'LEVEL_1',
            lastVerifiedAt: '2026-06-13',
            lines: [
              StationSearchLine(
                id: 'busan-1',
                name: '부산 1호선',
                color: '#F73A3A',
                stationCode: '119',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '중앙');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // 수도권 필터: 수도권 역만 남는다.
    expect(find.text('상록수역'), findsOneWidget);
    expect(
      find.byKey(
        const Key('stationSearchResult-station-busan-jungang-busan-1'),
      ),
      findsNothing,
    );
  });

  testWidgets('#2090 수도권 외 지역(부산) 선택 상태에서 열면 부산권 역 검색 결과를 노출한다', (
    tester,
  ) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '중앙': [
          _stationResult(),
          const StationSearchResult(
            id: 'station-busan-jungang',
            nameKo: '중앙',
            nameEn: 'Jungang',
            region: '부산권',
            dataQualityLevel: 'LEVEL_1',
            lastVerifiedAt: '2026-06-13',
            lines: [
              StationSearchLine(
                id: 'busan-1',
                name: '부산 1호선',
                color: '#F73A3A',
                stationCode: '119',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '부산',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '중앙');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // 부산 필터: 부산권 역이 검색 결과에 노출된다.
    expect(
      find.byKey(
        const Key('stationSearchResult-station-busan-jungang-busan-1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('#2090 배율 3.0에서 역 검색 화면 필드가 툴바 안에서 잘리지 않는다', (tester) async {
    // 툴바 높이 보정 상수가 필드 메트릭과 정합돼 큰 배율에서도 필드가
    // 상단바 세로 범위 안에 온전히 들어가야 한다.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: MaterialApp(
          home: StationSearchScreen(
            repository: _EmptyStationSearchRepository(),
            reportRepository: const UnavailableFacilityReportRepository(),
            pickSlot: RouteDraftSlot.origin,
            regionLabel: '수도권',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final topBarFinder = find.byKey(const Key('stationSearchAppBar'));
    expect(topBarFinder, findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('stationSearchTopBarContent')))
          .height,
      greaterThan(easySubwayTopBarContentHeight),
    );

    final topBarRect = tester.getRect(topBarFinder);
    final boxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    // 시각 박스가 상단바 세로 범위 안에 온전히 들어간다(위/아래로 잘리지 않음).
    expect(boxRect.bottom, lessThanOrEqualTo(topBarRect.bottom + 0.5));
    expect(boxRect.top, greaterThanOrEqualTo(topBarRect.top - 0.5));
  });

  testWidgets('#2090 역 검색 필드는 입력 후에도 슬롯 맥락 semantics 라벨을 유지한다', (tester) async {
    // 이전 floating label이 유지하던 슬롯 맥락("출발역") 라벨이 입력 후에도
    // 스크린리더 semantics 트리에 남아야 한다.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 입력 전에는 hint 노드와 라벨 래퍼 때문에 하나 이상 존재한다.
    expect(find.bySemanticsLabel('출발역'), findsWidgets);

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    // hint가 사라진 뒤에도 라벨 래퍼가 슬롯 맥락을 유지한다.
    expect(find.bySemanticsLabel('출발역'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('#2090 도착역 슬롯은 도착역 맥락 semantics 라벨을 노출한다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          pickSlot: RouteDraftSlot.destination,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '사당');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('도착역'), findsOneWidget);
    // 출발역 맥락이 새어 나오지 않는다.
    expect(find.bySemanticsLabel('출발역'), findsNothing);
    handle.dispose();
  });

  testWidgets('앱 메뉴 검색 진입은 최근 검색 저장소를 화면에 전달한다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository(['상록수']);

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: _EmptyStationSearchRepository(),
        reportRepository: const UnavailableFacilityReportRepository(),
        searchHistoryRepository: searchHistoryRepository,
        initialOnboardingState: _completedOnboardingState,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRecentSearchQuery-상록수')),
      findsOneWidget,
    );
  });

  testWidgets('역 검색 화면에는 내 주변 역 찾기 버튼이 없다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: _EmptyStationSearchRepository(),
        reportRepository: const UnavailableFacilityReportRepository(),
        initialOnboardingState: _completedOnboardingState,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
    expect(find.text('내 주변 역 찾기'), findsNothing);
    expect(find.text('내 주변 역 다시 찾기'), findsNothing);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
  });

  testWidgets('최근 검색이 없으면 빈 상태 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: _MemorySearchHistoryRepository(const []),
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRecentSearchEmptyState')),
      findsOneWidget,
    );
    expect(find.text('최근 검색 내역이 없습니다.'), findsOneWidget);
    expect(
      find.byKey(const Key('stationRecentSearchEmptyImage')),
      findsOneWidget,
    );
    // 내역이 없으면 헤더(최근 검색 / 모두 지우기)는 숨긴다.
    expect(find.text('최근 검색'), findsNothing);
    expect(find.text('모두 지우기'), findsNothing);
    expect(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
      findsNothing,
    );
  });

  testWidgets('역 검색 화면 상단바 입력 필드는 시스템 글자 크기를 키워도 잘리지 않는다', (tester) async {
    // #1962: 고정 높이 검색 필드가 큰 글자 배율에서도 상단바 경계를 넘지 않아야 한다.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: buildEasySubwayTestApp(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          initialOnboardingState: _completedOnboardingState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final inputFinder = find.byKey(const Key('stationSearchInput'));
    expect(inputFinder, findsOneWidget);

    final topBarFinder = find.byKey(const Key('stationSearchAppBar'));
    expect(topBarFinder, findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('stationSearchTopBarContent')))
          .height,
      greaterThan(easySubwayTopBarContentHeight),
    );

    final topBarRect = tester.getRect(topBarFinder);
    final inputRect = tester.getRect(inputFinder);
    expect(inputRect.bottom, lessThanOrEqualTo(topBarRect.bottom + 0.5));
    expect(inputRect.top, greaterThanOrEqualTo(topBarRect.top - 0.5));
  });

  testWidgets('역 검색 화면은 최근 검색어를 탭해 빠르게 다시 검색한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult()],
      },
    );
    final searchHistoryRepository = _MemorySearchHistoryRepository([
      '상록수',
      '사당',
    ]);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StationSearchScreen(
            repository: repository,
            reportRepository: const UnavailableFacilityReportRepository(),
            searchHistoryRepository: searchHistoryRepository,
            regionLabel: '수도권',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
      expect(
        find.byKey(const Key('stationRecentSearchSection')),
        findsOneWidget,
      );
      expect(find.text('최근 검색'), findsOneWidget);
      expect(find.text('모두 보기'), findsNothing);
      expect(find.text('모두 지우기'), findsOneWidget);
      expect(
        find.byKey(const Key('stationRecentSearchViewAllButton')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('stationRecentSearchClearAllButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationRecentSearchQuery-상록수')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('최근 검색어 상록수 검색'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('최근 검색어 상록수 검색'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('stationRecentSearchQuery-상록수')));
      await tester.pumpAndSettle();

      final searchInput = tester.widget<TextField>(
        find.byKey(const Key('stationSearchInput')),
      );
      expect(searchInput.controller?.text, '상록수');
      // 최근 목록 호선 마크용 조회·재로드가 섞이므로 제출 기록만 본다.
      expect(repository.requestedQueries, contains('상록수'));
      expect(searchHistoryRepository.recordedQueries, ['상록수']);
      expect(
        find.byKey(const Key('stationSearchResult-station-sangnoksu-seoul-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationRoleOrigin-station-sangnoksu')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('stationRoleDestination-station-sangnoksu')),
        findsNothing,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 화면 안에서 최근 검색을 개별 삭제한다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository([
      '상록수',
      '사당',
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('stationRecentSearchRemove-상록수')));
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.removedQueries, ['상록수']);
    expect(find.byKey(const Key('stationRecentSearchQuery-상록수')), findsNothing);
    expect(
      find.byKey(const Key('stationRecentSearchQuery-사당')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationRecentSearchSection')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
  });

  testWidgets('역 검색 최근 목록은 현재 지역 항목만 보여준다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository(const []);
    await searchHistoryRepository.recordSearch('상록수', region: '수도권');
    await searchHistoryRepository.recordSearch('서면', region: '부산');

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 수도권을 보는 동안 부산 검색어는 목록에 없다.
    expect(
      find.byKey(const Key('stationRecentSearchQuery-상록수')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationRecentSearchQuery-서면')), findsNothing);
  });

  testWidgets('최근 경로 항목은 화살표 라벨로 표시되고 draft에 적용된다', (tester) async {
    final draftController = RouteDraftController();
    final searchHistoryRepository = _MemorySearchHistoryRepository(const [])
      ..seedRoute(
        RecentRouteSearchEntry(
          originStationId: 'station-sangnoksu',
          originStationName: '상록수',
          destinationStationId: 'station-sadang',
          destinationStationName: '사당',
          region: '수도권',
          searchedAt: DateTime.utc(2026, 7, 21),
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          routeDraftController: draftController,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 경로 최근 항목은 역마다 호선 마크+이름을 나눠 그린다(한 줄 문자열 아님).
    expect(find.text('상록수역'), findsOneWidget);
    expect(find.text('사당역'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
    final recentRoute = find.byKey(
      const Key('recentRouteSearch-station-sangnoksu--station-sadang'),
    );
    expect(recentRoute, findsOneWidget);

    await tester.tap(recentRoute);
    await tester.pumpAndSettle();

    expect(draftController.draft.origin?.id, 'station-sangnoksu');
    expect(draftController.draft.destination?.id, 'station-sadang');
  });

  testWidgets('역 검색 결과는 환승 역을 노선마다 한 행으로 펼쳐 보여준다', (tester) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '환승': [
          const StationSearchResult(
            id: 'station-transfer',
            nameKo: '환승역',
            nameEn: 'Transfer',
            region: '수도권',
            dataQualityLevel: 'LEVEL_1',
            lastVerifiedAt: '2026-06-12',
            lines: [
              StationSearchLine(
                id: 'seoul-4',
                name: '수도권 4호선',
                color: '#00A5DE',
                stationCode: '448',
              ),
              StationSearchLine(
                id: 'korail-gyeongui-jungang',
                name: '경의중앙선',
                color: '#75C5A1',
                stationCode: 'K232',
              ),
              StationSearchLine(
                id: 'suin-bundang',
                name: '수인분당선',
                color: '#F5A200',
                stationCode: 'K249',
              ),
              StationSearchLine(
                id: 'shinbundang',
                name: '신분당선',
                color: '#D4003B',
                stationCode: 'D14',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '환승');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stationLineBadge-seoul-4')), findsOneWidget);
    expect(
      find.byKey(const Key('stationLineBadge-korail-gyeongui-jungang')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationLineBadge-suin-bundang')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationLineBadge-shinbundang')),
      findsOneWidget,
    );
    expect(find.text('+3'), findsNothing);
    expect(find.byKey(const Key('stationLineBadgeOverflow')), findsNothing);
    expect(
      find.byKey(const Key('stationSearchResult-station-transfer-seoul-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key(
          'stationSearchResult-station-transfer-korail-gyeongui-jungang',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('stationSearchResult-station-transfer-suin-bundang'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationSearchResult-station-transfer-shinbundang')),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  });

  testWidgets('역 검색 후 결과를 선택하면 검색어 단편("1") 대신 역 정식 명칭을 최근 검색어로 기록한다', (
    tester,
  ) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '1': [_stationResult()],
      },
    );
    final searchHistoryRepository = _MemorySearchHistoryRepository(const []);
    final draftController = RouteDraftController();

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          routeDraftController: draftController,
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('stationSearchInput'));
    await tester.enterText(input, '1');
    await tester.pumpAndSettle();

    final resultFinder = find.byKey(
      const Key('stationSearchResult-station-sangnoksu-seoul-4'),
    );
    expect(resultFinder, findsOneWidget);

    await tester.tap(resultFinder);
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.recordedQueries, contains('상록수'));
    expect(searchHistoryRepository.recordedQueries, isNot(contains('1')));
  });
}

class _EmptyStationSearchRepository implements StationSearchRepository {
  _EmptyStationSearchRepository({this.queryResults = const {}});

  final Map<String, List<StationSearchResult>> queryResults;
  final requestedQueries = <String>[];

  @override
  Future<StationDetail> getStationDetail(String stationId) =>
      throw UnimplementedError();

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async => [];

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async => [];

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async => const [];

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async {
    requestedQueries.add(query);
    return queryResults[query] ?? [];
  }
}

class _MemorySearchHistoryRepository implements SearchHistoryRepository {
  _MemorySearchHistoryRepository(
    List<String> queries, {
    String? seedRegion = '수도권',
  }) {
    for (final query in queries.reversed) {
      _addStation(query, region: seedRegion);
    }
  }

  final _stations = <RecentStationSearchEntry>[];
  final _routes = <RecentRouteSearchEntry>[];
  final recordedQueries = <String>[];
  final removedQueries = <String>[];
  int clearCount = 0;
  int _clock = 0;

  DateTime _tick() =>
      DateTime.fromMillisecondsSinceEpoch(++_clock, isUtc: true);

  void _addStation(
    String query, {
    String? region,
    List<StationSearchLine> lines = const [],
  }) {
    final normalized = region?.trim() ?? '';
    _stations.removeWhere(
      (entry) =>
          entry.query == query && (entry.region?.trim() ?? '') == normalized,
    );
    _stations.insert(
      0,
      RecentStationSearchEntry(
        query: query,
        region: normalized.isEmpty ? null : normalized,
        searchedAt: _tick(),
        lines: lines,
      ),
    );
  }

  void seedRoute(RecentRouteSearchEntry entry) {
    _routes.insert(
      0,
      RecentRouteSearchEntry(
        originStationId: entry.originStationId,
        originStationName: entry.originStationName,
        waypointStationId: entry.waypointStationId,
        waypointStationName: entry.waypointStationName,
        destinationStationId: entry.destinationStationId,
        destinationStationName: entry.destinationStationName,
        region: entry.region,
        searchedAt: _tick(),
      ),
    );
  }

  @override
  Future<void> clearSearches() async {
    clearCount++;
    _stations.clear();
    _routes.clear();
  }

  @override
  Future<List<String>> listRecentQueries() async =>
      _stations.map((entry) => entry.query).toList(growable: false);

  @override
  Future<List<RecentSearchEntry>> listRecentEntries({
    String? region,
    int limit = 10,
  }) async {
    final filter = region?.trim();
    final entries = <RecentSearchEntry>[
      for (final entry in _stations)
        if (_stationMatches(entry.region, filter)) entry,
      for (final entry in _routes)
        if (filter == null ||
            filter.isEmpty ||
            stationBelongsToRegion(entry.region, filter))
          entry,
    ]..sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    return entries.take(limit).toList(growable: false);
  }

  @override
  Future<void> recordSearch(
    String query, {
    String? region,
    String? stationId,
    StationSearchLine? line,
  }) async {
    final trimmed = query.trim();
    final normalized = region?.trim() ?? '';
    if (trimmed.isEmpty || normalized.isEmpty) {
      return;
    }
    recordedQueries.add(trimmed);
    _addStation(
      trimmed,
      region: normalized,
      lines: line == null || line.id.trim().isEmpty ? const [] : [line],
    );
  }

  @override
  Future<void> recordRouteSearch(RecentRouteSearchEntry entry) async {
    _routes.removeWhere(
      (existing) => existing.identityKey == entry.identityKey,
    );
    seedRoute(entry);
  }

  @override
  Future<void> removeSearch(String query, {String? region}) async {
    final trimmed = query.trim();
    removedQueries.add(trimmed);
    final normalized = region?.trim();
    if (normalized == null || normalized.isEmpty) {
      _stations.removeWhere((entry) => entry.query == trimmed);
      return;
    }
    _stations.removeWhere(
      (entry) =>
          entry.query == trimmed &&
          stationBelongsToRegion(entry.region ?? '', normalized),
    );
  }

  @override
  Future<void> removeRouteSearch(RecentRouteSearchEntry entry) async {
    _routes.removeWhere(
      (existing) => existing.identityKey == entry.identityKey,
    );
  }

  bool _stationMatches(String? rowRegion, String? filter) {
    if (filter == null || filter.isEmpty) {
      return true;
    }
    if (rowRegion == null || rowRegion.isEmpty) {
      return false;
    }
    return stationBelongsToRegion(rowRegion, filter);
  }
}

StationSearchResult _stationResult() {
  return const StationSearchResult(
    id: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-13',
    lines: [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
  );
}
