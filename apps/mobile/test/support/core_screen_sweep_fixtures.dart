// 핵심 화면 접근성 전수 검사(core_screen_guideline_sweep_test.dart)가 앱을 띄우는
// 고정 응답 모음. 화면 표(core_screen_sweep_screens.dart)가 같은 응답을 공유한다.
import 'package:easysubway_mobile/app/demo_dependencies.dart';
import 'package:easysubway_mobile/app/easy_subway_app.dart';
import 'package:easysubway_mobile/features/account/user_data_deletion.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_repository.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_request.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_result.dart';
import 'package:easysubway_mobile/features/favorites/favorite_facility.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/notifications/notification_settings.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'easy_subway_app_fixture.dart';

const sweepStationId = 'station-gangnam';

final sweepSearchResult = StationSearchResult(
  id: sweepStationId,
  nameKo: '강남',
  nameEn: 'Gangnam',
  region: '수도권',
  dataQualityLevel: 'LEVEL_1',
  lastVerifiedAt: '2026-09-27',
  lines: sweepLines,
);

/// 환승역으로 두어 역 시간표의 호선 선택 칩까지 그려지게 한다.
const sweepLines = [
  StationSearchLine(
    id: 'seoul-2',
    name: '수도권 2호선',
    color: '#00A84D',
    stationCode: '222',
  ),
  StationSearchLine(
    id: 'seoul-sb',
    name: '신분당선',
    color: '#D4003B',
    stationCode: 'D07',
  ),
];

/// 알림함이 읽는 시설·제보 조회의 성공·실패 조합.
enum SweepInboxLoad {
  /// 시설과 제보가 모두 성공한다.
  normal,

  /// 제보 조회가 실패하고 시설 항목이 없어, 알림함 전체가 오류 상태가 된다.
  failedNoItems,

  /// 제보 조회만 실패하고 시설 항목은 보여, 제보 구역에 오류 행이 뜬다.
  reportsFailed,
}

/// 내 제보 목록·알림함이 접수된 제보를 그리도록 제보 한 건을 돌려준다.
class SweepReportRepository implements FacilityReportRepository {
  const SweepReportRepository({this.listFails = false});

  /// true면 [listMyReports]가 실패해 알림함의 오류 상태를 검사할 수 있다.
  final bool listFails;

  static const _report = FacilityReportResult(
    id: 'report-1',
    stationId: sweepStationId,
    facilityId: 'facility-elevator-1',
    reportType: 'BROKEN',
    description: '1번 출구 엘리베이터가 멈춰 있어요.',
    status: 'SUBMITTED',
    createdAt: '2026-10-01T09:00:00',
  );

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest request,
  ) async => _report;

  @override
  Future<FacilityReportResult> getReport(String reportId) async => _report;

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    if (listFails) {
      throw StateError('sweep report list failure');
    }
    return const [_report];
  }
}

/// 알림함이 시설 항목을 그리도록 확인이 필요한 즐겨찾기 시설 한 건을 돌려준다.
class SweepFavoriteFacilityRepository implements FavoriteFacilityRepository {
  const SweepFavoriteFacilityRepository();

  static const _facility = FavoriteFacility(
    userId: 'sweep-user',
    facilityId: 'facility-gangnam-elevator-1',
    stationId: sweepStationId,
    stationNameKo: '강남',
    stationNameEn: 'Gangnam',
    exitId: 'exit-gangnam-1',
    type: 'ELEVATOR',
    name: '1번 출구 엘리베이터',
    floorFrom: '1F',
    floorTo: 'B1',
    description: '1번 출구 앞',
    status: 'USER_REPORTED',
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    lastUpdatedAt: '2026-10-01',
    addedAt: '2026-10-01T09:00:00',
  );

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async => const [
    _facility,
  ];

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async =>
      _facility;

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {}
}

/// 공지사항 목록과 홈 운행 지장 배너를 그리려고 일반 공지와 운행 지장 공지를 하나씩 둔다.
class SweepNoticeRepository implements NoticeRepository {
  @override
  Future<ActiveNoticesResult> activeNotices() async =>
      ActiveNoticesResult.fresh([
        ServiceNotice(
          id: 'notice-info',
          scope: NoticeScope.all,
          title: '시간표 개편 안내',
          body: '10월 20일부터 평일 막차 시간이 바뀝니다.',
          severity: NoticeSeverity.info,
          publishedAt: DateTime.utc(2026, 10, 1),
        ),
        ServiceNotice(
          id: 'notice-disruption',
          scope: NoticeScope.line,
          scopeValue: 'seoul-2',
          title: '2호선 일부 구간 지연',
          body: '신호 점검으로 열차가 지연되고 있습니다.',
          severity: NoticeSeverity.disruption,
          publishedAt: DateTime.utc(2026, 10, 2),
        ),
      ]);
}

class SweepUserDataDeletionRepository implements UserDataDeletionRepository {
  @override
  Future<UserDataDeletionResult> deleteCurrentUserData() async =>
      const UserDataDeletionResult(
        userId: 'sweep-user',
        deletedFavoriteStationCount: 1,
        deletedFavoriteFacilityCount: 1,
        deletedFavoriteRouteCount: 1,
        anonymizedRouteFeedbackCount: 0,
        notificationSettingsDeleted: true,
        deletedRegisteredDeviceCount: 0,
        deletedPushNotificationCount: 0,
        mobilityProfileDeleted: true,
        anonymizedReportCount: 1,
      );
}

class SweepNotificationSettingsRepository
    implements NotificationSettingsRepository {
  static const _settings = NotificationSettings(
    userId: 'sweep-user',
    favoriteStationFacilityAlerts: true,
    favoriteRouteFacilityAlerts: false,
    reportStatusAlerts: true,
    dataQualityAlerts: false,
    updatedAt: '2026-10-01T09:00:00',
  );

  @override
  Future<NotificationSettings> getNotificationSettings() async => _settings;

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) async => settings;
}

class SweepNotificationPermissionProvider
    implements NotificationPermissionProvider {
  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      NotificationPermissionStatus.granted;
}

/// 역 검색 화면의 최근 검색 칩을 그리려고 검색어 하나를 가진 고정 기록.
class SweepSearchHistoryRepository extends SearchHistoryRepository {
  @override
  Future<void> recordSearch(
    String query, {
    String? region,
    String? stationId,
    StationSearchLine? line,
  }) async {}

  @override
  Future<List<String>> listRecentQueries() async => const ['강남'];

  @override
  Future<void> removeSearch(String query, {String? region}) async {}

  @override
  Future<void> clearSearches() async {}
}

/// 홈 노선도·역 상세·역 시간표가 쓰는 고정 응답. 역 검색·노선도·시간표 포트를 함께
/// 구현한다.
class SweepRepository
    implements
        StationSearchRepository,
        NetworkMapRepository,
        StationTimetableRepository {
  SweepRepository({this.stationResults = const []});

  final List<StationSearchResult> stationResults;

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return const NetworkMapData(
      regions: [
        NetworkMapRegion(name: '수도권'),
        NetworkMapRegion(name: '부산'),
      ],
      selectedRegion: '수도권',
      lines: [
        NetworkMapLine(
          id: 'seoul-2',
          name: '수도권 2호선',
          color: '#00A84D',
          region: '수도권',
        ),
      ],
      stations: [
        NetworkMapStation(
          id: sweepStationId,
          nameKo: '강남',
          nameEn: 'Gangnam',
          region: '수도권',
          lineId: 'seoul-2',
          stationCode: '222',
          sequence: 1,
          position: NetworkMapPosition(
            x: 100,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'sweep-fixture',
          ),
        ),
      ],
      edges: [],
      positionSources: [],
    );
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    return const StationDetail(
      id: sweepStationId,
      nameKo: '강남',
      nameEn: 'Gangnam',
      region: '수도권',
      dataQualityLevel: 'LEVEL_1',
      lastVerifiedAt: '2026-09-27',
      latitude: 37.4979,
      longitude: 127.0276,
      lines: sweepLines,
    );
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    return const [
      StationExitInfo(
        id: 'exit-1',
        stationId: sweepStationId,
        exitNumber: '1',
        name: '1번 출구',
        description: '강남역 광장',
        hasElevatorConnection: true,
        hasStairOnlyPath: StairOnlyPathStatus.absent,
        dataConfidence: 'HIGH',
        lastVerifiedAt: '2026-09-27',
      ),
    ];
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    return const [
      StationFacilityInfo(
        id: 'facility-elevator-1',
        stationId: sweepStationId,
        exitId: 'exit-1',
        type: 'ELEVATOR',
        name: '1번 출구 엘리베이터',
        floorFrom: '지상',
        floorTo: '대합실',
        description: '1번 출구',
        status: 'BROKEN',
        dataConfidence: 'HIGH',
        lastUpdatedAt: '2026-09-27',
      ),
    ];
  }

  @override
  Future<List<StationSearchResult>> searchStations(
    String query, {
    String? region,
  }) async => stationResults;

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async => const [];

  StationTimetable _timetable(StationTimetableDayType dayType) =>
      StationTimetable(
        stationId: sweepStationId,
        lineId: 'seoul-2',
        dayType: dayType,
        directions: const [
          StationTimetableDirection(
            name: '역삼 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '역삼 방면',
                seconds: 9 * 3600,
                destination: '성수',
              ),
            ],
          ),
          StationTimetableDirection(
            name: '교대 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '교대 방면',
                seconds: 9 * 3600 + 300,
                destination: '신도림',
              ),
            ],
          ),
        ],
      );

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async => _timetable(dayType);

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async => _timetable(StationTimetableDayType.weekday);

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) => loadStationTimetableForDate(
    stationId: stationId,
    lineId: lineId,
    date: asOf,
  );
}

/// 전수 검사용으로 구성한 앱. 저장소는 모두 고정 응답이라 네트워크·DB에 닿지 않는다.
///
/// [stationResults]는 역 검색 포트가 돌려줄 결과다.
EasySubwayApp buildSweepApp({
  required GlobalKey<NavigatorState> navigatorKey,
  required OnboardingState onboardingState,
  List<StationSearchResult> stationResults = const [],
  SweepInboxLoad inboxLoad = SweepInboxLoad.normal,
}) {
  return buildEasySubwayTestApp(
    repository: SweepRepository(stationResults: stationResults),
    reportRepository: SweepReportRepository(
      listFails: inboxLoad != SweepInboxLoad.normal,
    ),
    searchHistoryRepository: SweepSearchHistoryRepository(),
    favoriteRepository: const DemoFavoriteStationRepository(),
    favoriteFacilityRepository: switch (inboxLoad) {
      SweepInboxLoad.normal => const DemoFavoriteFacilityRepository(),
      SweepInboxLoad.failedNoItems => null,
      SweepInboxLoad.reportsFailed => const SweepFavoriteFacilityRepository(),
    },
    favoriteRouteRepository: const DemoFavoriteRouteRepository(),
    noticeRepository: SweepNoticeRepository(),
    notificationRepository: SweepNotificationSettingsRepository(),
    userDataDeletionRepository: SweepUserDataDeletionRepository(),
    notificationPermissionProvider: SweepNotificationPermissionProvider(),
    navigatorKey: navigatorKey,
    initialOnboardingState: onboardingState,
  );
}
