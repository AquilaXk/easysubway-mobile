import 'dart:io';

import 'package:easysubway_mobile/app/network_map_search_session.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
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

    expect(repository.requests, [
      (query: '강남', region: '수도권'),
    ]);
  });

  testWidgets('active query의 region 변경을 새 지역 검색으로 넘긴다', (
    tester,
  ) async {
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

  test('root는 public app owner를 쓰고 private session 선언을 갖지 않는다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    expect(
      root,
      contains("import 'app/network_map_search_session.dart';"),
    );
    expect(root, contains('GlobalKey<NetworkMapSearchSessionState>'));
    expect(root, contains('return NetworkMapSearchSession('));
    expect(root, isNot(contains('class _NetworkMapSearchSession')));
    expect(root, isNot(contains('class _NetworkMapSearchSessionState')));
  });
}

class _RecordingStationSearchRepository implements StationSearchRepository {
  final requests = <({String query, String? region})>[];

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async {
    requests.add((query: query, region: region));
    return const [];
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
