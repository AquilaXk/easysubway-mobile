import 'package:easysubway_mobile/features/journey/domain/journey_profile_models.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/transfer_guide.dart';
import 'package:easysubway_mobile/features/journey/journey_session_provider.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';

/// 길안내 결과 화면 접근성 검사용 고정 응답.
///
/// 후보 둘: 둘 다 환승 1회이고, 첫 후보만 계단 없는 빠른 경로다. 첫 후보의
/// 첫 탑승에 환승·엘리베이터 가까운 문 안내를 둔다.
const fixtureOriginStationId = 'st-gangnam';
const fixtureTransferStationId = 'st-gyodae';
const fixtureDestinationStationId = 'st-yangjae';
const fixtureStairFreeJourneyId = 'journey-fixture-stair-free';
const fixtureSlowerJourneyId = 'journey-fixture-slower';

const fixtureTransferGuideKey = TransferGuideKey(
  stationId: fixtureTransferStationId,
  fromLineId: 'line-2',
  fromPrevStationId: 'st-sports',
  toLineId: 'line-3',
  toNextStationId: fixtureDestinationStationId,
);

const fixtureTransferGuideSteps = <String>[
  '1) 방배 방면 승강장 하차',
  '2) 3호선 환승 엘리베이터 탑승',
  '3) 3호선 양재 방면 승강장으로 이동',
];

const _fixtureStationNames = <String, String>{
  fixtureOriginStationId: '강남',
  fixtureTransferStationId: '교대',
  fixtureDestinationStationId: '양재',
  'st-sports': '종합운동장',
  'st-ogeum': '오금',
};

Future<String> fixtureStationName(String stationId) async =>
    _fixtureStationNames[stationId] ?? stationId;

RouteDraft fixtureRouteDraft() => RouteDraft(
  origin: const RouteDraftStation(id: fixtureOriginStationId, nameKo: '강남'),
  waypoint: const RouteDraftStation(id: fixtureTransferStationId, nameKo: '교대'),
  destination: const RouteDraftStation(
    id: fixtureDestinationStationId,
    nameKo: '양재',
  ),
  lastModifiedAt: DateTime.utc(2026, 8, 12),
);

class FixtureIntegrityAttestor implements JourneyV3IntegrityAttestor {
  const FixtureIntegrityAttestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class FixtureTransferGuideRepository implements TransferGuideRepository {
  const FixtureTransferGuideRepository();

  @override
  Future<List<String>> loadSteps(TransferGuideKey key) async =>
      key == fixtureTransferGuideKey ? fixtureTransferGuideSteps : const [];

  @override
  Future<List<TransferGuideSource>> loadSources() async => const [];
}

JourneySessionResponse buildFixtureJourneySessionResponse({
  DateTime? issuedAt,
  Duration ttl = const Duration(minutes: 5),
  String token = 'session-token',
}) {
  final basis = issuedAt ?? DateTime.utc(2026, 8, 12);
  return JourneySessionResponse(
    token: token,
    scope: JourneySessionScope.journeyV3,
    issuedAt: basis,
    expiresAt: basis.add(ttl),
  );
}

JourneySearchSuccess buildFixtureJourneySearchSuccess(
  JourneySearchRequest request, {
  required List<Journey> journeys,
  DateTime? now,
  String queryId = 'query-1',
  String? serviceDate,
  JourneyStairFreeAlternative? stairFreeAlternative =
      const JourneyStairFreeAlternative(
        status: JourneyStairFreeAlternativeStatus.included,
        facilityStatus: JourneyStairFreeFacilityStatus.applied,
      ),
  String routeBundleId = 'bundle-1',
  String timetableSnapshotId = 'timetable-1',
  String accessibilitySnapshotId = 'accessibility-1',
}) {
  final basis = now ?? DateTime.utc(2026, 8, 12);
  return JourneySearchSuccess(
    contractVersion: JourneyContractVersion.journeySearchV3,
    requestId: request.requestId,
    queryId: queryId,
    calculatedAt: basis,
    validUntil: basis.add(const Duration(minutes: 5)),
    effectiveDepartureTime: basis,
    serviceDate: JourneyDate.parse(serviceDate ?? '2026-08-12'),
    serviceTimezone: 'Asia/Seoul',
    serviceDayCutoff: '03:00',
    stairFreeAlternative: stairFreeAlternative,
    sourceIdentity: JourneySourceIdentity(
      routeBundleId: routeBundleId,
      routeBundleSha256: 'a' * 64,
      timetableSnapshotId: timetableSnapshotId,
      accessibilitySnapshotId: accessibilitySnapshotId,
      realtimeSnapshotId: null,
    ),
    requestPolicy: JourneyRequestPolicy(
      timePolicy: request.timePolicy,
      walkingPace: request.walkingPace,
      mobilityProfile: request.mobilityProfile,
      constraintMode: request.constraintMode,
      maxTransfers: request.maxTransfers,
      alternativeCount: request.alternativeCount,
    ),
    journeys: journeys,
  );
}

JourneyProfileSuccess buildFixtureJourneyProfileSuccess(
  JourneyProfileRequest request, {
  required List<Journey> journeys,
  DateTime? now,
  String queryId = 'profile-1',
  List<String> objectiveTags = const ['LAST_CONNECTION'],
  Duration? candidateArrivalOffset,
}) {
  final basis = now ?? DateTime.utc(2026, 8, 12);
  return JourneyProfileSuccess(
    contractVersion: 'JOURNEY_PROFILE_V1',
    requestId: request.requestId,
    queryId: queryId,
    calculatedAt: basis,
    validUntil: basis.add(const Duration(minutes: 5)),
    temporalQuery: request.temporalQuery,
    serviceDayCutoff: '03:00',
    sourceIdentity: JourneyProfileSourceIdentity(
      routeBundleId: 'bundle-1',
      routeBundleGeneration: 'gen-1',
      routeBundleSha256: 'a' * 64,
      timetableSnapshotId: 'timetable-1',
      accessibilitySnapshotId: 'accessibility-1',
      realtimeSnapshotId: null,
    ),
    journeys: [
      for (final journey in journeys)
        JourneyProfileJourneyCandidate(
          journeyId: journey.journeyId,
          readyAt: candidateArrivalOffset == null
              ? journey.plannedDepartureTime
              : basis,
          journeyStartTime: candidateArrivalOffset == null
              ? journey.plannedDepartureTime
              : basis,
          firstBoardingTime: candidateArrivalOffset == null
              ? journey.plannedDepartureTime
              : basis,
          arrivalAtPlatform: candidateArrivalOffset == null
              ? journey.plannedArrivalTime
              : basis.add(candidateArrivalOffset),
          arrivalAtDestination: candidateArrivalOffset == null
              ? journey.plannedArrivalTime
              : basis.add(candidateArrivalOffset),
          objectiveTags: objectiveTags,
          journey: journey,
        ),
    ],
  );
}

class FixtureJourneyRepository implements JourneyRepository {
  FixtureJourneyRepository({
    DateTime? now,
    List<Journey>? journeys,
    this.serviceDate,
    this.stairFreeAlternative = const JourneyStairFreeAlternative(
      status: JourneyStairFreeAlternativeStatus.included,
      facilityStatus: JourneyStairFreeFacilityStatus.applied,
    ),
    this.profileObjectiveTags = const ['LAST_CONNECTION'],
    this.enableProfile = false,
  }) : now = now ?? DateTime.utc(2026, 8, 12),
       journeys =
           journeys ??
           _defaultFixtureJourneys(now ?? DateTime.utc(2026, 8, 12));

  final DateTime now;
  List<Journey> journeys;
  final String? serviceDate;
  final JourneyStairFreeAlternative? stairFreeAlternative;
  final List<String> profileObjectiveTags;
  final bool enableProfile;
  final List<JourneySearchRequest> requests = <JourneySearchRequest>[];
  final List<JourneyProfileRequest> profileRequests = <JourneyProfileRequest>[];

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async => buildFixtureJourneySessionResponse(issuedAt: now);

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    requests.add(request);
    return buildFixtureJourneySearchSuccess(
      request,
      journeys: journeys,
      now: now,
      serviceDate: serviceDate,
      stairFreeAlternative: stairFreeAlternative,
    );
  }

  @override
  Future<JourneyProfileSuccess> profileJourneys(
    JourneyProfileRequest request, {
    required String sessionToken,
  }) async {
    if (!enableProfile) {
      throw UnimplementedError('접근성 fixture는 프로필 검색을 쓰지 않는다.');
    }
    profileRequests.add(request);
    return buildFixtureJourneyProfileSuccess(
      request,
      journeys: journeys,
      now: now,
      objectiveTags: profileObjectiveTags,
    );
  }

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) => throw UnimplementedError('접근성 fixture는 역 시간표를 쓰지 않는다.');
}

List<Journey> _defaultFixtureJourneys(DateTime now) => <Journey>[
  _transferJourney(
    now,
    id: fixtureStairFreeJourneyId,
    extraMinutes: 0,
    stairFree: true,
    categories: const [
      JourneyAlternativeCategory.fastest,
      JourneyAlternativeCategory.stairFree,
    ],
    alightingCarDoors: _alightingCarDoors,
  ),
  _transferJourney(
    now,
    id: fixtureSlowerJourneyId,
    extraMinutes: 6,
    stairFree: false,
    categories: const [JourneyAlternativeCategory.fewestTransfers],
  ),
];

JourneyRideStop _stop(
  String stationId, {
  DateTime? arrival,
  DateTime? departure,
}) => JourneyRideStop(
  stationId: stationId,
  plannedArrivalTime: arrival,
  plannedDepartureTime: departure,
  realtimeArrivalTime: null,
  realtimeDepartureTime: null,
);

const _alightingCarDoors = <JourneyAlightingCarDoor>[
  JourneyAlightingCarDoor(
    carNumber: 3,
    doorNumber: 2,
    targetFacilityType: AlightingTargetFacilityType.transfer,
  ),
  JourneyAlightingCarDoor(
    carNumber: 4,
    doorNumber: 1,
    targetFacilityType: AlightingTargetFacilityType.elevator,
  ),
];

const _unavailableFare = JourneyFare(
  status: JourneyFareStatus.unavailable,
  sourceSnapshotIds: <String>[],
);

/// 강남 -> (2호선 교대 방면) -> 교대 환승 -> (3호선 오금 방면) -> 양재.
/// [extraMinutes]만큼 늦게 도착한다.
Journey _transferJourney(
  DateTime now, {
  required String id,
  required int extraMinutes,
  required bool stairFree,
  required List<JourneyAlternativeCategory> categories,
  List<JourneyAlightingCarDoor> alightingCarDoors = const [],
}) {
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));
  return Journey(
    journeyId: id,
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now,
    plannedArrivalTime: at(35 + extraMinutes),
    realtimeDepartureTime: null,
    realtimeArrivalTime: null,
    durationSeconds: (35 + extraMinutes) * 60,
    transferCount: 1,
    walkingDistanceMeters: 320,
    timeSource: JourneyTimeSource.timetable,
    accessibility: JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: stairFree,
      reasonCodes: const <String>[],
    ),
    legs: <JourneyLeg>[
      const JourneyEntryLeg(
        fromStationId: fixtureOriginStationId,
        durationSeconds: 120,
      ),
      JourneyRideLeg(
        lineId: 'line-2',
        tripId: 'trip-$id-2',
        directionStationId: fixtureTransferStationId,
        fromStationId: fixtureOriginStationId,
        toStationId: fixtureTransferStationId,
        plannedDepartureTime: at(3),
        plannedArrivalTime: at(15),
        realtimeDepartureTime: null,
        realtimeArrivalTime: null,
        servicePattern: JourneyServicePattern.local,
        stops: <JourneyRideStop>[
          _stop(fixtureOriginStationId, departure: at(3)),
          _stop('st-sports', arrival: at(12), departure: at(12)),
          _stop(fixtureTransferStationId, arrival: at(15)),
        ],
        alightingCarDoors: alightingCarDoors,
      ),
      const JourneyTransferLeg(
        fromStationId: fixtureTransferStationId,
        toStationId: fixtureTransferStationId,
        durationSeconds: 180,
      ),
      JourneyRideLeg(
        lineId: 'line-3',
        tripId: 'trip-$id-3',
        directionStationId: 'st-ogeum',
        fromStationId: fixtureTransferStationId,
        toStationId: fixtureDestinationStationId,
        plannedDepartureTime: at(26 + extraMinutes),
        plannedArrivalTime: at(34 + extraMinutes),
        realtimeDepartureTime: null,
        realtimeArrivalTime: null,
        servicePattern: JourneyServicePattern.local,
        stops: <JourneyRideStop>[
          _stop(fixtureTransferStationId, departure: at(26 + extraMinutes)),
          _stop(fixtureDestinationStationId, arrival: at(34 + extraMinutes)),
        ],
      ),
      const JourneyExitLeg(
        fromStationId: fixtureDestinationStationId,
        durationSeconds: 60,
      ),
    ],
    fare: _unavailableFare,
    alternativeCategories: categories,
  );
}
