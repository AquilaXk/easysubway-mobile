import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_exception.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_request.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:easysubway_mobile/features/journey/data/journey_api_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_models.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 공지 일러스트 CC Attribution을 라이선스 화면에 등록한다', () async {
    app.registerBundledAssetLicenses();

    final entry = await LicenseRegistry.licenses.firstWhere(
      (entry) => entry.packages.contains('empty-notices-illustration'),
    );
    final text = entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

    expect(text, contains('Anton Kalashnyk'));
    expect(text, contains('Customer Relation Vectors With Faces'));
    expect(
      text,
      contains(
        'https://www.svgrepo.com/collection/customer-relation-vectors-with-faces/',
      ),
    );
    expect(
      text,
      contains('https://www.svgrepo.com/page/licensing/#CC%20Attribution'),
    );
  });

  test('최근 검색 빈 상태 경고 일러스트 출처를 라이선스 화면에 등록한다', () async {
    app.registerBundledAssetLicenses();

    final entry = await LicenseRegistry.licenses.firstWhere(
      (entry) =>
          entry.packages.contains('empty-recent-search-warning-illustration'),
    );
    final text = entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

    expect(text, contains('https://www.svgrepo.com/svg/501793/warning'));
    expect(text, contains('https://www.svgrepo.com/page/licensing/'));
  });

  test(
    '광고 repository 주입 identity를 유지하고 기본값은 fetch 전 base URI를 읽지 않는다',
    () async {
      final catalogDatabase = CatalogDatabase.memory();
      final userDatabase = user_db.UserDatabase.memory();
      final injected = AdRepository(
        ApiClient(baseUri: Uri.parse('https://ads.example.test')),
      );
      var apiBaseReads = 0;
      addTearDown(catalogDatabase.close);
      addTearDown(userDatabase.close);

      final injectedDependencies = AppDependencies.resolve(
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
        adRepository: injected,
        apiBaseUri: () {
          apiBaseReads++;
          return null;
        },
        enablePushNotifications: false,
      );

      expect(injectedDependencies.adRepository, same(injected));
      expect(apiBaseReads, 0);

      final defaultDependencies = AppDependencies.resolve(
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
        apiBaseUri: () {
          apiBaseReads++;
          return null;
        },
        enablePushNotifications: false,
      );

      expect(apiBaseReads, 0);
      expect(
        await defaultDependencies.adRepository!.fetchActive(
          AdPlacement.routeResultBottom,
        ),
        isNull,
      );
      expect(apiBaseReads, 1);
    },
  );

  test('release build는 demo home data flag를 허용하지 않는다', () {
    expect(
      () => app.validateReleaseBuildFlags(
        isReleaseMode: true,
        demoHomeDataEnabled: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('로컬 데이터베이스가 있어도 release route fallback은 만들지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () {
        throw StateError('Local catalog defaults must not read API base URL.');
      },
      enablePushNotifications: true,
    );

    expect(dependencies.repository, isA<DriftStationRepository>());
    expect(dependencies.notificationRepository, isNotNull);
    expect(
      dependencies.reportRepository,
      isA<UnavailableFacilityReportRepository>(),
    );

    expect(dependencies.routeRepository, isNull);

    final internalNodes = await dependencies.internalRouteRepository
        .listRouteNodes('station-sangnoksu');

    expect(internalNodes, isEmpty);
  });

  test('로컬 데이터베이스 기본 의존성은 시설 신고 fallback 때문에 API 주소를 읽지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    var apiBaseReads = 0;
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () {
        apiBaseReads++;
        throw StateError('Local app defaults must not read API base URL.');
      },
      enablePushNotifications: false,
    );

    expect(apiBaseReads, 0);
    expect(dependencies.repository, isA<DriftStationRepository>());
  });

  test('주입 routeRepository는 online-first flag가 켜져도 API 주소를 읽지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    final injectedRouteRepository = _InjectedRouteSearchRepository();
    var apiBaseReads = 0;
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      reportRepository: const UnavailableFacilityReportRepository(),
      routeRepository: injectedRouteRepository,
      apiBaseUri: () {
        apiBaseReads++;
        throw StateError(
          'Injected route repository must not read API base URL.',
        );
      },
      enablePushNotifications: false,
    );

    expect(apiBaseReads, 0);
    expect(dependencies.routeRepository, same(injectedRouteRepository));
  });

  test('API 주소가 있으면 Journey V3 repository만 release route로 만든다', () {
    final dependencies = AppDependencies.resolve(
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () => Uri.parse('https://api.example.com'),
      enablePushNotifications: false,
    );

    expect(dependencies.routeRepository, isNull);
    expect(dependencies.journeyRepository, isA<JourneyApiRepository>());
  });

  test('API 주소가 없으면 local로 강등하지 않고 Journey failure로 닫는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    addTearDown(catalogDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () => null,
      enablePushNotifications: false,
    );

    expect(dependencies.routeRepository, isNull);
    await expectLater(
      dependencies.journeyRepository.issueSession(
        JourneySessionRequest(
          integrityToken: 'integrity-token',
          clientNonce: 'AAAAAAAAAAAAAAAAAAAAAA',
        ),
      ),
      throwsA(isA<JourneyTransportFailure>()),
    );
  });

  test('로컬 데이터베이스와 API 주소가 있으면 실시간은 API를 호출한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    late Uri requestedUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    addTearDown(server.close);

    server.listen((request) {
      requestedUri = request.uri;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'FRESH',
              'receivedAt': '2026-06-26T08:00:00Z',
              'arrivals': <Object?>[],
            },
          }),
        )
        ..close();
    });

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () =>
          Uri.parse('http://${server.address.host}:${server.port}'),
      enablePushNotifications: false,
    );

    await dependencies.realtimeRepository.arrivals(
      const RealtimeStationQuery(
        stationId: 'station-sangnoksu',
        lineId: '4',
        stationQueryName: '상록수',
      ),
    );

    expect(requestedUri.path, '/api/v1/realtime/arrivals');
    expect(requestedUri.queryParameters['stationId'], 'station-sangnoksu');
  });

  test('시설 신고 기본 의존성은 API 주소가 없으면 호출 시점에 unavailable로 동작한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () => null,
      enablePushNotifications: false,
    );

    await expectLater(
      dependencies.reportRepository.createReport(
        const FacilityReportRequest(
          stationId: 'station-sangnoksu',
          facilityId: 'facility-elevator-sangnoksu-1',
          reportType: 'BROKEN',
          description: '승강기 고장',
        ),
      ),
      throwsA(isA<FacilityReportException>()),
    );
  });

  test('userDatabase가 있으면 운행 공지 조회 의존성이 배선된다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () => Uri.parse('https://example.test'),
      enablePushNotifications: false,
    );

    expect(dependencies.noticeRepository, isA<NoticeRepository>());
  });

  test('운행 공지 의존성은 resolve 시점에 API 주소를 읽지 않고, 주소가 없으면 unavailable이다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    var apiBaseReads = 0;
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () {
        apiBaseReads++;
        return null;
      },
      enablePushNotifications: false,
    );

    // 앱 시작 중에는 공개 공지 base URL을 강제 평가하지 않는다(선택 기능).
    expect(apiBaseReads, 0);

    final result = await dependencies.noticeRepository!.activeNotices();

    expect(result.notices, isEmpty);
    expect(result.stale, isFalse);
    expect(result.state, NoticeResultState.unavailable);
  });

  test('기차 검색은 첫 호출까지 API 주소를 읽지 않고 주소가 없으면 unavailable이다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    var apiBaseReads = 0;
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () {
        apiBaseReads++;
        return null;
      },
      enablePushNotifications: false,
    );

    expect(apiBaseReads, 0);
    await expectLater(
      dependencies.trainSearchRepository.stations('서울'),
      throwsA(
        isA<TrainSearchException>().having(
          (error) => error.kind,
          'kind',
          TrainSearchFailureKind.unavailable,
        ),
      ),
    );
    expect(apiBaseReads, 1);
  });

  test('로컬 데이터베이스가 없으면 API 주소 없는 원격 fallback을 만들지 않는다', () {
    expect(
      () => AppDependencies.resolve(
        apiBaseUri: () => null,
        enablePushNotifications: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release API base URL must be configured.',
        ),
      ),
    );
  });

  test(
    'Network Map capability는 station repository runtime type이 아니라 명시적 주입으로만 선택한다',
    () {
      final catalogDatabase = CatalogDatabase.memory();
      final dualInterfaceStationRepository = DriftStationRepository(
        database: catalogDatabase,
      );
      final explicitNetworkMapRepository = _InjectedNetworkMapRepository();
      addTearDown(catalogDatabase.close);

      final stationOnlyDependencies = AppDependencies.resolve(
        repository: dualInterfaceStationRepository,
        reportRepository: const UnavailableFacilityReportRepository(),
        routeRepository: _InjectedRouteSearchRepository(),
        apiBaseUri: () => Uri.parse('https://api.example.com'),
        enablePushNotifications: false,
      );

      expect(
        stationOnlyDependencies.repository,
        same(dualInterfaceStationRepository),
      );
      expect(
        stationOnlyDependencies.networkMapRepository,
        isNot(same(dualInterfaceStationRepository)),
      );

      final explicitDependencies = AppDependencies.resolve(
        repository: dualInterfaceStationRepository,
        networkMapRepository: explicitNetworkMapRepository,
        reportRepository: const UnavailableFacilityReportRepository(),
        routeRepository: _InjectedRouteSearchRepository(),
        apiBaseUri: () => Uri.parse('https://api.example.com'),
        enablePushNotifications: false,
      );

      expect(
        explicitDependencies.networkMapRepository,
        same(explicitNetworkMapRepository),
      );

      final defaultCatalogDependencies = AppDependencies.resolve(
        catalogDatabase: catalogDatabase,
        reportRepository: const UnavailableFacilityReportRepository(),
        routeRepository: _InjectedRouteSearchRepository(),
        apiBaseUri: () => Uri.parse('https://api.example.com'),
        enablePushNotifications: false,
      );

      expect(
        defaultCatalogDependencies.networkMapRepository,
        same(defaultCatalogDependencies.repository),
      );
    },
  );
}

class _InjectedRouteSearchRepository implements RouteSearchRepository {
  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    throw UnimplementedError();
  }
}

class _InjectedNetworkMapRepository implements NetworkMapRepository {
  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return NetworkMapData(
      regions: const [],
      selectedRegion: region ?? '',
      lines: const [],
      stations: const [],
      edges: const [],
      positionSources: const [],
    );
  }
}
