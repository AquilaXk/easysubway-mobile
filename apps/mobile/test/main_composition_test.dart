import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/ads/active_ad_banner.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_location.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_target.dart';
import 'package:easysubway_mobile/features/facility_report/presentation/facility_report_screen.dart';
import 'package:easysubway_mobile/features/home_widget/home_widget_link_handler.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
