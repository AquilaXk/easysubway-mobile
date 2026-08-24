import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/app/easy_subway_app.dart';
import 'package:easysubway_mobile/core/datapack/bundled_data_pack_freshness.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:easysubway_mobile/features/favorites/domain/favorite_route.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_photo.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_target.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/support/presentation/support_access_screen.dart';
import 'package:easysubway_mobile/legacy_credential_cleanup.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter/material.dart';

EasySubwayApp buildEasySubwayTestApp({
  AppDependencies? dependencies,
  StationSearchRepository? repository,
  FacilityReportRepository? reportRepository,
  FavoriteStationRepository? favoriteRepository,
  FavoriteFacilityRepository? favoriteFacilityRepository,
  FavoriteRouteRepository? favoriteRouteRepository,
  AdRepository? adRepository,
  Future<List<FavoriteRoute>>? recentRoutesFuture,
  SearchHistoryRepository? searchHistoryRepository,
  NetworkMapRepository? networkMapRepository,
  NetworkMapViewportRepository? networkMapViewportRepository,
  RealtimeRepository? realtimeRepository,
  NotificationSettingsRepository? notificationRepository,
  NotificationPermissionProvider? notificationPermissionProvider,
  CurrentLocationProvider? locationProvider,
  UserDataDeletionRepository? userDataDeletionRepository,
  NoticeRepository? noticeRepository,
  LegacyCredentialCleaner legacyCredentialCleaner =
      const NoLegacyCredentialCleaner(),
  OnboardingResultStore? onboardingStore,
  FacilityReportDraftTargetStore? facilityReportDraftTargetStore,
  FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer,
  SupportAccessInfo supportAccessInfo =
      const SupportAccessInfo.fromEnvironment(),
  SupportAccessLauncher supportAccessLauncher =
      const UrlLauncherSupportAccessLauncher(),
  DataPackUpdateStateRepository? dataPackUpdateStateRepository,
  Future<void> Function()? onDataPackMeteredConsent,
  Future<void>? dataPackUpdate,
  BundledDataPackFreshness? bundledDataPackFreshness,
  OnboardingState initialOnboardingState = const OnboardingState.initial(),
  bool enablePushNotifications = false,
  GlobalKey<NavigatorState>? navigatorKey,
  Key? key,
}) {
  // Widget fixtures use a dual-port fake; adapt it only at this test composition boundary.
  final fixtureNetworkMapRepository =
      networkMapRepository ??
      switch (repository) {
        final NetworkMapRepository dualPortRepository => dualPortRepository,
        _ => null,
      };

  return EasySubwayApp(
    dependencies:
        dependencies ??
        AppDependencies.resolve(
          repository: repository,
          reportRepository: reportRepository,
          favoriteRepository: favoriteRepository,
          favoriteFacilityRepository: favoriteFacilityRepository,
          favoriteRouteRepository: favoriteRouteRepository,
          adRepository: adRepository,
          searchHistoryRepository: searchHistoryRepository,
          networkMapRepository: fixtureNetworkMapRepository,
          networkMapViewportRepository: networkMapViewportRepository,
          realtimeRepository: realtimeRepository,
          notificationRepository: notificationRepository,
          notificationPermissionProvider: notificationPermissionProvider,
          locationProvider: locationProvider,
          userDataDeletionRepository: userDataDeletionRepository,
          noticeRepository: noticeRepository,
          enablePushNotifications: enablePushNotifications,
        ),
    recentRoutesFuture: recentRoutesFuture,
    legacyCredentialCleaner: legacyCredentialCleaner,
    onboardingStore: onboardingStore,
    facilityReportDraftTargetStore: facilityReportDraftTargetStore,
    facilityReportLostPhotoRestorer: facilityReportLostPhotoRestorer,
    supportAccessInfo: supportAccessInfo,
    supportAccessLauncher: supportAccessLauncher,
    dataPackUpdateStateRepository: dataPackUpdateStateRepository,
    onDataPackMeteredConsent: onDataPackMeteredConsent,
    dataPackUpdate: dataPackUpdate,
    bundledDataPackFreshness: bundledDataPackFreshness,
    initialOnboardingState: initialOnboardingState,
    navigatorKey: navigatorKey,
    key: key,
  );
}
