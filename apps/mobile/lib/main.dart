import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import 'app/app_bootstrap.dart';
import 'app/app_endpoints.dart';
import 'app/demo_dependencies.dart';
import 'app/easy_subway_app.dart';
import 'app/next_train_widget_timetable_composition.dart';
import 'core/crashlytics/mobile_crash_reporting.dart';
import 'core/external/kakao_map_configuration.dart';
import 'features/ads/active_ad_banner.dart';
import 'features/ads/ad_repository.dart';
import 'features/get_off_alarm/get_off_alarm_controller.dart';
import 'features/home_widget/home_widget_link_handler.dart';
import 'features/home_widget/next_train_widget_repository.dart';
import 'features/home_widget/next_train_widget_runtime.dart'
    as next_train_widget_runtime;
import 'features/facility_report/data/image_picker_facility_report_photo_picker.dart';
import 'features/facility_report/data/secure_facility_report_draft_target_store.dart';
import 'features/facility_report/domain/facility_report_location.dart';
import 'features/facility_report/presentation/facility_report_screen.dart';
import 'features/favorites/domain/favorite_route.dart';
import 'features/favorites/favorite_facility.dart';
import 'features/stations/domain/station_repositories.dart';
import 'features/stations/presentation/station_detail_screen.dart';
import 'legacy_credential_cleanup.dart';
import 'mobile_error_reporter.dart';
import 'features/onboarding/onboarding.dart';

const defaultPushNotificationsEnabled = bool.fromEnvironment(
  'EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);

typedef MainCrashReportingInitializer =
    Future<bool> Function({required bool isReleaseMode});
typedef MainAppBootstrapInitializer =
    Future<AppBootstrap> Function({
      required bool enablePushNotifications,
      FavoriteStationRepository? favoriteRepository,
      FavoriteFacilityRepository? favoriteFacilityRepository,
      FavoriteRouteRepository? favoriteRouteRepository,
      SearchHistoryRepository? searchHistoryRepository,
    });
typedef MainNextTrainWidgetStartup =
    Future<void> Function({
      required Future<List<int>> Function() installedWidgetIds,
      required Future<void> Function() registerRefresh,
      required Future<void> Function() cancelRefresh,
      required Future<void> Function(List<int> widgetIds) refresh,
      required void Function(Object error, StackTrace stackTrace) reportError,
    });
typedef MainNextTrainWidgetCallbackInstaller =
    void Function({required Future<bool> Function() runWidgetRefresh});
typedef MainNextTrainWidgetConfigurator =
    Future<void> Function({
      required next_train_widget_runtime.CreateNextTrainWidgetTimetableRepository
      createTimetableRepository,
      required Future<void> Function() initializeAndRegisterRefresh,
    });
typedef MainNextTrainWidgetHeadlessRunner =
    Future<bool> Function({
      required next_train_widget_runtime.CreateNextTrainWidgetTimetableRepository
      createTimetableRepository,
    });

@visibleForTesting
MainCrashReportingInitializer debugMainCrashReportingInitializer =
    initializeMobileCrashReporting;
@visibleForTesting
MainAppBootstrapInitializer debugMainAppBootstrapInitializer =
    AppBootstrap.initialize;
@visibleForTesting
Future<void> Function() debugMainWorkManagerInitializer =
    initializeMainWorkManagerDispatcher;
@visibleForTesting
Future<void> Function(GetOffAlarmController?) debugMainAlarmRestorer =
    restoreGetOffAlarmState;
@visibleForTesting
MainNextTrainWidgetStartup debugMainNextTrainWidgetStartup =
    next_train_widget_runtime.runNextTrainWidgetStartup;
@visibleForTesting
MainNextTrainWidgetCallbackInstaller debugMainNextTrainWidgetCallbackInstaller =
    next_train_widget_runtime.nextTrainWidgetCallbackDispatcher;
@visibleForTesting
Future<bool> Function() debugMainHeadlessWidgetRefresh =
    runMainHeadlessNextTrainWidgetRefresh;
@visibleForTesting
MainNextTrainWidgetConfigurator debugMainNextTrainWidgetConfigurator =
    next_train_widget_runtime.configureMain;
@visibleForTesting
MainNextTrainWidgetHeadlessRunner debugMainNextTrainWidgetHeadlessRunner =
    next_train_widget_runtime.runHeadlessNextTrainWidgetRefresh;
@visibleForTesting
Stream<Uri?> Function() debugMainHomeWidgetClicks =
    next_train_widget_runtime.homeWidgetClicks;
@visibleForTesting
void Function(Widget) debugMainRunApp = runApp;

WidgetBuilder? _stationDetailBottomAdBuilder(AdRepository? repository) {
  if (repository == null) return null;
  return (_) => ActiveAdBanner(
    key: const Key('stationDetailBottomAdBanner'),
    repository: repository,
    placement: AdPlacement.stationDetailBottom,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validateKakaoMapConfiguration(
    nativeAppKey: kakaoMapNativeAppKey,
    isReleaseMode: kReleaseMode,
  );
  installMobileErrorHandlers();
  await debugMainCrashReportingInitializer(isReleaseMode: kReleaseMode);
  if (kakaoMapNativeAppKey.trim().isNotEmpty) {
    try {
      await KakaoMapSdk.instance.initialize(kakaoMapNativeAppKey);
      markKakaoMapSdkInitialized();
    } catch (error, stackTrace) {
      reportMobileError(
        StateError('Kakao Map SDK initialization failed: ${error.runtimeType}'),
        stackTrace,
        context: '카카오맵 SDK 초기화 실패',
      );
    }
  }
  registerBundledAssetLicenses();
  validateReleaseBuildFlags(
    isReleaseMode: kReleaseMode,
    demoHomeDataEnabled: defaultDemoHomeDataEnabled,
  );
  final bootstrap = await debugMainAppBootstrapInitializer(
    enablePushNotifications: defaultPushNotificationsEnabled,
    favoriteRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteStationRepository()
        : null,
    favoriteFacilityRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteFacilityRepository()
        : null,
    favoriteRouteRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteRouteRepository()
        : null,
    searchHistoryRepository: defaultDemoHomeDataEnabled
        ? DemoSearchHistoryRepository()
        : null,
  );
  // process-wide WorkManager dispatcher를 app bootstrap에서 정확히 1회 초기화한다.
  // 이후 하차 알림 복원과 위젯 startup은 각자 등록만 수행한다(재초기화 금지).
  await debugMainWorkManagerInitializer();
  await debugMainAlarmRestorer(bootstrap.dependencies.getOffAlarmController);
  final nextTrainWidgetRepository = NextTrainWidgetRepository(
    catalogDatabase: bootstrap.catalogDatabase,
    userDatabase: bootstrap.userDatabase,
    timetableRepository: bootstrap.dependencies.stationTimetableRepository,
  );
  await debugMainNextTrainWidgetStartup(
    installedWidgetIds: next_train_widget_runtime.installedNextTrainWidgetIds,
    registerRefresh: next_train_widget_runtime.registerNextTrainWidgetRefresh,
    cancelRefresh: next_train_widget_runtime.cancelNextTrainWidgetRefresh,
    refresh: (widgetIds) => next_train_widget_runtime.refreshNextTrainWidgets(
      nextTrainWidgetRepository,
      widgetIds: widgetIds,
    ),
    reportError: (error, stackTrace) =>
        reportMobileError(error, stackTrace, context: '홈 위젯 초기화 중 예외가 발생했습니다.'),
  );
  final photoPicker = ImagePickerFacilityReportPhotoPicker();
  final navigatorKey = GlobalKey<NavigatorState>();
  final onboardingStore = const SecureOnboardingResultStore();
  final draftTargetStore = const SecureFacilityReportDraftTargetStore();
  debugMainRunApp(
    AppBootstrapLifecycle(
      close: bootstrap.close,
      resumeDataPackUpdate: () async {
        await bootstrap.resumeDataPackUpdate();
        await next_train_widget_runtime.runNextTrainWidgetOperationSafely(
          operation: () => next_train_widget_runtime.refreshNextTrainWidgets(
            nextTrainWidgetRepository,
          ),
          reportError: (error, stackTrace) => reportMobileError(
            error,
            stackTrace,
            context: '홈 위젯 갱신 중 예외가 발생했습니다.',
          ),
        );
      },
      resumeGetOffAlarmState: () => reconcileGetOffAlarmState(
        bootstrap.dependencies.getOffAlarmController,
      ),
      child: HomeWidgetLinkHandler(
        clicks: debugMainHomeWidgetClicks(),
        navigatorKey: navigatorKey,
        stationDetailBuilder: (stationId) => StationDetailScreen(
          repository: bootstrap.dependencies.repository,
          reportRepository: bootstrap.dependencies.reportRepository,
          favoriteRepository: bootstrap.dependencies.favoriteRepository,
          bottomAdBuilder: _stationDetailBottomAdBuilder(
            bootstrap.dependencies.adRepository,
          ),
          realtimeRepository: bootstrap.dependencies.realtimeRepository,
          timetableRepository:
              bootstrap.dependencies.stationTimetableRepository,
          locationProvider: bootstrap.dependencies.locationProvider,
          stationId: stationId,
          facilityReportDraftTargetStore: draftTargetStore,
          onOpenFacilityReport: (target) {
            return navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => FacilityReportScreen(
                  repository: bootstrap.dependencies.reportRepository,
                  locationLoader: () async {
                    try {
                      final location = await bootstrap
                          .dependencies
                          .locationProvider
                          .currentLocation();
                      return FacilityReportLocation(
                        latitude: location.latitude,
                        longitude: location.longitude,
                      );
                    } on CurrentLocationException catch (error) {
                      throw FacilityReportLocationException(error.message);
                    }
                  },
                  needsLocationPermissionRequest: bootstrap
                      .dependencies
                      .locationProvider
                      .needsLocationPermissionRequest,
                  openLocationSettings: bootstrap
                      .dependencies
                      .locationProvider
                      .openLocationSettings,
                  draftTargetStore: draftTargetStore,
                  target: target,
                ),
              ),
            );
          },
        ),
        child: EasySubwayApp(
          navigatorKey: navigatorKey,
          dependencies: bootstrap.dependencies,
          onboardingStore: onboardingStore,
          facilityReportDraftTargetStore: draftTargetStore,
          facilityReportLostPhotoRestorer: photoPicker.retrieveLostPhoto,
          legacyCredentialCleaner: const SecureLegacyCredentialCleaner(),
          dataPackUpdateStateRepository: createDataPackUpdateStateRepository(
            userDatabase: bootstrap.userDatabase,
            endpoints: AppEndpoints.fromEnvironment(),
          ),
          onDataPackMeteredConsent: bootstrap.acceptMeteredDataPackUpdate,
          dataPackUpdate: bootstrap.dataPackUpdate,
          bundledDataPackFreshness: bootstrap.bundledDataPackFreshness,
        ),
      ),
    ),
  );
}

@visibleForTesting
void registerBundledAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['empty-notices-illustration'],
      '''
Empty notices illustration from Customer Relation Vectors With Faces
Author: Anton Kalashnyk
Source: https://www.svgrepo.com/collection/customer-relation-vectors-with-faces/
License: CC Attribution
License URL: https://www.svgrepo.com/page/licensing/#CC%20Attribution
Changes: converted from SVG to PNG and colorized for EasySubway.
''',
    );
    yield const LicenseEntryWithLineBreaks(
      ['empty-recent-search-warning-illustration'],
      '''
Empty recent-search warning illustration
Source: https://www.svgrepo.com/svg/501793/warning
License: SVG Repo (see SVG Repo licensing)
License URL: https://www.svgrepo.com/page/licensing/
Changes: converted from SVG to PNG and colorized for EasySubway.
''',
    );
  });
}

@pragma('vm:entry-point')
Future<void> configureMain() => debugMainNextTrainWidgetConfigurator(
  createTimetableRepository: createNextTrainWidgetTimetableRepository,
  initializeAndRegisterRefresh: initializeAndRegisterNextTrainWidgetRefresh,
);

@pragma('vm:entry-point')
void nextTrainWidgetCallbackDispatcher() {
  debugMainNextTrainWidgetCallbackInstaller(
    runWidgetRefresh: debugMainHeadlessWidgetRefresh,
  );
}

Future<bool> runMainHeadlessNextTrainWidgetRefresh() {
  return debugMainNextTrainWidgetHeadlessRunner(
    createTimetableRepository: createNextTrainWidgetTimetableRepository,
  );
}

Future<void> initializeMainWorkManagerDispatcher() {
  return next_train_widget_runtime.initializeWorkManagerDispatcher(
    callbackDispatcher: nextTrainWidgetCallbackDispatcher,
  );
}

Future<void> initializeAndRegisterNextTrainWidgetRefresh() {
  return next_train_widget_runtime.initializeAndRegisterNextTrainWidgetRefresh(
    callbackDispatcher: nextTrainWidgetCallbackDispatcher,
  );
}

@visibleForTesting
Future<void> restoreGetOffAlarmState(GetOffAlarmController? controller) async {
  try {
    await controller?.restore();
  } catch (error, stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 시작 상태 복원 중 예외가 발생했습니다.',
    );
  }
}

@visibleForTesting
Future<void> reconcileGetOffAlarmState(
  GetOffAlarmController? controller,
) async {
  try {
    await controller?.reconcile();
  } catch (error, stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 foreground 상태 재조정 중 예외가 발생했습니다.',
    );
  }
}

void validateReleaseBuildFlags({
  required bool isReleaseMode,
  required bool demoHomeDataEnabled,
}) {
  if (isReleaseMode && demoHomeDataEnabled) {
    throw StateError('EASYSUBWAY_DEMO_HOME_DATA is not allowed in release.');
  }
}
