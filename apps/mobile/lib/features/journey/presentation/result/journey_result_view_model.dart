import '../../../../generated/journey_v3/journey_v3_contract.dart';

/// 역 ID를 화면에 보일 역 이름으로 바꾼다.
typedef JourneyStationNameLookup = String Function(String stationId);

/// 길찾기 결과 화면이 그리는 표시 값. 서버 응답(Journey V3)에 있는 값만 쓴다.
class JourneyResultViewModel {
  const JourneyResultViewModel._({
    required this.summary,
    required this.segments,
    required this.timeline,
  });

  factory JourneyResultViewModel.fromJourney(
    Journey journey, {
    required JourneyStationNameLookup stationName,
  }) {
    final departureTime = journeyKstTime(
      journey.realtimeDepartureTime ?? journey.plannedDepartureTime,
    );
    final arrivalTime = journeyKstTime(
      journey.realtimeArrivalTime ?? journey.plannedArrivalTime,
    );
    final segments = <JourneyResultSegment>[];
    final timeline = <JourneyTimelineNode>[];
    for (var index = 0; index < journey.legs.length; index++) {
      switch (journey.legs[index]) {
        case JourneyEntryLeg(:final fromStationId, :final durationSeconds):
          segments.add(
            JourneyResultSegment._(
              JourneyResultSegmentKind.entry,
              durationSeconds,
            ),
          );
          timeline.add(
            JourneyDepartureNode._(
              legIndex: index,
              stationName: stationName(fromStationId),
              departureTime: departureTime,
              walkLabel: '승강장까지 도보 ${_minutesLabel(durationSeconds)}',
            ),
          );
        case final JourneyRideLeg leg:
          final node = JourneyRideNode._fromLeg(index, leg, stationName);
          segments.add(
            JourneyResultSegment._(
              JourneyResultSegmentKind.ride,
              node.rideSeconds,
              lineId: leg.lineId,
            ),
          );
          timeline.add(node);
        case final JourneyTransferLeg leg:
          segments.add(
            JourneyResultSegment._(
              JourneyResultSegmentKind.transfer,
              leg.durationSeconds,
            ),
          );
          timeline.add(
            JourneyTransferNode._(
              legIndex: index,
              stationName: stationName(leg.fromStationId),
              walkMinutesLabel: _minutesLabel(leg.durationSeconds),
              leg: leg,
            ),
          );
        case JourneyExitLeg(:final fromStationId, :final durationSeconds):
          segments.add(
            JourneyResultSegment._(
              JourneyResultSegmentKind.exit,
              durationSeconds,
            ),
          );
          timeline.add(
            JourneyArrivalNode._(
              legIndex: index,
              stationName: stationName(fromStationId),
              arrivalTime: arrivalTime,
              walkLabel: '출구까지 도보 ${_minutesLabel(durationSeconds)}',
            ),
          );
      }
    }
    return JourneyResultViewModel._(
      summary: JourneyResultSummary._(
        durationMinutes: _minutes(journey.durationSeconds),
        departureTime: departureTime,
        arrivalTime: arrivalTime,
        transferLabel: journeyTransferLabel(journey.transferCount),
        fareLabel: journeyFareLabel(journey.fare),
        walkLabel: '도보 ${journey.walkingDistanceMeters}m',
        isRealtime: journey.timeSource == JourneyTimeSource.realtime,
        isStairFree: journey.accessibility.stairFree,
      ),
      segments: List.unmodifiable(segments),
      timeline: List.unmodifiable(timeline),
    );
  }

  final JourneyResultSummary summary;
  final List<JourneyResultSegment> segments;
  final List<JourneyTimelineNode> timeline;

  /// 구간 막대 전체를 읽는 Semantics 라벨.
  String get segmentsSemanticsLabel {
    final parts = segments.map(
      (segment) => switch (segment.kind) {
        JourneyResultSegmentKind.entry ||
        JourneyResultSegmentKind.exit => '도보 ${segment.minutesLabel}',
        JourneyResultSegmentKind.ride =>
          '${journeyLineName(segment.lineId!)} ${segment.minutesLabel}',
        JourneyResultSegmentKind.transfer => '환승 도보 ${segment.minutesLabel}',
      },
    );
    return '구간: ${parts.join(', ')}';
  }
}

class JourneyResultSummary {
  const JourneyResultSummary._({
    required this.durationMinutes,
    required this.departureTime,
    required this.arrivalTime,
    required this.transferLabel,
    required this.fareLabel,
    required this.walkLabel,
    required this.isRealtime,
    required this.isStairFree,
  });

  final int durationMinutes;
  final String departureTime;
  final String arrivalTime;
  final String transferLabel;
  final String? fareLabel;
  final String walkLabel;
  final bool isRealtime;
  final bool isStairFree;

  String get durationLabel => '$durationMinutes분';

  String get timesLabel => '$departureTime 출발 → $arrivalTime 도착';

  String get detailLabel => [transferLabel, ?fareLabel, walkLabel].join(' · ');

  String get semanticsLabel => [
    '$durationMinutes분 소요',
    '$departureTime 출발',
    '$arrivalTime 도착',
    transferLabel,
    ?fareLabel,
    walkLabel,
    if (isRealtime) '실시간 반영',
  ].join(', ');
}

enum JourneyResultSegmentKind { entry, ride, transfer, exit }

class JourneyResultSegment {
  const JourneyResultSegment._(this.kind, this.seconds, {this.lineId});

  final JourneyResultSegmentKind kind;
  final int seconds;
  final String? lineId;

  String get minutesLabel => _minutesLabel(seconds);
}

sealed class JourneyTimelineNode {
  const JourneyTimelineNode(this.legIndex);

  /// 이 노드가 그리는 `Journey.legs`의 위치.
  final int legIndex;
}

final class JourneyDepartureNode extends JourneyTimelineNode {
  const JourneyDepartureNode._({
    required int legIndex,
    required this.stationName,
    required this.departureTime,
    required this.walkLabel,
  }) : super(legIndex);

  final String stationName;
  final String departureTime;
  final String walkLabel;

  String get semanticsLabel => '$stationName, $departureTime 출발, $walkLabel';
}

final class JourneyRideNode extends JourneyTimelineNode {
  const JourneyRideNode._({
    required int legIndex,
    required this.lineId,
    required this.lineName,
    required this.directionLabel,
    required this.departureTime,
    required this.isExpress,
    required this.carDoorLabel,
    required this.carDoorSemanticsLabel,
    required this.stopCount,
    required this.rideMinutes,
    required this.intermediateStops,
    required this.boardingStationName,
    required this.alightingStationName,
    required this.boardingPlatformGaps,
    required this.alightingPlatformGaps,
    required this.rideSeconds,
  }) : super(legIndex);

  factory JourneyRideNode._fromLeg(
    int legIndex,
    JourneyRideLeg leg,
    JourneyStationNameLookup stationName,
  ) {
    final departure = leg.realtimeDepartureTime ?? leg.plannedDepartureTime;
    final arrival = leg.realtimeArrivalTime ?? leg.plannedArrivalTime;
    final rideSeconds = arrival.difference(departure).inSeconds;
    final doors = leg.alightingCarDoors.take(2).toList(growable: false);
    final stops = leg.stops;
    return JourneyRideNode._(
      legIndex: legIndex,
      lineId: leg.lineId,
      lineName: journeyLineName(leg.lineId),
      directionLabel: leg.directionStationId.isEmpty
          ? null
          : '${stationName(leg.directionStationId)} 방면',
      departureTime: journeyKstTime(departure),
      isExpress: leg.servicePattern == JourneyServicePattern.express,
      carDoorLabel: doors.isEmpty
          ? null
          : doors
                .map(
                  (door) =>
                      '${_carDoorPrefix(door.targetFacilityType)} '
                      '${door.carNumber}-${door.doorNumber}',
                )
                .join(' · '),
      carDoorSemanticsLabel: doors.isEmpty
          ? null
          : doors
                .map(
                  (door) =>
                      '${_carDoorSemanticsPrefix(door.targetFacilityType)} '
                      '${door.carNumber}호차 ${door.doorNumber}번 문',
                )
                .join(', '),
      stopCount: stops.length - 1,
      rideMinutes: _minutes(rideSeconds),
      intermediateStops: List.unmodifiable(
        stops
            .sublist(1, stops.length - 1)
            .map(
              (stop) => JourneyIntermediateStop._(
                name: stationName(stop.stationId),
                time: switch (stop.realtimeArrivalTime ??
                    stop.plannedArrivalTime ??
                    stop.realtimeDepartureTime ??
                    stop.plannedDepartureTime) {
                  final DateTime time => journeyKstTime(time),
                  null => null,
                },
              ),
            ),
      ),
      boardingStationName: stationName(leg.fromStationId),
      alightingStationName: stationName(leg.toStationId),
      boardingPlatformGaps: leg.boardingPlatformGaps,
      alightingPlatformGaps: leg.alightingPlatformGaps,
      rideSeconds: rideSeconds,
    );
  }

  final String lineId;
  final String lineName;

  /// `○○ 방면`. 서버가 방면 역을 주지 않으면 null이다.
  final String? directionLabel;
  final String departureTime;
  final bool isExpress;

  /// 탑승 위치 안내(`빠른 환승 3-2 · 엘리베이터 가까운 문 4-1`). 서버 순서 앞 2개.
  final String? carDoorLabel;

  /// 칸-문 안내의 스크린리더 문구(`빠른 환승 3호차 2번 문`).
  final String? carDoorSemanticsLabel;
  final int stopCount;
  final int rideMinutes;
  final List<JourneyIntermediateStop> intermediateStops;
  final String boardingStationName;
  final String alightingStationName;
  final List<JourneyPlatformGap> boardingPlatformGaps;
  final List<JourneyPlatformGap> alightingPlatformGaps;

  /// (실시간 도착 ?? 계획 도착) − (실시간 출발 ?? 계획 출발).
  final int rideSeconds;

  String get stopToggleLabel => '$stopCount개 역 이동 · $rideMinutes분';

  String get semanticsLabel => [
    [lineName, if (isExpress) '급행', ?directionLabel, '탑승'].join(' '),
    '$departureTime 출발',
    ?carDoorSemanticsLabel,
    '$stopCount개 역 이동',
    '$rideMinutes분',
  ].join(', ');
}

final class JourneyTransferNode extends JourneyTimelineNode {
  const JourneyTransferNode._({
    required int legIndex,
    required this.stationName,
    required this.walkMinutesLabel,
    required this.leg,
  }) : super(legIndex);

  final String stationName;
  final String walkMinutesLabel;

  /// 역 밖 환승 배지·재승차 안내가 읽는 원본 환승 구간.
  final JourneyTransferLeg leg;

  /// 재승차가 있으면 환승 노드에 이 문구만 표시한다(금액은 표시하지 않는다).
  static const reboardingFareLabel = '재승차 운임 발생';

  String get walkLabel => '환승 · 도보 $walkMinutesLabel';

  String get semanticsLabel => '$stationName 환승, 도보 $walkMinutesLabel';
}

final class JourneyArrivalNode extends JourneyTimelineNode {
  const JourneyArrivalNode._({
    required int legIndex,
    required this.stationName,
    required this.arrivalTime,
    required this.walkLabel,
  }) : super(legIndex);

  final String stationName;
  final String arrivalTime;
  final String walkLabel;

  String get semanticsLabel => '$stationName, $arrivalTime 도착, $walkLabel';
}

class JourneyIntermediateStop {
  const JourneyIntermediateStop._({required this.name, required this.time});

  final String name;

  /// 서버가 시각을 하나도 주지 않은 정차역이면 null이다.
  final String? time;
}

/// 경로 탭 하나의 표시 값.
class JourneyRouteTab {
  const JourneyRouteTab._({
    required this.journeyId,
    required this.labels,
    required this.durationLabel,
    required this.transferLabel,
    required this.arrivalTime,
  });

  final String journeyId;
  final List<String> labels;
  final String durationLabel;
  final String transferLabel;
  final String arrivalTime;

  String get semanticsLabel =>
      [...labels, durationLabel, transferLabel, '$arrivalTime 도착'].join(', ');
}

/// 계단 없는 경로 라벨. 상용 지하철 서비스의 계단 없는 경로 분류를 쉬운 말로 쓴다(#441 QA).
const journeyStairFreeCategoryLabel = '계단 없는 경로';
const _fastestLabel = '빠른 경로';
const _fewestTransfersLabel = '환승 적은 경로';

String _alternativeCategoryLabel(JourneyAlternativeCategory category) =>
    switch (category) {
      JourneyAlternativeCategory.fastest => _fastestLabel,
      JourneyAlternativeCategory.fewestTransfers => _fewestTransfersLabel,
      JourneyAlternativeCategory.stairFree => journeyStairFreeCategoryLabel,
    };

/// 계단 표시(계단 없는 경로 라벨, 계단 상태 안내)가 필요한 검색인지(#441 QA).
/// 계단 없는 경로가 필요한 이동 프로필(NO_STAIRS·STEP_FREE)이거나 계단 없는 경로를
/// 요청한 검색만 해당한다. 상용 지하철 서비스도 계단회피를 사용자가 고르는 길찾기
/// 옵션으로만 보여 주므로, 일반·느린 걸음 사용자에게는 계단 표시를 하지 않는다.
bool journeyShowsStairStatus(JourneyRequestPolicy policy) =>
    policy.constraintMode == ConstraintMode.requireStepFree ||
    policy.mobilityProfile == MobilityProfile.noStairs ||
    policy.mobilityProfile == MobilityProfile.stepFree;

/// 후보 목록(서버 순서)에서 경로 탭을 만든다. 라벨은 소요시간·환승 횟수·계단 없음
/// 사실에서만 만들고, 순서만으로 라벨을 붙이지 않는다.
///
/// 서버가 여정마다 대표 묶음(`alternativeCategories`, backend #471)을 주면 그
/// 묶음을 라벨로 쓴다. 묶음을 주지 않는 서버 응답이면 사실에서 라벨을 만든다.
/// [showStairStatus]가 false면 계단 없는 경로 라벨을 붙이지 않는다.
List<JourneyRouteTab> journeyRouteTabs(
  List<Journey> journeys, {
  required bool showStairStatus,
}) {
  if (journeys.isNotEmpty &&
      journeys.every((journey) => journey.alternativeCategories != null)) {
    return List.unmodifiable([
      for (var index = 0; index < journeys.length; index++)
        _routeTab(journeys[index], () {
          final categories = [
            for (final category in journeys[index].alternativeCategories!)
              if (showStairStatus ||
                  category != JourneyAlternativeCategory.stairFree)
                category,
          ];
          return [
            for (final category in categories)
              _alternativeCategoryLabel(category),
            if (categories.isEmpty) '경로 ${index + 1}',
            if (showStairStatus &&
                journeys[index].accessibility.stairFree &&
                !categories.contains(JourneyAlternativeCategory.stairFree))
              journeyStairFreeCategoryLabel,
          ];
        }()),
    ]);
  }
  var fastest = 0;
  var leastTransfers = 0;
  for (var index = 1; index < journeys.length; index++) {
    if (journeys[index].durationSeconds < journeys[fastest].durationSeconds) {
      fastest = index;
    }
    if (journeys[index].transferCount <
        journeys[leastTransfers].transferCount) {
      leastTransfers = index;
    }
  }
  return List.unmodifiable([
    for (var index = 0; index < journeys.length; index++)
      _routeTab(journeys[index], [
        if (index == fastest)
          _fastestLabel
        else if (index == leastTransfers)
          _fewestTransfersLabel
        else
          '경로 ${index + 1}',
        if (showStairStatus && journeys[index].accessibility.stairFree)
          journeyStairFreeCategoryLabel,
      ]),
  ]);
}

JourneyRouteTab _routeTab(Journey journey, List<String> labels) =>
    JourneyRouteTab._(
      journeyId: journey.journeyId,
      labels: List.unmodifiable(labels),
      durationLabel: '${_minutes(journey.durationSeconds)}분',
      transferLabel: journeyTransferLabel(journey.transferCount),
      arrivalTime: journeyKstTime(
        journey.realtimeArrivalTime ?? journey.plannedArrivalTime,
      ),
    );

enum JourneyStairStatusNoticeKind {
  stairFreeNotFound,
  stairInfoUnconfirmed,
  facilityOutageUnobserved,
}

/// 경로 후보 위에 두는 계단 상태 안내 한 줄(#441).
class JourneyStairStatusNotice {
  const JourneyStairStatusNotice._(this.kind, this.title, this.body);

  final JourneyStairStatusNoticeKind kind;
  final String title;
  final String body;

  String get semanticsLabel => '$title. $body';
}

const _stairFreeNotFoundNotice = JourneyStairStatusNotice._(
  JourneyStairStatusNoticeKind.stairFreeNotFound,
  '계단 없이 갈 수 있는 경로가 없어요',
  '찾은 경로는 모두 환승할 때 계단을 지나요.',
);

const _stairInfoUnconfirmedNotice = JourneyStairStatusNotice._(
  JourneyStairStatusNoticeKind.stairInfoUnconfirmed,
  '계단 정보가 없는 환승이 있어요',
  '출발 전에 환승역 엘리베이터 위치를 확인해 주세요.',
);

const _facilityOutageUnobservedNotice = JourneyStairStatusNotice._(
  JourneyStairStatusNoticeKind.facilityOutageUnobserved,
  '엘리베이터 고장 정보는 반영하지 못했어요',
  '계단 없는 경로의 엘리베이터가 지금 운행 중인지 확인되지 않았어요.',
);

/// 서버의 계단 없는 대안 결과(backend #471 `JourneyStairFreeAlternative`)를
/// 안내로 바꾼다. 상태 안내(NOT_FOUND·UNDETERMINED)를 먼저 두고, 시설 미반영
/// 안내는 계약 정의대로 계단 없는 여정이 결과에 있을 때만 둔다.
/// 서버가 상태를 주지 않은 결과(프로필 검색)는 추정해 안내하지 않는다.
List<JourneyStairStatusNotice> journeyStairStatusNotices(
  JourneyStairFreeAlternative? alternative, {
  required bool hasStairFreeJourney,
}) {
  if (alternative == null) return const [];
  return List.unmodifiable([
    if (alternative.status == JourneyStairFreeAlternativeStatus.notFound)
      _stairFreeNotFoundNotice,
    if (alternative.status == JourneyStairFreeAlternativeStatus.undetermined)
      _stairInfoUnconfirmedNotice,
    if (hasStairFreeJourney &&
        alternative.facilityStatus == JourneyStairFreeFacilityStatus.unobserved)
      _facilityOutageUnobservedNotice,
  ]);
}

/// 실패 화면 문구. 서버 처분의 `canonicalKoreanCopy`를 쓰되, 모바일이 문구를
/// 갖는 처분(`mobileResourceKey`)은 모바일 문구와 다음 행동을 쓴다.
class JourneyFailureCopy {
  const JourneyFailureCopy._({
    required this.message,
    this.detail,
    this.offersStandardRoutes = false,
  });

  final String message;
  final String? detail;

  /// 계단 여부를 표시한 일반 경로 검색을 행동으로 줄지.
  final bool offersStandardRoutes;
}

/// 계단 없는 경로만 요청했을 때 서버가 주는 422
/// `ACCESSIBILITY_CONSTRAINT_UNSATISFIED`의 모바일 문구 키.
const _accessibilityConstraintUnsatisfiedResourceKey =
    'journeyErrorAccessibilityConstraintUnsatisfied';

JourneyFailureCopy journeyFailureCopy(JourneyErrorDisposition? disposition) {
  if (disposition == null) {
    return const JourneyFailureCopy._(message: '경로를 찾지 못했어요. 잠시 후 다시 시도해 주세요.');
  }
  if (disposition.mobileResourceKey ==
      _accessibilityConstraintUnsatisfiedResourceKey) {
    return const JourneyFailureCopy._(
      message: '계단 없이 갈 수 있는 경로를 찾지 못했어요.',
      detail: '일반 경로를 볼까요? 환승할 때 계단이 있는지 함께 알려 드려요.',
      offersStandardRoutes: true,
    );
  }
  return JourneyFailureCopy._(message: disposition.canonicalKoreanCopy);
}

/// 서울 표준시(KST) `HH:mm`.
String journeyKstTime(DateTime instant) {
  final value = instant.toUtc().add(const Duration(hours: 9));
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String journeyTransferLabel(int transferCount) =>
    transferCount == 0 ? '환승 없음' : '환승 $transferCount회';

/// 성인 카드 운임. 서버가 운임을 제공하지 않으면 null이다.
String? journeyFareLabel(JourneyFare fare) {
  final won = fare.adultCardWon;
  if (fare.status != JourneyFareStatus.available || won == null) return null;
  return '카드 ${_groupThousands(won)}원';
}

/// 노선 ID를 사용자에게 보일 노선명으로 바꾼다. 모르는 ID는 그대로 둔다.
String journeyLineName(String lineId) {
  final clean = lineId.replaceAll(RegExp(r'^line-|^seoul-|^korail-'), '');
  const knownLines = <String, String>{
    'gyeongui-jungang': '경의중앙선',
    'suin-bundang': '수인분당선',
    'shinbundang': '신분당선',
    'arex': '공항철도',
    'airport': '공항철도',
    'gyeongchun': '경춘선',
    'gyeonggang': '경강선',
    'seohae': '서해선',
    'sillim': '신림선',
    'ui-sinseol': '우이신설선',
    'everline': '에버라인',
    'gimpo-gold': '김포골드라인',
  };
  if (knownLines[clean] case final name?) return name;
  if (int.tryParse(clean) != null) return '$clean호선';
  return lineId;
}

int _minutes(int seconds) => (seconds + 59) ~/ 60;

String _minutesLabel(int seconds) => '${_minutes(seconds)}분';

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _carDoorPrefix(AlightingTargetFacilityType type) => switch (type) {
  AlightingTargetFacilityType.transfer => '빠른 환승',
  AlightingTargetFacilityType.elevator => '엘리베이터 가까운 문',
  AlightingTargetFacilityType.escalator => '에스컬레이터 가까운 문',
  AlightingTargetFacilityType.stair => '계단 가까운 문',
};

String _carDoorSemanticsPrefix(AlightingTargetFacilityType type) =>
    switch (type) {
      AlightingTargetFacilityType.transfer => '빠른 환승',
      AlightingTargetFacilityType.elevator => '엘리베이터 가까운',
      AlightingTargetFacilityType.escalator => '에스컬레이터 가까운',
      AlightingTargetFacilityType.stair => '계단 가까운',
    };
