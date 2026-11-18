import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/features/network_map/application/network_map_region_bridge.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapitalOnlyNetworkMapRepository implements NetworkMapRepository {
  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    final isCapital = region == null || region == '수도권' || region == '수도권권';
    if (!isCapital) {
      // 수도권 외 지역은 번들에 없어 데이터가 비어있음
      return const NetworkMapData(
        regions: [NetworkMapRegion(name: '수도권')],
        selectedRegion: '부산',
        lines: [],
        stations: [],
        edges: [],
        positionSources: [],
      );
    }
    return const NetworkMapData(
      regions: [NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: [
        NetworkMapLine(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A4E3',
          region: '수도권',
        ),
      ],
      stations: [
        NetworkMapStation(
          id: 'station-sangnoksu',
          nameKo: '상록수',
          nameEn: 'Sangnoksu',
          region: '수도권',
          lineId: 'seoul-4',
          stationCode: '448',
          sequence: 1,
          position: NetworkMapPosition(
            x: 100,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'test-src',
          ),
        ),
      ],
      edges: [],
      positionSources: [],
    );
  }
}

class _NationwideNetworkMapRepository
    implements NetworkMapRepository, StationSearchRepository {
  static const _regions = <NetworkMapRegion>[
    NetworkMapRegion(name: '광주권'),
    NetworkMapRegion(name: '대구권'),
    NetworkMapRegion(name: '대전권'),
    NetworkMapRegion(name: '부산권'),
    NetworkMapRegion(name: '수도권'),
  ];

  static String _normalizeRegion(String? region) {
    return switch (region?.trim()) {
      null || '' || '수도권' || '수도권권' => '수도권',
      '부산' || '부산권' => '부산권',
      '대구' || '대구권' => '대구권',
      '광주' || '광주권' => '광주권',
      '대전' || '대전권' => '대전권',
      final other => other,
    };
  }

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    final storedRegion = _normalizeRegion(region);
    final stationId = switch (storedRegion) {
      '부산권' => 'station-seomyeon',
      '대구권' => 'station-banwoldang',
      '광주권' => 'station-sangmu',
      '대전권' => 'station-city-hall',
      _ => 'station-sangnoksu',
    };
    final stationName = switch (storedRegion) {
      '부산권' => '서면',
      '대구권' => '반월당',
      '광주권' => '상무',
      '대전권' => '시청',
      _ => '상록수',
    };
    final lineIdForRegion = switch (storedRegion) {
      '부산권' => 'busan-1',
      '대구권' => 'daegu-1',
      '광주권' => 'gwangju-1',
      '대전권' => 'daejeon-1',
      _ => 'seoul-4',
    };
    return NetworkMapData(
      regions: _regions,
      selectedRegion: storedRegion,
      lines: [
        NetworkMapLine(
          id: lineIdForRegion,
          name: '$storedRegion 1호선',
          color: '#00A4E3',
          region: storedRegion,
        ),
      ],
      stations: [
        NetworkMapStation(
          id: stationId,
          nameKo: stationName,
          nameEn: stationId,
          region: storedRegion,
          lineId: lineIdForRegion,
          stationCode: '101',
          sequence: 1,
          position: const NetworkMapPosition(
            x: 100,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'test-src',
          ),
        ),
      ],
      edges: const [],
      positionSources: const [
        NetworkMapPositionSource(
          id: 'test-src',
          name: 'Test source',
          licenseStatus: 'fixture-only',
        ),
      ],
    );
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    return [
      StationSearchResult(
        id: 'station-sangnoksu',
        nameKo: '상록수',
        nameEn: 'Sangnoksu',
        region: '수도권',
        dataQualityLevel: 'VERIFIED_PUBLIC_DATA',
        lastVerifiedAt: '2026-09-09',
        lines: [
          StationSearchLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A4E3',
            stationCode: '448',
          ),
        ],
      ),
    ];
  }

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async => const [];

  @override
  Future<StationDetail> getStationDetail(String stationId) =>
      throw UnimplementedError();

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async =>
      const [];

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async => const [];
}

class _FixedCapitalLocationProvider implements CurrentLocationProvider {
  @override
  Future<bool> needsLocationPermissionRequest() async => false;

  @override
  Future<CurrentLocation> currentLocation() async {
    return CurrentLocation(
      latitude: 37.3028,
      longitude: 126.8664,
      accuracyMeters: 12,
      measuredAt: DateTime.now(),
    );
  }

  @override
  Future<bool> openLocationSettings() async => true;
}

class _InMemoryViewportRepository implements NetworkMapViewportRepository {
  _InMemoryViewportRepository({this.selectedRegion});

  String? selectedRegion;
  final Map<String, Rect> viewports = <String, Rect>{};

  @override
  Future<String?> loadSelectedRegion() async => selectedRegion;

  @override
  Future<void> saveSelectedRegion(String region) async {
    selectedRegion = region;
  }

  @override
  Future<Rect?> loadViewport(String region) async => viewports[region];

  @override
  Future<void> saveViewport({
    required String region,
    required Rect viewport,
  }) async {
    viewports[region] = viewport;
  }
}

void main() {
  testWidgets('오프라인 미내장 지역 선택 시 침묵 리셋하지 않고 스낵바 피드백을 제공한다', (tester) async {
    final repository = _CapitalOnlyNetworkMapRepository();
    final routeDraftController = RouteDraftController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkMapScreen(
            repository: repository,
            routeDraftController: routeDraftController,
            onOpenStationSearch: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 현재 지역이 '수도권'임을 확인
    expect(find.text('수도권'), findsWidgets);

    // 지역 드롭다운 열기
    await tester.tap(find.byKey(const Key('networkMapRegionDropdown')));
    await tester.pumpAndSettle();

    // 드롭다운에 5대 대도시권(수도권, 광주, 대구, 대전, 부산)이 지원되어야 함
    expect(
      find.byKey(const ValueKey('networkMapRegionMenuRow_부산')),
      findsOneWidget,
    );

    // 미내장 지역 '부산' 탭
    await tester.tap(find.byKey(const ValueKey('networkMapRegionMenuRow_부산')));
    // 스낵바는 4초만 보인다. 바탕 타일 굽기가 프레임을 요청하는 동안 pumpAndSettle은
    // 가짜 시계를 그만큼 밀어 스낵바가 사라진 뒤에 돌아오므로, 스낵바가 보이는 짧은
    // 시간만 돌린다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 안내 스낵바가 표시되어야 함
    expect(
      find.text('부산 지역은 내장된 오프라인 데이터가 없어 수도권 노선도로 유지됩니다.'),
      findsOneWidget,
    );

    // 노선도는 수도권으로 안전하게 유지됨
    expect(find.text('수도권'), findsWidgets);
  });

  testWidgets('위치 권한이 허용되어 현재 위치가 수도권이어도 권역을 전환하면 선택 권역과 저장 상태가 즉시 유지된다', (
    tester,
  ) async {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
    addTearDown(() {
      resetNetworkMapOwnerLabelsCacheForTest();
      resetNetworkMapOwnerNodesCacheForTest();
    });

    final repository = _NationwideNetworkMapRepository();
    final viewportRepository = _InMemoryViewportRepository();
    final regionBridge = NetworkMapRegionBridge();
    final reportedLabels = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkMapScreen(
            repository: repository,
            stationSearchRepository: repository,
            locationProvider: _FixedCapitalLocationProvider(),
            viewportRepository: viewportRepository,
            regionBridge: regionBridge,
            onRegionLabelChanged: reportedLabels.add,
            routeDraftController: RouteDraftController(),
            onOpenStationSearch: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final (menuRowKey, expectedLabel, expectedStoredRegion) in const [
      ('networkMapRegionMenuRow_부산권', '부산', '부산권'),
      ('networkMapRegionMenuRow_대구권', '대구', '대구권'),
      ('networkMapRegionMenuRow_광주권', '광주', '광주권'),
      ('networkMapRegionMenuRow_대전권', '대전', '대전권'),
    ]) {
      await tester.tap(find.byKey(const Key('networkMapRegionDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(menuRowKey)));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('networkMapRegionDropdown')),
          matching: find.text(expectedLabel),
        ),
        findsOneWidget,
      );
      expect(viewportRepository.selectedRegion, expectedStoredRegion);
      expect(reportedLabels.last, expectedLabel);
    }
  });

  testWidgets('저장된 비수도권 권역을 복원한 시작 경로에서 수도권 GPS가 저장 권역을 덮어쓰지 않는다', (
    tester,
  ) async {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
    addTearDown(() {
      resetNetworkMapOwnerLabelsCacheForTest();
      resetNetworkMapOwnerNodesCacheForTest();
    });

    final repository = _NationwideNetworkMapRepository();
    final viewportRepository = _InMemoryViewportRepository(
      selectedRegion: '광주권',
    );
    final reportedLabels = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkMapScreen(
            repository: repository,
            stationSearchRepository: repository,
            locationProvider: _FixedCapitalLocationProvider(),
            viewportRepository: viewportRepository,
            onRegionLabelChanged: reportedLabels.add,
            routeDraftController: RouteDraftController(),
            onOpenStationSearch: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRegionDropdown')),
        matching: find.text('광주'),
      ),
      findsOneWidget,
    );
    expect(viewportRepository.selectedRegion, '광주권');
    expect(reportedLabels.last, '광주');
  });

  testWidgets('오너 노드 sidecar 로드 실패 시에도 NetworkMapScreen은 정상 초기화된다', (
    tester,
  ) async {
    final repository = _CapitalOnlyNetworkMapRepository();
    final routeDraftController = RouteDraftController();
    final reportedErrors = <FlutterErrorDetails>[];
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheErrorForTest(
      Exception('sidecar load failed'),
    );
    addTearDown(() {
      resetNetworkMapOwnerLabelsCacheForTest();
      resetNetworkMapOwnerNodesCacheForTest();
    });

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkMapScreen(
              repository: repository,
              routeDraftController: routeDraftController,
              onOpenStationSearch: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(find.text('수도권'), findsWidgets);
    expect(reportedErrors, isNotEmpty);
  });
}
