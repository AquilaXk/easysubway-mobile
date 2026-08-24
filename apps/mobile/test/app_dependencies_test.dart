import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_exception.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_location.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_request.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_target.dart';
import 'package:easysubway_mobile/features/facility_report/presentation/facility_report_screen.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:easysubway_mobile/features/ads/active_ad_banner.dart';
import 'package:easysubway_mobile/features/home_widget/home_widget_link_handler.dart';
import 'package:easysubway_mobile/features/journey/data/journey_api_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_models.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  testWidgets('production main은 홈 위젯 역 상세·시설 제보 composition을 그대로 배선한다', (
    tester,
  ) async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    final locationProvider = _MutableCurrentLocationProvider();
    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      locationProvider: locationProvider,
      apiBaseUri: () => null,
      enablePushNotifications: false,
    );
    final bootstrap = AppBootstrap(
      dependencies: dependencies,
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      dataPackUpdate: Future<void>.value(),
      resumeDataPackUpdate: () async {},
      acceptMeteredDataPackUpdate: () async {},
      bundledDataPackFreshness: null,
    );
    final previousFlutterError = FlutterError.onError;
    final previousPlatformError = PlatformDispatcher.instance.onError;
    final previousCrashInitializer = app.debugMainCrashReportingInitializer;
    final previousBootstrapInitializer = app.debugMainAppBootstrapInitializer;
    final previousWorkManagerInitializer = app.debugMainWorkManagerInitializer;
    final previousAlarmRestorer = app.debugMainAlarmRestorer;
    final previousWidgetStartup = app.debugMainNextTrainWidgetStartup;
    final previousClicks = app.debugMainHomeWidgetClicks;
    final previousRunApp = app.debugMainRunApp;
    late Widget root;
    addTearDown(() async {
      FlutterError.onError = previousFlutterError;
      PlatformDispatcher.instance.onError = previousPlatformError;
      app.debugMainCrashReportingInitializer = previousCrashInitializer;
      app.debugMainAppBootstrapInitializer = previousBootstrapInitializer;
      app.debugMainWorkManagerInitializer = previousWorkManagerInitializer;
      app.debugMainAlarmRestorer = previousAlarmRestorer;
      app.debugMainNextTrainWidgetStartup = previousWidgetStartup;
      app.debugMainHomeWidgetClicks = previousClicks;
      app.debugMainRunApp = previousRunApp;
      await catalogDatabase.close();
      await userDatabase.close();
    });

    app.debugMainCrashReportingInitializer = ({required isReleaseMode}) async =>
        true;
    app.debugMainAppBootstrapInitializer =
        ({
          required enablePushNotifications,
          favoriteRepository,
          favoriteFacilityRepository,
          favoriteRouteRepository,
          searchHistoryRepository,
        }) async => bootstrap;
    app.debugMainWorkManagerInitializer = () async {};
    app.debugMainAlarmRestorer = (_) async {};
    app.debugMainNextTrainWidgetStartup =
        ({
          required installedWidgetIds,
          required registerRefresh,
          required cancelRefresh,
          required refresh,
          required reportError,
        }) async {};
    app.debugMainHomeWidgetClicks = () => const Stream<Uri?>.empty();
    app.debugMainRunApp = (widget) => root = widget;

    await app.main();

    final lifecycle = root as AppBootstrapLifecycle;
    final linkHandler = lifecycle.child as HomeWidgetLinkHandler;
    final detail =
        linkHandler.stationDetailBuilder('station-sangnoksu')
            as StationDetailScreen;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: linkHandler.navigatorKey,
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(detail.stationId, 'station-sangnoksu');
    expect(detail.repository, same(dependencies.repository));
    expect(detail.reportRepository, same(dependencies.reportRepository));
    expect(detail.bottomAdBuilder!(context), isA<ActiveAdBanner>());

    const target = FacilityReportTarget(
      stationId: 'station-sangnoksu',
      stationName: '상록수',
      facilityId: 'elevator-1',
      facilityName: '1번 출구 엘리베이터',
      facilityTypeLabel: '엘리베이터',
      facilityStatusLabel: '운행 중',
    );
    final pushed = detail.onOpenFacilityReport!(target);
    await tester.pumpAndSettle();
    final reportScreen = tester.widget<FacilityReportScreen>(
      find.byType(FacilityReportScreen),
    );
    expect(reportScreen.target, same(target));
    final location = await reportScreen.locationLoader!();
    expect(location.latitude, 37.321);
    expect(location.longitude, 126.831);
    locationProvider.error = const CurrentLocationException('위치 사용 불가');
    await expectLater(
      reportScreen.locationLoader!(),
      throwsA(
        isA<FacilityReportLocationException>().having(
          (error) => error.message,
          'message',
          '위치 사용 불가',
        ),
      ),
    );
    linkHandler.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await pushed;
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

  test('API 주소가 있으면 Journey V3 repository만 release route로 만든다', () {
    final dependencies = AppDependencies.resolve(
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () => Uri.parse('https://api.example.com'),
      enablePushNotifications: false,
    );

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

    await expectLater(
      dependencies.journeyRepository.issueSession(
        JourneySessionRequest(
          integrityToken: 'integrity-token',
          clientNonce: 'AAAAAAAAAAAAAAAAAAAAAA',
        ),
      ),
      throwsA(isA<JourneyTransportFailure>()),
    );
    await expectLater(
      dependencies.journeyRepository.searchJourneys(
        JourneySearchRequest(
          requestId: '01J00000000000000000000000',
          originStationId: 'station-origin',
          destinationStationId: 'station-destination',
          departure: const JourneyDepartureNow(),
          timePolicy: TimePolicy.timetableRequired,
          walkingPace: WalkingPace.standard,
          mobilityProfile: MobilityProfile.standard,
          constraintMode: ConstraintMode.none,
          maxTransfers: 3,
          alternativeCount: 3,
        ),
        sessionToken: 'unused',
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

    server.listen((request) async {
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
        );
      await request.response.close();
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

class _MutableCurrentLocationProvider implements CurrentLocationProvider {
  Object? error;

  @override
  Future<CurrentLocation> currentLocation() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return const CurrentLocation(latitude: 37.321, longitude: 126.831);
  }

  @override
  Future<bool> needsLocationPermissionRequest() async => false;

  @override
  Future<bool> openLocationSettings() async => true;
}
