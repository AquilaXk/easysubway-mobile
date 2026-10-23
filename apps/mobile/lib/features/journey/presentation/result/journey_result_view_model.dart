import '../../../../generated/journey_v3/journey_v3_contract.dart';
import '../../../route_draft/domain/route_draft.dart';
import '../../../stations/domain/station_line.dart';

/// 역 ID를 화면에 보일 역 이름으로 바꾼다.
typedef JourneyStationNameLookup = String Function(String stationId);

/// 길찾기 결과 화면이 그리는 표시 값. 서버 응답(Journey V3)에 있는 값만 쓴다.
class JourneyResultViewModel {
  const JourneyResultViewModel._({
    required this.summary,
    required this.segments,
    required this.timeline,
    required this.firstBoardingTime,
    required this.basisLabel,
  });

  /// [basis]는 서버가 검색에 쓴 기준 시각(`effectiveDepartureTime`)이다. 막차처럼
  /// 앱이 기준 시각을 받지 못한 검색은 null이고, 그러면 기준 시각 줄과 열차의 남은
  /// 분을 만들지 않는다.
  factory JourneyResultViewModel.fromJourney(
    Journey journey, {
    required JourneyStationNameLookup stationName,
    DateTime? basis,
  }) {
    final departure =
        journey.realtimeDepartureTime ?? journey.plannedDepartureTime;
    final arrival = journey.realtimeArrivalTime ?? journey.plannedArrivalTime;
    final segments = <JourneyResultSegment>[];
    final timeline = <JourneyTimelineNode>[];
    final legs = journey.legs;
    for (var index = 0; index < legs.length; index++) {
      switch (legs[index]) {
        case JourneyEntryLeg(:final fromStationId, :final durationSeconds):
          segments.add(
            JourneyResultSegment._walk(
              JourneyResultSegmentKind.entry,
              durationSeconds,
            ),
          );
          timeline.add(
            JourneyDepartureNode._(
              legIndex: index,
              stationName: stationName(fromStationId),
              departureTime: journeyKstTime(departure),
              walkLabel: '승강장까지 도보 ${_minutesLabel(durationSeconds)}',
            ),
          );
        case final JourneyRideLeg leg:
          final node = JourneyRideNode._fromLeg(
            index,
            leg,
            stationName,
            basis: basis,
          );
          segments.add(JourneyResultSegment._ride(node));
          timeline.add(node);
        case final JourneyTransferLeg leg:
          segments.add(
            JourneyResultSegment._walk(
              JourneyResultSegmentKind.transfer,
              leg.durationSeconds,
            ),
          );
          timeline.add(
            JourneyTransferNode._(
              legIndex: index,
              stationName: stationName(leg.fromStationId),
              walkMinutesLabel: _minutesLabel(leg.durationSeconds),
              waitSeconds: _transferWaitSeconds(legs, index),
              leg: leg,
            ),
          );
        case JourneyExitLeg(:final fromStationId, :final durationSeconds):
          segments.add(
            JourneyResultSegment._walk(
              JourneyResultSegmentKind.exit,
              durationSeconds,
            ),
          );
          timeline.add(
            JourneyArrivalNode._(
              legIndex: index,
              stationName: stationName(fromStationId),
              arrivalTime: journeyKstTime(arrival),
              walkLabel: '출구까지 도보 ${_minutesLabel(durationSeconds)}',
            ),
          );
      }
    }
    final firstBoarding = switch (legs
        .whereType<JourneyRideLeg>()
        .firstOrNull) {
      final JourneyRideLeg ride => _effectiveDeparture(ride),
      null => departure,
    };
    return JourneyResultViewModel._(
      summary: JourneyResultSummary._(
        durationMinutes: _minutes(journey.durationSeconds),
        departure: departure,
        arrival: arrival,
        transferLabel: journeyTransferLabel(journey.transferCount),
        fareLabel: journeyFareLabel(journey.fare),
        isStairFree: journey.accessibility.stairFree,
      ),
      segments: List.unmodifiable(segments),
      timeline: List.unmodifiable(timeline),
      firstBoardingTime: firstBoarding,
      basisLabel: switch (basis) {
        final DateTime value => _basisLabel(value, firstBoarding),
        null => null,
      },
    );
  }

  final JourneyResultSummary summary;
  final List<JourneyResultSegment> segments;
  final List<JourneyTimelineNode> timeline;

  /// 첫 열차의 출발 시각(실시간 ?? 계획). `다음열차`는 이 시각 1분 뒤로 다시 찾는다.
  final DateTime firstBoardingTime;

  /// `오전 12:36 기준 (출발 대기 4시간 35분)`. 기준 시각이 없으면 null이다.
  final String? basisLabel;

  /// 구간 막대 전체를 읽는 Semantics 라벨.
  String get segmentsSemanticsLabel {
    final parts = segments.map(
      (segment) => switch (segment.kind) {
        JourneyResultSegmentKind.entry ||
        JourneyResultSegmentKind.exit => '도보 ${segment.minutesLabel}',
        JourneyResultSegmentKind.ride =>
          '${journeyLineName(segment.lineId!)} ${segment.boardingStationName} '
              '${segment.departureTime} 출발 ${segment.minutesLabel}',
        JourneyResultSegmentKind.transfer => '환승 도보 ${segment.minutesLabel}',
      },
    );
    return '구간: ${parts.join(', ')}';
  }
}

String _basisLabel(DateTime basis, DateTime firstBoarding) {
  final waitSeconds = firstBoarding.difference(basis).inSeconds;
  final label = '${journeyKstClock(basis)} 기준';
  if (waitSeconds < Duration.secondsPerMinute) return label;
  return '$label (출발 대기 ${journeyDurationLabel(_minutes(waitSeconds))})';
}

DateTime _effectiveDeparture(JourneyRideLeg leg) =>
    leg.realtimeDepartureTime ?? leg.plannedDepartureTime;

DateTime _effectiveArrival(JourneyRideLeg leg) =>
    leg.realtimeArrivalTime ?? leg.plannedArrivalTime;

/// 환승 대기: 다음 열차 출발 − 앞 열차 도착 − 환승 도보. 서버 RAPTOR가 환승
/// 여유를 계산하는 식과 같다(backend `RouteTimetableRaptorPlanner`의 connection
/// slack). 앞뒤가 탑승이 아니면 계산하지 않는다.
int? _transferWaitSeconds(List<JourneyLeg> legs, int transferIndex) {
  if (transferIndex == 0 || transferIndex + 1 >= legs.length) return null;
  final (previous, next) = (legs[transferIndex - 1], legs[transferIndex + 1]);
  if (previous is! JourneyRideLeg || next is! JourneyRideLeg) return null;
  final transfer = legs[transferIndex] as JourneyTransferLeg;
  return _effectiveDeparture(
        next,
      ).difference(_effectiveArrival(previous)).inSeconds -
      transfer.durationSeconds;
}

class JourneyResultSummary {
  const JourneyResultSummary._({
    required this.durationMinutes,
    required this.departure,
    required this.arrival,
    required this.transferLabel,
    required this.fareLabel,
    required this.isStairFree,
  });

  final int durationMinutes;

  /// 실시간 ?? 계획 출발·도착 시각.
  final DateTime departure;
  final DateTime arrival;
  final String transferLabel;
  final String? fareLabel;
  final bool isStairFree;

  /// `2시간 17분`, 1시간 미만이면 `45분`.
  String get durationLabel => journeyDurationLabel(durationMinutes);

  /// 숫자와 단위 쌍. 숫자만 크게 그리고 단위는 작게 그린다.
  List<(String, String)> get durationParts =>
      journeyDurationParts(durationMinutes);

  /// `HH:mm` 도착 시각(공유 문구용).
  String get arrivalTime => journeyKstTime(arrival);

  /// `오전 5:11 - 오전 7:28`.
  String get timesLabel =>
      '${journeyKstClock(departure)} - ${journeyKstClock(arrival)}';

  String get semanticsLabel => [
    '$durationLabel 소요',
    '${journeyKstSpokenClock(departure)} 출발',
    '${journeyKstSpokenClock(arrival)} 도착',
    transferLabel,
    ?fareLabel,
  ].join(', ');
}

enum JourneyResultSegmentKind { entry, ride, transfer, exit }

class JourneyResultSegment {
  const JourneyResultSegment._walk(this.kind, this.seconds)
    : lineId = null,
      lineMarkLabel = null,
      departureTime = null,
      boardingStationName = null;

  JourneyResultSegment._ride(JourneyRideNode node)
    : kind = JourneyResultSegmentKind.ride,
      seconds = node.rideSeconds,
      lineId = node.lineId,
      lineMarkLabel = stationLineBadgeText(node.lineName),
      departureTime = node.departureTime,
      boardingStationName = node.boardingStationName;

  final JourneyResultSegmentKind kind;
  final int seconds;
  final String? lineId;

  /// 막대 안 흰 원의 노선 약칭(`1`, `수인분당`). 탑승 구간만 있다.
  final String? lineMarkLabel;

  /// 막대 위 출발 시각(`05:11`). 탑승 구간만 있다.
  final String? departureTime;

  /// 막대 아래 승차역 이름. 탑승 구간만 있다.
  final String? boardingStationName;

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
    required this.arrivalTime,
    required this.isExpress,
    required this.carDoorLines,
    required this.carDoorSemanticsLabel,
    required this.stopCount,
    required this.rideMinutes,
    required this.intermediateStops,
    required this.boardingStationId,
    required this.alightingStationId,
    required this.boardingStationName,
    required this.alightingStationName,
    required this.boardingPlatformGaps,
    required this.alightingPlatformGaps,
    required this.rideSeconds,
    required this.remainingMinutes,
  }) : super(legIndex);

  factory JourneyRideNode._fromLeg(
    int legIndex,
    JourneyRideLeg leg,
    JourneyStationNameLookup stationName, {
    required DateTime? basis,
  }) {
    final departure = _effectiveDeparture(leg);
    final arrival = _effectiveArrival(leg);
    final rideSeconds = arrival.difference(departure).inSeconds;
    final doors = leg.alightingCarDoors.take(2).toList(growable: false);
    final stops = leg.stops;
    final realtimeDeparture = leg.realtimeDepartureTime;
    return JourneyRideNode._(
      legIndex: legIndex,
      lineId: leg.lineId,
      lineName: journeyLineName(leg.lineId),
      directionLabel: leg.directionStationId.isEmpty
          ? null
          : '${stationNameWithSuffix(stationName(leg.directionStationId))} 방면',
      departureTime: journeyKstTime(departure),
      arrivalTime: journeyKstTime(arrival),
      isExpress: leg.servicePattern == JourneyServicePattern.express,
      carDoorLines: List.unmodifiable(
        doors.map(
          (door) =>
              '${_carDoorPrefix(door.targetFacilityType)}: '
              '${door.carNumber}-${door.doorNumber}',
        ),
      ),
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
      boardingStationId: leg.fromStationId,
      alightingStationId: leg.toStationId,
      boardingStationName: stationName(leg.fromStationId),
      alightingStationName: stationName(leg.toStationId),
      boardingPlatformGaps: leg.boardingPlatformGaps,
      alightingPlatformGaps: leg.alightingPlatformGaps,
      rideSeconds: rideSeconds,
      remainingMinutes: switch ((realtimeDeparture, basis)) {
        (final DateTime realtime, final DateTime from)
            when !realtime.isBefore(from) =>
          _minutes(realtime.difference(from).inSeconds),
        _ => null,
      },
    );
  }

  final String lineId;
  final String lineName;

  /// `○○역 방면`. 서버가 방면 역을 주지 않으면 null이다.
  final String? directionLabel;
  final String departureTime;

  /// 하차역 도착 시각(`HH:mm`).
  final String arrivalTime;
  final bool isExpress;

  /// 칸-문 안내 줄(`빠른 환승: 3-2`, `엘리베이터 가까운 문: 4-1`). 서버 순서 앞 2개.
  final List<String> carDoorLines;

  /// 칸-문 안내의 스크린리더 문구(`빠른 환승 3호차 2번 문`).
  final String? carDoorSemanticsLabel;
  final int stopCount;
  final int rideMinutes;
  final List<JourneyIntermediateStop> intermediateStops;
  final String boardingStationId;
  final String alightingStationId;
  final String boardingStationName;
  final String alightingStationName;
  final List<JourneyPlatformGap> boardingPlatformGaps;
  final List<JourneyPlatformGap> alightingPlatformGaps;

  /// (실시간 도착 ?? 계획 도착) − (실시간 출발 ?? 계획 출발).
  final int rideSeconds;

  /// 서버가 실시간 출발을 준 열차만 기준 시각부터 출발까지 남은 분이 있다.
  final int? remainingMinutes;

  String get boardingHeading => stationNameWithSuffix(boardingStationName);

  String get alightingHeading => stationNameWithSuffix(alightingStationName);

  /// 열차 카드의 남은 분(`11분`).
  String? get remainingLabel => switch (remainingMinutes) {
    final int minutes => '$minutes분',
    null => null,
  };

  String get trainSemanticsLabel => [
    '$departureTime 출발 열차',
    if (remainingLabel case final remaining?) '$remaining 남음',
  ].join(', ');

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
    required this.waitSeconds,
    required this.leg,
  }) : super(legIndex);

  final String stationName;
  final String walkMinutesLabel;

  /// 다음 열차 출발 − 앞 열차 도착 − 환승 도보(초). 앞뒤가 탑승이 아니면 null이다.
  final int? waitSeconds;

  /// 역 밖 환승 배지·재승차 안내가 읽는 원본 환승 구간.
  final JourneyTransferLeg leg;

  /// 재승차가 있으면 환승 노드에 이 문구만 표시한다(금액은 표시하지 않는다).
  static const reboardingFareLabel = '재승차 운임 발생';

  String get walkLabel => '도보 $walkMinutesLabel';

  /// `환승 대기 3분`. 대기가 1분 미만이거나 앞뒤가 탑승이 아니면 null이다.
  String? get waitLabel => switch (waitSeconds) {
    final int seconds when seconds >= Duration.secondsPerMinute =>
      '환승 대기 ${journeyDurationLabel(_minutes(seconds))}',
    _ => null,
  };

  String get semanticsLabel =>
      ['$stationName 환승', walkLabel, ?waitLabel].join(', ');
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

  String get heading => stationNameWithSuffix(name);
}

/// 결과 탭의 기준. 서버 대표 묶음(`alternativeCategories`)과 같은 순서다.
enum JourneyCriterion { fastest, fewestTransfers, stairFree }

/// 기준 탭 하나. 상용 지하철 서비스의 `최단시간`·`최소환승` 탭처럼 기준마다 한
/// 탭이고, 탭은 그 기준을 대표하는 서버 여정 하나를 가리킨다.
class JourneyCriterionTab {
  const JourneyCriterionTab._(this.criterion, this.journeyId);

  final JourneyCriterion criterion;
  final String journeyId;

  String get label => switch (criterion) {
    JourneyCriterion.fastest => '최단시간',
    JourneyCriterion.fewestTransfers => '최소환승',
    JourneyCriterion.stairFree => journeyStairFreeCategoryLabel,
  };
}

/// 계단 없는 경로 라벨. 상용 지하철 서비스의 계단 없는 경로 분류를 쉬운 말로 쓴다(#441 QA).
const journeyStairFreeCategoryLabel = '계단 없는 경로';

/// 계단 표시(계단 없는 경로 라벨, 계단 상태 안내)가 필요한 검색인지(#441 QA).
/// 계단 없는 경로가 필요한 이동 프로필(NO_STAIRS·STEP_FREE)이거나 계단 없는 경로를
/// 요청한 검색만 해당한다. 상용 지하철 서비스도 계단회피를 사용자가 고르는 길찾기
/// 옵션으로만 보여 주므로, 일반·느린 걸음 사용자에게는 계단 표시를 하지 않는다.
bool journeyShowsStairStatus(JourneyRequestPolicy policy) =>
    policy.constraintMode == ConstraintMode.requireStepFree ||
    policy.mobilityProfile == MobilityProfile.noStairs ||
    policy.mobilityProfile == MobilityProfile.stepFree;

/// 서버 여정에서 기준 탭을 만든다. 모든 여정에 대표 묶음(`alternativeCategories`,
/// backend #471)이 있으면 묶음을 대표하는 여정을 쓴다. 묶음이 없는 응답(프로필
/// 검색 등)은 소요시간이 가장 짧은 여정, 환승이 가장 적은 여정, 계단 없는 첫
/// 여정이라는 사실로 고른다. 최저요금은 서버 묶음이 없어 만들지 않는다.
/// [showStairStatus]가 false면 계단 없는 경로 탭을 만들지 않는다.
List<JourneyCriterionTab> journeyCriterionTabs(
  List<Journey> journeys, {
  required bool showStairStatus,
}) {
  if (journeys.isEmpty) return const [];
  final criteria = [
    JourneyCriterion.fastest,
    JourneyCriterion.fewestTransfers,
    if (showStairStatus) JourneyCriterion.stairFree,
  ];
  final grouped = journeys.every(
    (journey) => journey.alternativeCategories != null,
  );
  Journey? pick(JourneyCriterion criterion) => grouped
      ? journeys
            .where(
              (journey) => journey.alternativeCategories!.contains(
                _categoryOf(criterion),
              ),
            )
            .firstOrNull
      : _factualPick(journeys, criterion);
  return List.unmodifiable([
    for (final criterion in criteria)
      if (pick(criterion) case final journey?)
        JourneyCriterionTab._(criterion, journey.journeyId),
  ]);
}

JourneyAlternativeCategory _categoryOf(JourneyCriterion criterion) =>
    switch (criterion) {
      JourneyCriterion.fastest => JourneyAlternativeCategory.fastest,
      JourneyCriterion.fewestTransfers =>
        JourneyAlternativeCategory.fewestTransfers,
      JourneyCriterion.stairFree => JourneyAlternativeCategory.stairFree,
    };

Journey? _factualPick(List<Journey> journeys, JourneyCriterion criterion) =>
    switch (criterion) {
      JourneyCriterion.fastest => journeys.reduce(
        (best, next) =>
            next.durationSeconds < best.durationSeconds ? next : best,
      ),
      JourneyCriterion.fewestTransfers => journeys.reduce(
        (best, next) => next.transferCount < best.transferCount ? next : best,
      ),
      JourneyCriterion.stairFree =>
        journeys
            .where((journey) => journey.accessibility.stairFree)
            .firstOrNull,
    };

enum JourneyStairStatusNoticeKind { stairFreeNotFound }

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

/// 서버의 계단 없는 대안 결과(backend #471 `JourneyStairFreeAlternative`)를
/// 안내로 바꾼다. 계단 없는 경로가 실제로 없다고 확인된 경우(NOT_FOUND)만
/// 알린다. 확인되지 않은 것(계단 정보 없음, 엘리베이터 운행 여부 미관측)은
/// 상용 지하철 서비스처럼 아무 말도 하지 않는다(#443 QA).
List<JourneyStairStatusNotice> journeyStairStatusNotices(
  JourneyStairFreeAlternative? alternative,
) {
  if (alternative == null) return const [];
  return List.unmodifiable([
    if (alternative.status == JourneyStairFreeAlternativeStatus.notFound)
      _stairFreeNotFoundNotice,
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

DateTime _kst(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

/// 서울 표준시(KST) `HH:mm`.
String journeyKstTime(DateTime instant) {
  final value = _kst(instant);
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

const _hoursPerHalfDay = 12;

(String, int) _halfDayHour(DateTime instant) {
  final hour = _kst(instant).hour;
  final twelve = hour % _hoursPerHalfDay == 0
      ? _hoursPerHalfDay
      : hour % _hoursPerHalfDay;
  return (hour < _hoursPerHalfDay ? '오전' : '오후', twelve);
}

/// 서울 표준시 12시간제 `오전 5:11`. 자정 시는 `오전 12:36`이다.
String journeyKstClock(DateTime instant) {
  final (half, hour) = _halfDayHour(instant);
  return '$half $hour:${_kst(instant).minute.toString().padLeft(2, '0')}';
}

/// 스크린리더용 `오전 5시 11분`.
String journeyKstSpokenClock(DateTime instant) {
  final (half, hour) = _halfDayHour(instant);
  return '$half $hour시 ${_kst(instant).minute}분';
}

/// 숫자와 단위 쌍(`[('2', '시간'), ('17', '분')]`). 1시간 미만은 분만, 정시는
/// 시간만 쓴다.
List<(String, String)> journeyDurationParts(int minutes) {
  final hours = minutes ~/ Duration.minutesPerHour;
  final rest = minutes % Duration.minutesPerHour;
  return [
    if (hours > 0) ('$hours', '시간'),
    if (rest > 0 || hours == 0) ('$rest', '분'),
  ];
}

/// `2시간 17분`, `45분`, `1시간`.
String journeyDurationLabel(int minutes) => journeyDurationParts(
  minutes,
).map((part) => '${part.$1}${part.$2}').join(' ');

String journeyTransferLabel(int transferCount) =>
    transferCount == 0 ? '환승 없음' : '환승 $transferCount회';

/// 성인 카드 운임(`2,850원`). 서버가 운임을 제공하지 않으면 null이다.
String? journeyFareLabel(JourneyFare fare) {
  final won = fare.adultCardWon;
  if (fare.status != JourneyFareStatus.available || won == null) return null;
  return '${_groupThousands(won)}원';
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
