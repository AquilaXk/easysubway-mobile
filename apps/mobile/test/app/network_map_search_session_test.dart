import 'dart:async';
import 'dart:io';

import 'package:easysubway_mobile/app/network_map_search_session.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_line_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('public owner가 submit과 initial recent state를 소유한다', (
    tester,
  ) async {
    final key = GlobalKey<NetworkMapSearchSessionState>();
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final repository = _RecordingStationSearchRepository();
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapSearchSession(
          key: key,
          onResultFocus: (_, _) {},
          searchQueryController: queryController,
          stationSearchRepository: repository,
          searchHistoryRepository: null,
          routeDraftController: routeDraftController,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pump();

    expect(key.currentState, isNotNull);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsOneWidget);

    key.currentState!.submitSearch('강남');
    await tester.pump();

    expect(repository.requests, [(query: '강남', region: '수도권')]);
  });

  testWidgets('active query의 region 변경을 새 지역 검색으로 넘긴다', (tester) async {
    final key = GlobalKey<NetworkMapSearchSessionState>();
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final repository = _RecordingStationSearchRepository();
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    Widget session(String regionLabel) => MaterialApp(
      home: NetworkMapSearchSession(
        key: key,
        onResultFocus: (_, _) {},
        searchQueryController: queryController,
        stationSearchRepository: repository,
        searchHistoryRepository: null,
        routeDraftController: routeDraftController,
        regionLabel: regionLabel,
      ),
    );

    await tester.pumpWidget(session('수도권'));
    await tester.pump();
    queryController.text = '서울';
    await tester.pump();

    await tester.pumpWidget(session('부산'));
    await tester.pump();

    expect(repository.requests, [
      (query: '서울', region: '수도권'),
      (query: '서울', region: '부산'),
    ]);
  });

  testWidgets('empty query의 region 변경은 recent history를 새 지역으로 다시 읽는다', (
    tester,
  ) async {
    final key = GlobalKey<NetworkMapSearchSessionState>();
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final history = _SearchHistoryRepository(entries: [_recentStation]);
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        key: key,
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(),
        historyRepository: history,
        regionLabel: '수도권',
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      _session(
        key: key,
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(),
        historyRepository: history,
        regionLabel: '부산',
      ),
    );
    await tester.pump();

    expect(history.listRegions, ['수도권', '부산']);
  });

  testWidgets('recent station과 waypoint route selection을 app session에서 처리한다', (
    tester,
  ) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final stationRepository = _RecordingStationSearchRepository();
    final history = _SearchHistoryRepository(
      entries: [_recentStation, _recentRoute],
    );
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: stationRepository,
        historyRepository: history,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('recentRouteSearch-origin-waypoint-destination')),
    );
    expect(routeDraftController.draft.origin?.id, 'origin');
    expect(routeDraftController.draft.waypoint?.id, 'waypoint');
    expect(routeDraftController.draft.destination?.id, 'destination');

    await tester.tap(find.byKey(const Key('stationRecentSearchQuery-서울')));
    await tester.pump();
    expect(queryController.text, '서울');
    expect(stationRepository.requests.last, (query: '서울', region: '수도권'));
  });

  testWidgets('recent 항목 개별 삭제와 모두 지우기를 두 entry type에 적용한다', (tester) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final history = _SearchHistoryRepository(
      entries: [_recentStation, _recentRoute],
    );
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(),
        historyRepository: history,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('stationRecentSearchRemove-서울')));
    await tester.pump();
    expect(history.removedQueries, ['서울']);

    await tester.tap(
      find.byKey(
        const Key('recentRouteSearchRemove-origin-waypoint-destination'),
      ),
    );
    await tester.pump();
    expect(history.removedRouteKeys, [_recentRoute.identityKey]);

    history.entries = [_recentStation, _recentRoute];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(),
        historyRepository: history,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pump();
    expect(history.entries, hasLength(2));

    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllConfirm')),
    );
    await tester.pump();
    expect(history.entries, isEmpty);
  });

  testWidgets('recent load·remove·clear failures는 ready state와 snackbar로 끝난다', (
    tester,
  ) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final history = _SearchHistoryRepository(
      entries: [_recentStation, _recentRoute],
      listError: StateError('load failed'),
    );
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(),
        historyRepository: history,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(
      find.byKey(const Key('stationRecentSearchEmptyState')),
      findsOneWidget,
    );

    history.listError = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(),
        historyRepository: history,
      ),
    );
    await tester.pump();
    history.removeError = StateError('remove failed');
    await tester.tap(find.byKey(const Key('stationRecentSearchRemove-서울')));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('최근 검색을 지우지 못했어요.'), findsOneWidget);

    history.removeError = null;
    history.failListAfterCalls = history.listCalls;
    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllConfirm')),
    );
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('최근 검색을 지우지 못했어요.'), findsWidgets);
  });

  testWidgets('검색 결과 행은 즐겨찾기 토글 없이 역명과 노선 마크만 그린다', (tester) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(
          results: [_searchResult],
        ),
      ),
    );
    await tester.pump();
    queryController.text = '서울';
    await tester.pump();

    final row = find.byKey(
      const Key('stationSearchResult-station-seoul-line-1'),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(StationLineBadge)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star_border), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('disposed session은 late history completion을 무시한다', (
    tester,
  ) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final searchCompleter = Completer<List<StationSearchResult>>();
    final historyCompleter = Completer<List<RecentSearchEntry>>();
    final history = _SearchHistoryRepository(
      entries: const [],
      listCompleter: historyCompleter,
    );
    final key = GlobalKey<NetworkMapSearchSessionState>();
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        key: key,
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(
          searchCompleter: searchCompleter,
        ),
        historyRepository: history,
      ),
    );
    key.currentState!.submitSearch('서울');
    await tester.pumpWidget(const SizedBox.shrink());
    searchCompleter.complete(const []);
    historyCompleter.complete([_recentStation]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed session은 history repository 없는 late search 완료를 무시한다', (
    tester,
  ) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final searchCompleter = Completer<List<StationSearchResult>>();
    final key = GlobalKey<NetworkMapSearchSessionState>();
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        key: key,
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(
          searchCompleter: searchCompleter,
        ),
      ),
    );
    key.currentState!.submitSearch('서울');
    await tester.pumpWidget(const SizedBox.shrink());
    searchCompleter.complete(const []);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test('root는 public app owner를 쓰고 private session 선언을 갖지 않는다', () {
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    expect(root, contains("import 'network_map_search_session.dart';"));
    expect(root, contains('GlobalKey<NetworkMapSearchSessionState>'));
    expect(root, contains('return NetworkMapSearchSession('));
    expect(root, isNot(contains('class _NetworkMapSearchSession')));
    expect(root, isNot(contains('class _NetworkMapSearchSessionState')));
  });

  testWidgets('searchQueryController 교체 시 리스너를 정상 이전한다', (tester) async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final stationRepository = _RecordingStationSearchRepository();

    await tester.pumpWidget(
      _session(
        queryController: oldController,
        routeDraftController: routeDraftController,
        stationRepository: stationRepository,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _session(
        queryController: newController,
        routeDraftController: routeDraftController,
        stationRepository: stationRepository,
      ),
    );
    await tester.pump();

    newController.text = '강남';
    await tester.pump();
    expect(stationRepository.requests, isNotEmpty);
  });
}

class _RecordingStationSearchRepository implements StationSearchRepository {
  _RecordingStationSearchRepository({
    this.results = const [],
    this.searchCompleter,
  });

  final requests = <({String query, String? region})>[];
  final List<StationSearchResult> results;
  final Completer<List<StationSearchResult>>? searchCompleter;

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async {
    requests.add((query: query, region: region));
    return searchCompleter?.future ?? results;
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(String stationId) {
    throw UnimplementedError();
  }
}

Widget _session({
  GlobalKey<NetworkMapSearchSessionState>? key,
  required TextEditingController queryController,
  required RouteDraftController routeDraftController,
  required StationSearchRepository stationRepository,
  SearchHistoryRepository? historyRepository,
  String regionLabel = '수도권',
}) {
  return MaterialApp(
    home: Scaffold(
      body: NetworkMapSearchSession(
        key: key,
        onResultFocus: (_, _) {},
        searchQueryController: queryController,
        stationSearchRepository: stationRepository,
        searchHistoryRepository: historyRepository,
        routeDraftController: routeDraftController,
        regionLabel: regionLabel,
      ),
    ),
  );
}

const _line = StationSearchLine(
  id: 'line-1',
  name: '수도권 1호선',
  color: '#0052A4',
  stationCode: '101',
);

final _recentStation = RecentStationSearchEntry(
  query: '서울',
  region: '수도권',
  searchedAt: DateTime(2026, 8, 13),
  lines: const [_line],
);

final _recentRoute = RecentRouteSearchEntry(
  originStationId: 'origin',
  originStationName: '출발',
  waypointStationId: 'waypoint',
  waypointStationName: '경유',
  destinationStationId: 'destination',
  destinationStationName: '도착',
  region: '수도권',
  searchedAt: DateTime(2026, 8, 13),
);

const _searchResult = StationSearchResult(
  id: 'station-seoul',
  nameKo: '서울',
  nameEn: 'Seoul',
  region: '수도권',
  dataQualityLevel: 'VERIFIED',
  lastVerifiedAt: '2026-08-13T00:00:00Z',
  lines: [_line],
);

class _SearchHistoryRepository implements SearchHistoryRepository {
  _SearchHistoryRepository({
    required this.entries,
    this.listError,
    this.listCompleter,
  });

  List<RecentSearchEntry> entries;
  Object? listError;
  final Completer<List<RecentSearchEntry>>? listCompleter;
  Object? removeError;
  int? failListAfterCalls;
  int listCalls = 0;
  final listRegions = <String?>[];
  final removedQueries = <String>[];
  final removedRouteKeys = <String>[];

  @override
  Future<List<RecentSearchEntry>> listRecentEntries({
    String? region,
    int limit = 10,
  }) async {
    listRegions.add(region);
    final call = listCalls++;
    final error = listError;
    if (error != null ||
        (failListAfterCalls != null && call >= failListAfterCalls!)) {
      throw error ?? StateError('list failed');
    }
    final completedEntries =
        await (listCompleter?.future ?? Future.value(entries));
    return completedEntries.take(limit).toList(growable: false);
  }

  @override
  Future<void> removeSearch(String query, {String? region}) async {
    final error = removeError;
    if (error != null) {
      throw error;
    }
    removedQueries.add(query);
    entries = [
      for (final entry in entries)
        if (entry is! RecentStationSearchEntry || entry.query != query) entry,
    ];
  }

  @override
  Future<void> removeRouteSearch(RecentRouteSearchEntry entry) async {
    final error = removeError;
    if (error != null) {
      throw error;
    }
    removedRouteKeys.add(entry.identityKey);
    entries = [
      for (final current in entries)
        if (current is! RecentRouteSearchEntry ||
            current.identityKey != entry.identityKey)
          current,
    ];
  }

  @override
  Future<void> recordSearch(
    String query, {
    String? region,
    String? stationId,
    StationSearchLine? line,
  }) async {}

  @override
  Future<void> recordRouteSearch(RecentRouteSearchEntry entry) async {}

  @override
  Future<List<String>> listRecentQueries() async => const [];

  @override
  Future<void> clearSearches() async {
    entries = [];
  }
}
