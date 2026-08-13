import 'dart:async';
import 'dart:io';

import 'package:easysubway_mobile/app/network_map_search_session.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
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
          favoriteRepository: null,
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
        favoriteRepository: null,
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

  testWidgets('favorite load와 toggle은 line identity로 remove와 save를 수행한다', (
    tester,
  ) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final favorite = _FavoriteStationRepository(favorites: [_favoriteStation]);
    addTearDown(queryController.dispose);
    addTearDown(routeDraftController.dispose);

    await tester.pumpWidget(
      _session(
        queryController: queryController,
        routeDraftController: routeDraftController,
        stationRepository: _RecordingStationSearchRepository(
          results: [_searchResult],
        ),
        favoriteRepository: favorite,
      ),
    );
    await tester.pump();
    queryController.text = '서울';
    await tester.pump();

    final button = find.byKey(
      const Key('stationSearchFavorite-station-seoul-line-1'),
    );
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();

    expect(favorite.removed, [(stationId: 'station-seoul', lineId: 'line-1')]);
    expect(favorite.saved, [(stationId: 'station-seoul', lineId: 'line-1')]);
  });

  testWidgets(
    'favorite load와 toggle failures는 fallback 없이 report/snackbar로 끝난다',
    (tester) async {
      final queryController = TextEditingController();
      final routeDraftController = RouteDraftController();
      final favorite = _FavoriteStationRepository(
        listError: StateError('favorite load failed'),
        saveError: StateError('favorite save failed'),
      );
      addTearDown(queryController.dispose);
      addTearDown(routeDraftController.dispose);

      await tester.pumpWidget(
        _session(
          queryController: queryController,
          routeDraftController: routeDraftController,
          stationRepository: _RecordingStationSearchRepository(
            results: [_searchResult],
          ),
          favoriteRepository: favorite,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      queryController.text = '서울';
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('stationSearchFavorite-station-seoul-line-1')),
      );
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());

      expect(find.text('즐겨찾기를 추가하지 못했어요.'), findsOneWidget);
    },
  );

  testWidgets('disposed session은 late history와 favorite completions를 무시한다', (
    tester,
  ) async {
    final queryController = TextEditingController();
    final routeDraftController = RouteDraftController();
    final searchCompleter = Completer<List<StationSearchResult>>();
    final historyCompleter = Completer<List<RecentSearchEntry>>();
    final favoriteCompleter = Completer<List<FavoriteStation>>();
    final history = _SearchHistoryRepository(
      entries: const [],
      listCompleter: historyCompleter,
    );
    final favorite = _FavoriteStationRepository(
      listCompleter: favoriteCompleter,
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
        favoriteRepository: favorite,
      ),
    );
    key.currentState!.submitSearch('서울');
    await tester.pumpWidget(const SizedBox.shrink());
    searchCompleter.complete(const []);
    historyCompleter.complete([_recentStation]);
    favoriteCompleter.complete([_favoriteStation]);
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

  for (final failAfterDispose in [false, true]) {
    testWidgets(
      'disposed session은 late favorite ${failAfterDispose ? 'error' : 'success'}를 무시한다',
      (tester) async {
        final queryController = TextEditingController();
        final routeDraftController = RouteDraftController();
        final saveCompleter = Completer<FavoriteStation>();
        final favorite = _FavoriteStationRepository(
          saveCompleter: saveCompleter,
        );
        addTearDown(queryController.dispose);
        addTearDown(routeDraftController.dispose);

        await tester.pumpWidget(
          _session(
            queryController: queryController,
            routeDraftController: routeDraftController,
            stationRepository: _RecordingStationSearchRepository(
              results: [_searchResult],
            ),
            favoriteRepository: favorite,
          ),
        );
        await tester.pump();
        queryController.text = '서울';
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('stationSearchFavorite-station-seoul-line-1')),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        if (failAfterDispose) {
          saveCompleter.completeError(StateError('late save failed'));
        } else {
          saveCompleter.complete(_favoriteStation);
        }
        await tester.pump();

        expect(
          tester.takeException(),
          failAfterDispose ? isA<StateError>() : isNull,
        );
      },
    );
  }

  test('root는 public app owner를 쓰고 private session 선언을 갖지 않는다', () {
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    expect(root, contains("import 'network_map_search_session.dart';"));
    expect(root, contains('GlobalKey<NetworkMapSearchSessionState>'));
    expect(root, contains('return NetworkMapSearchSession('));
    expect(root, isNot(contains('class _NetworkMapSearchSession')));
    expect(root, isNot(contains('class _NetworkMapSearchSessionState')));
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
  FavoriteStationRepository? favoriteRepository,
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
        favoriteRepository: favoriteRepository,
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

final _favoriteStation = FavoriteStation(
  userId: 'user',
  stationId: 'station-seoul',
  lineId: 'line-1',
  nameKo: '서울',
  nameEn: 'Seoul',
  region: '수도권',
  dataQualityLevel: 'VERIFIED',
  lastVerifiedAt: '2026-08-13T00:00:00Z',
  lines: const [_line],
  addedAt: '2026-08-13T00:00:00Z',
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

class _FavoriteStationRepository implements FavoriteStationRepository {
  _FavoriteStationRepository({
    this.favorites = const [],
    this.listError,
    this.saveError,
    this.listCompleter,
    this.saveCompleter,
  });

  List<FavoriteStation> favorites;
  final Object? listError;
  final Object? saveError;
  final Completer<List<FavoriteStation>>? listCompleter;
  final Completer<FavoriteStation>? saveCompleter;
  final saved = <({String stationId, String? lineId})>[];
  final removed = <({String stationId, String? lineId})>[];

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final completer = listCompleter;
    if (completer != null) {
      return completer.future;
    }
    final error = listError;
    if (error != null) {
      throw error;
    }
    return favorites;
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(
    String stationId, {
    String? lineId,
  }) async {
    saved.add((stationId: stationId, lineId: lineId));
    final completer = saveCompleter;
    if (completer != null) {
      return completer.future;
    }
    final error = saveError;
    if (error != null) {
      throw error;
    }
    favorites = [_favoriteStation];
    return _favoriteStation;
  }

  @override
  Future<void> removeFavoriteStation(String stationId, {String? lineId}) async {
    removed.add((stationId: stationId, lineId: lineId));
    favorites = [];
  }
}
