import 'package:easysubway_mobile/features/journey/presentation/result/journey_result_view_model.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

// 모든 시각은 UTC로 적고, 기대값은 KST(+9) HH:mm으로 손으로 적는다.
DateTime _kst(int hour, int minute) =>
    DateTime.utc(2026, 9, 30, hour - 9, minute);

const _names = <String, String>{
  'st-gangnam': '강남',
  'st-yeoksam': '역삼',
  'st-seolleung': '선릉',
  'st-samseong': '삼성',
  'st-sports': '종합운동장',
  'st-gyodae': '교대',
  'st-nambu': '남부터미널',
  'st-yangjae': '양재',
  'st-ogeum': '오금',
  'st-dongjak': '동작',
  'st-express-mid': '고속터미널',
  'st-bohun': '중앙보훈병원',
  'st-sinnonhyeon': '신논현',
};

String _name(String stationId) => _names[stationId] ?? stationId;

const _unavailableFare = JourneyFare(
  status: JourneyFareStatus.unavailable,
  sourceSnapshotIds: <String>[],
);

const _availableFare = JourneyFare(
  status: JourneyFareStatus.available,
  adultCardWon: 1550,
  adultCashWon: 1650,
  sourceSnapshotIds: <String>['fare-snapshot-1'],
);

JourneyRideStop _stop(
  String stationId, {
  DateTime? plannedArrival,
  DateTime? plannedDeparture,
  DateTime? realtimeArrival,
  DateTime? realtimeDeparture,
}) => JourneyRideStop(
  stationId: stationId,
  plannedArrivalTime: plannedArrival,
  plannedDepartureTime: plannedDeparture,
  realtimeArrivalTime: realtimeArrival,
  realtimeDepartureTime: realtimeDeparture,
);

JourneyRideLeg _ride({
  String lineId = 'line-2',
  String directionStationId = 'st-gyodae',
  required String from,
  required String to,
  required DateTime departure,
  required DateTime arrival,
  DateTime? realtimeDeparture,
  DateTime? realtimeArrival,
  JourneyServicePattern servicePattern = JourneyServicePattern.local,
  required List<JourneyRideStop> stops,
  List<JourneyAlightingCarDoor> alightingCarDoors = const [],
}) => JourneyRideLeg(
  lineId: lineId,
  tripId: 'trip-$lineId',
  directionStationId: directionStationId,
  fromStationId: from,
  toStationId: to,
  plannedDepartureTime: departure,
  plannedArrivalTime: arrival,
  realtimeDepartureTime: realtimeDeparture,
  realtimeArrivalTime: realtimeArrival,
  servicePattern: servicePattern,
  stops: stops,
  alightingCarDoors: alightingCarDoors,
);

Journey _journey({
  String id = 'journey-1',
  required List<JourneyLeg> legs,
  required DateTime departure,
  required DateTime arrival,
  DateTime? realtimeDeparture,
  DateTime? realtimeArrival,
  int durationSeconds = 2100,
  int transferCount = 0,
  int walkingDistanceMeters = 320,
  JourneyTimeSource timeSource = JourneyTimeSource.timetable,
  bool stairFree = false,
  JourneyFare fare = _availableFare,
  List<JourneyAlternativeCategory>? alternativeCategories,
}) => Journey(
  journeyId: id,
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: departure,
  plannedArrivalTime: arrival,
  realtimeDepartureTime: realtimeDeparture,
  realtimeArrivalTime: realtimeArrival,
  durationSeconds: durationSeconds,
  transferCount: transferCount,
  walkingDistanceMeters: walkingDistanceMeters,
  timeSource: timeSource,
  accessibility: JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: stairFree,
    reasonCodes: const <String>[],
  ),
  legs: legs,
  fare: fare,
  alternativeCategories: alternativeCategories,
);

const _transferDoor = JourneyAlightingCarDoor(
  carNumber: 3,
  doorNumber: 2,
  targetFacilityType: AlightingTargetFacilityType.transfer,
);

/// 강남 → (2호선 교대역 방면, 5개 역) → 교대 환승 → (3호선 오금역 방면, 2개 역) → 양재
Journey _transferJourney({JourneyFare fare = _availableFare}) => _journey(
  departure: _kst(8, 12),
  arrival: _kst(8, 47),
  transferCount: 1,
  fare: fare,
  legs: <JourneyLeg>[
    const JourneyEntryLeg(fromStationId: 'st-gangnam', durationSeconds: 120),
    _ride(
      from: 'st-gangnam',
      to: 'st-gyodae',
      departure: _kst(8, 15),
      arrival: _kst(8, 27),
      alightingCarDoors: const [_transferDoor],
      stops: [
        _stop('st-gangnam', plannedDeparture: _kst(8, 15)),
        _stop(
          'st-yeoksam',
          plannedArrival: _kst(8, 17),
          plannedDeparture: _kst(8, 17),
        ),
        _stop(
          'st-seolleung',
          plannedArrival: _kst(8, 19),
          plannedDeparture: _kst(8, 19),
        ),
        _stop(
          'st-samseong',
          plannedArrival: _kst(8, 21),
          plannedDeparture: _kst(8, 21),
        ),
        _stop(
          'st-sports',
          plannedArrival: _kst(8, 24),
          plannedDeparture: _kst(8, 24),
        ),
        _stop('st-gyodae', plannedArrival: _kst(8, 27)),
      ],
    ),
    const JourneyTransferLeg(
      fromStationId: 'st-gyodae',
      toStationId: 'st-gyodae',
      durationSeconds: 180,
    ),
    _ride(
      lineId: 'line-3',
      directionStationId: 'st-ogeum',
      from: 'st-gyodae',
      to: 'st-yangjae',
      departure: _kst(8, 36),
      arrival: _kst(8, 44),
      stops: [
        _stop('st-gyodae', plannedDeparture: _kst(8, 36)),
        _stop(
          'st-nambu',
          plannedArrival: _kst(8, 40),
          plannedDeparture: _kst(8, 40),
        ),
        _stop('st-yangjae', plannedArrival: _kst(8, 44)),
      ],
    ),
    const JourneyExitLeg(fromStationId: 'st-yangjae', durationSeconds: 60),
  ],
);

JourneyResultViewModel _viewModel(Journey journey) =>
    JourneyResultViewModel.fromJourney(journey, stationName: _name);

void main() {
  test('(1) 직통: stops 6개면 5개 역 이동이고 경유 4개의 이름과 시각을 만든다', () {
    final journey = _journey(
      departure: _kst(8, 12),
      arrival: _kst(8, 28),
      durationSeconds: 960,
      legs: <JourneyLeg>[
        const JourneyEntryLeg(fromStationId: 'st-gangnam', durationSeconds: 90),
        _ride(
          from: 'st-gangnam',
          to: 'st-gyodae',
          departure: _kst(8, 15),
          arrival: _kst(8, 27),
          stops: [
            _stop('st-gangnam', plannedDeparture: _kst(8, 15)),
            _stop(
              'st-yeoksam',
              plannedArrival: _kst(8, 17),
              plannedDeparture: _kst(8, 17),
            ),
            _stop(
              'st-seolleung',
              plannedArrival: _kst(8, 19),
              plannedDeparture: _kst(8, 19),
            ),
            _stop(
              'st-samseong',
              plannedArrival: _kst(8, 21),
              plannedDeparture: _kst(8, 21),
            ),
            _stop(
              'st-sports',
              plannedArrival: _kst(8, 24),
              plannedDeparture: _kst(8, 24),
            ),
            _stop('st-gyodae', plannedArrival: _kst(8, 27)),
          ],
        ),
        const JourneyExitLeg(fromStationId: 'st-gyodae', durationSeconds: 60),
      ],
    );

    final viewModel = _viewModel(journey);
    final ride = viewModel.timeline[1] as JourneyRideNode;

    expect(ride.stopCount, 5);
    expect(ride.rideMinutes, 12);
    expect(ride.stopToggleLabel, '5개 역 이동 · 12분');
    expect(ride.intermediateStops.map((stop) => stop.name), [
      '역삼',
      '선릉',
      '삼성',
      '종합운동장',
    ]);
    expect(ride.intermediateStops.map((stop) => stop.time), [
      '08:17',
      '08:19',
      '08:21',
      '08:24',
    ]);
    expect(ride.isExpress, isFalse);
    expect(ride.lineId, 'line-2');
    expect(ride.lineName, '2호선');
    expect(ride.directionLabel, '교대역 방면');
    expect(ride.departureTime, '08:15');
    expect(ride.boardingStationName, '강남');
    expect(ride.alightingStationName, '교대');

    expect(viewModel.summary.durationMinutes, 16);
    expect(viewModel.summary.durationLabel, '16분');
    expect(viewModel.summary.transferLabel, '환승 없음');
    expect(viewModel.summary.timesLabel, '오전 8:12 - 오전 8:28');
    expect(viewModel.summary.fareLabel, '1,550원');
    expect(
      viewModel.segmentsSemanticsLabel,
      '구간: 도보 2분, 2호선 강남 08:15 출발 12분, 도보 1분',
    );
  });

  test('(2) 급행: stops 3개 EXPRESS면 2개 역 이동과 급행을 표시한다', () {
    final journey = _journey(
      departure: _kst(8, 18),
      arrival: _kst(8, 31),
      legs: <JourneyLeg>[
        const JourneyEntryLeg(
          fromStationId: 'st-sinnonhyeon',
          durationSeconds: 120,
        ),
        _ride(
          lineId: 'line-9',
          directionStationId: 'st-bohun',
          from: 'st-sinnonhyeon',
          to: 'st-dongjak',
          departure: _kst(8, 20),
          arrival: _kst(8, 30),
          servicePattern: JourneyServicePattern.express,
          stops: [
            _stop('st-sinnonhyeon', plannedDeparture: _kst(8, 20)),
            _stop(
              'st-express-mid',
              plannedArrival: _kst(8, 23),
              plannedDeparture: _kst(8, 24),
            ),
            _stop('st-dongjak', plannedArrival: _kst(8, 30)),
          ],
        ),
        const JourneyExitLeg(fromStationId: 'st-dongjak', durationSeconds: 60),
      ],
    );

    final ride = _viewModel(journey).timeline[1] as JourneyRideNode;

    expect(ride.isExpress, isTrue);
    expect(ride.stopCount, 2);
    expect(ride.stopToggleLabel, '2개 역 이동 · 10분');
    expect(ride.intermediateStops.single.name, '고속터미널');
    expect(ride.intermediateStops.single.time, '08:23');
    expect(ride.semanticsLabel, '9호선 급행 중앙보훈병원역 방면 탑승, 08:20 출발, 2개 역 이동, 10분');
  });

  test('(3) 환승 1회: 타임라인 노드 순서가 출발·탑승·환승·탑승·도착이다', () {
    final viewModel = _viewModel(_transferJourney());
    final timeline = viewModel.timeline;

    expect(timeline.map((node) => node.runtimeType), [
      JourneyDepartureNode,
      JourneyRideNode,
      JourneyTransferNode,
      JourneyRideNode,
      JourneyArrivalNode,
    ]);
    expect(timeline.map((node) => node.legIndex), [0, 1, 2, 3, 4]);

    final departure = timeline[0] as JourneyDepartureNode;
    expect(departure.stationName, '강남');
    expect(departure.departureTime, '08:12');
    expect(departure.walkLabel, '승강장까지 도보 2분');
    expect(departure.semanticsLabel, '강남, 08:12 출발, 승강장까지 도보 2분');

    final firstRide = timeline[1] as JourneyRideNode;
    expect(
      firstRide.semanticsLabel,
      '2호선 교대역 방면 탑승, 08:15 출발, 빠른 환승 3호차 2번 문, 5개 역 이동, 12분',
    );

    final transfer = timeline[2] as JourneyTransferNode;
    expect(transfer.stationName, '교대');
    expect(transfer.walkLabel, '도보 3분');
    // 08:27 하차 + 도보 3분 = 08:30, 다음 열차 08:36 출발.
    expect(transfer.waitLabel, '환승 대기 6분');
    expect(transfer.semanticsLabel, '교대 환승, 도보 3분, 환승 대기 6분');
    expect(transfer.leg.durationSeconds, 180);

    final secondRide = timeline[3] as JourneyRideNode;
    expect(secondRide.lineName, '3호선');
    expect(secondRide.directionLabel, '오금역 방면');
    expect(secondRide.stopToggleLabel, '2개 역 이동 · 8분');

    final arrival = timeline[4] as JourneyArrivalNode;
    expect(arrival.stationName, '양재');
    expect(arrival.arrivalTime, '08:47');
    expect(arrival.walkLabel, '출구까지 도보 1분');
    expect(arrival.semanticsLabel, '양재, 08:47 도착, 출구까지 도보 1분');

    expect(viewModel.summary.durationLabel, '35분');
    expect(viewModel.summary.timesLabel, '오전 8:12 - 오전 8:47');
    expect(
      viewModel.summary.semanticsLabel,
      '35분 소요, 오전 8시 12분 출발, 오전 8시 47분 도착, 환승 1회, 1,550원',
    );
    expect(viewModel.summary.isStairFree, isFalse);

    expect(
      viewModel.segments.map((segment) => (segment.kind, segment.seconds)),
      [
        (JourneyResultSegmentKind.entry, 120),
        (JourneyResultSegmentKind.ride, 720),
        (JourneyResultSegmentKind.transfer, 180),
        (JourneyResultSegmentKind.ride, 480),
        (JourneyResultSegmentKind.exit, 60),
      ],
    );
    expect(viewModel.segments.map((segment) => segment.lineId), [
      null,
      'line-2',
      null,
      'line-3',
      null,
    ]);
    expect(viewModel.segments.map((segment) => segment.minutesLabel), [
      '2분',
      '12분',
      '3분',
      '8분',
      '1분',
    ]);
    expect(viewModel.segments.map((segment) => segment.departureTime), [
      null,
      '08:15',
      null,
      '08:36',
      null,
    ]);
    expect(viewModel.segments.map((segment) => segment.boardingStationName), [
      null,
      '강남',
      null,
      '교대',
      null,
    ]);
    expect(viewModel.segments.map((segment) => segment.lineMarkLabel), [
      null,
      '2',
      null,
      '3',
      null,
    ]);
    expect(
      viewModel.segmentsSemanticsLabel,
      '구간: 도보 2분, 2호선 강남 08:15 출발 12분, 환승 도보 3분, '
      '3호선 교대 08:36 출발 8분, 도보 1분',
    );
  });

  test('(4) 운임: AVAILABLE 1550이면 카드 1,550원, 그 밖에는 null이다', () {
    expect(_viewModel(_transferJourney()).summary.fareLabel, '1,550원');

    final unavailable = _viewModel(
      _transferJourney(fare: _unavailableFare),
    ).summary;
    expect(unavailable.fareLabel, isNull);
    expect(
      unavailable.semanticsLabel,
      '35분 소요, 오전 8시 12분 출발, 오전 8시 47분 도착, 환승 1회',
    );

    final availableWithoutCard = _viewModel(
      _transferJourney(
        fare: const JourneyFare(
          status: JourneyFareStatus.available,
          adultCashWon: 1650,
          sourceSnapshotIds: <String>['fare-snapshot-1'],
        ),
      ),
    ).summary;
    expect(availableWithoutCard.fareLabel, isNull);

    final large = _viewModel(
      _transferJourney(
        fare: const JourneyFare(
          status: JourneyFareStatus.available,
          adultCardWon: 12050,
          sourceSnapshotIds: <String>['fare-snapshot-1'],
        ),
      ),
    ).summary;
    expect(large.fareLabel, '12,050원');
  });

  Journey tabCandidate(
    String id,
    int minutes,
    int transfers,
    List<JourneyAlternativeCategory>? categories, {
    bool stairFree = false,
  }) => _journey(
    id: id,
    departure: _kst(8, 0),
    arrival: _kst(8, minutes),
    durationSeconds: minutes * 60,
    transferCount: transfers,
    stairFree: stairFree,
    alternativeCategories: categories,
    legs: const <JourneyLeg>[
      JourneyEntryLeg(fromStationId: 'st-gangnam', durationSeconds: 60),
    ],
  );

  List<(String, String)> tabPairs(List<JourneyCriterionTab> tabs) => [
    for (final tab in tabs) (tab.label, tab.journeyId),
  ];

  test('(5b) 기준 탭은 서버 대표 묶음을 최단시간·최소환승·계단 없는 경로 순으로 잇는다', () {
    final tabs = journeyCriterionTabs(showStairStatus: true, [
      tabCandidate('a', 30, 2, [JourneyAlternativeCategory.fastest]),
      tabCandidate('b', 34, 1, [JourneyAlternativeCategory.fewestTransfers]),
      tabCandidate('c', 41, 2, [
        JourneyAlternativeCategory.stairFree,
      ], stairFree: true),
    ]);
    expect(tabPairs(tabs), [('최단시간', 'a'), ('최소환승', 'b'), ('계단 없는 경로', 'c')]);

    // 한 여정이 두 묶음을 대표하면 두 탭이 같은 여정을 가리킨다. 묶음이 빈 여정은
    // 기준 탭이 없다.
    final merged = journeyCriterionTabs(showStairStatus: true, [
      tabCandidate('a', 30, 0, [
        JourneyAlternativeCategory.fastest,
        JourneyAlternativeCategory.fewestTransfers,
      ]),
      tabCandidate('b', 38, 1, const [], stairFree: true),
    ]);
    expect(tabPairs(merged), [('최단시간', 'a'), ('최소환승', 'a')]);
  });

  test('(5) 묶음이 없는 응답은 소요시간·환승 수 사실로 기준 탭을 만든다', () {
    final facts = journeyCriterionTabs(showStairStatus: true, [
      tabCandidate('a', 40, 1, null),
      tabCandidate('b', 30, 1, null),
      tabCandidate('c', 45, 0, null, stairFree: true),
      tabCandidate('d', 30, 0, null),
    ]);
    expect(tabPairs(facts), [('최단시간', 'b'), ('최소환승', 'c'), ('계단 없는 경로', 'c')]);

    // 묶음이 일부 여정에만 오면(계약상 선택 필드) 사실로 만든다.
    final mixed = journeyCriterionTabs(showStairStatus: false, [
      tabCandidate('a', 30, 1, [JourneyAlternativeCategory.fastest]),
      tabCandidate('b', 35, 0, null),
    ]);
    expect(tabPairs(mixed), [('최단시간', 'a'), ('최소환승', 'b')]);
  });

  // #441 QA: 일반 이동 프로필 사용자에게는 계단 관련 표시를 하지 않는다.
  test('(5-1) 계단 표시가 필요 없는 사용자에게는 계단 없는 경로 탭을 만들지 않는다', () {
    final grouped = journeyCriterionTabs(showStairStatus: false, [
      tabCandidate('a', 30, 1, [
        JourneyAlternativeCategory.fastest,
        JourneyAlternativeCategory.stairFree,
      ], stairFree: true),
      tabCandidate('b', 35, 0, [JourneyAlternativeCategory.fewestTransfers]),
    ]);
    expect(tabPairs(grouped), [('최단시간', 'a'), ('최소환승', 'b')]);

    // 계단 없는 여정이 없으면 계단 없는 경로 탭도 없다.
    final none = journeyCriterionTabs(showStairStatus: true, [
      tabCandidate('a', 30, 1, null),
    ]);
    expect(tabPairs(none), [('최단시간', 'a'), ('최소환승', 'a')]);
  });

  test('(5-2) 계단 표시는 계단 없는 경로가 필요한 이동 프로필이나 계단 없는 경로 요청에만 켠다', () {
    JourneyRequestPolicy policy(
      MobilityProfile profile,
      ConstraintMode constraint,
    ) => JourneyRequestPolicy(
      timePolicy: TimePolicy.timetableRequired,
      walkingPace: WalkingPace.standard,
      mobilityProfile: profile,
      constraintMode: constraint,
      maxTransfers: 3,
      alternativeCount: 3,
    );

    expect(
      journeyShowsStairStatus(
        policy(MobilityProfile.standard, ConstraintMode.none),
      ),
      isFalse,
    );
    expect(
      journeyShowsStairStatus(
        policy(MobilityProfile.slow, ConstraintMode.none),
      ),
      isFalse,
    );
    expect(
      journeyShowsStairStatus(
        policy(MobilityProfile.stepFree, ConstraintMode.none),
      ),
      isTrue,
    );
    expect(
      journeyShowsStairStatus(
        policy(MobilityProfile.noStairs, ConstraintMode.requireStepFree),
      ),
      isTrue,
    );
    expect(
      journeyShowsStairStatus(
        policy(MobilityProfile.stepFree, ConstraintMode.requireStepFree),
      ),
      isTrue,
    );
  });

  test('(6) 방면이 빈 문자열이면 방면 문구를 만들지 않는다', () {
    final journey = _journey(
      departure: _kst(8, 12),
      arrival: _kst(8, 20),
      legs: <JourneyLeg>[
        _ride(
          directionStationId: '',
          from: 'st-gangnam',
          to: 'st-yeoksam',
          departure: _kst(8, 15),
          arrival: _kst(8, 17),
          stops: [
            _stop('st-gangnam', plannedDeparture: _kst(8, 15)),
            _stop('st-yeoksam', plannedArrival: _kst(8, 17)),
          ],
        ),
      ],
    );

    final ride = _viewModel(journey).timeline.single as JourneyRideNode;

    expect(ride.directionLabel, isNull);
    expect(ride.stopCount, 1);
    expect(ride.intermediateStops, isEmpty);
    expect(ride.stopToggleLabel, '1개 역 이동 · 2분');
    expect(ride.semanticsLabel, '2호선 탑승, 08:15 출발, 1개 역 이동, 2분');
  });

  test('(7) 칸-문: 서버 순서 앞 2개만 시설별 문구로 잇고 빈 배열이면 없다', () {
    JourneyRideNode rideWith(List<JourneyAlightingCarDoor> doors) {
      final journey = _journey(
        departure: _kst(8, 12),
        arrival: _kst(8, 20),
        legs: <JourneyLeg>[
          _ride(
            from: 'st-gangnam',
            to: 'st-yeoksam',
            departure: _kst(8, 15),
            arrival: _kst(8, 17),
            alightingCarDoors: doors,
            stops: [
              _stop('st-gangnam', plannedDeparture: _kst(8, 15)),
              _stop('st-yeoksam', plannedArrival: _kst(8, 17)),
            ],
          ),
        ],
      );
      return _viewModel(journey).timeline.single as JourneyRideNode;
    }

    final transferAndElevator = rideWith(const [
      _transferDoor,
      JourneyAlightingCarDoor(
        carNumber: 4,
        doorNumber: 1,
        targetFacilityType: AlightingTargetFacilityType.elevator,
      ),
      JourneyAlightingCarDoor(
        carNumber: 7,
        doorNumber: 3,
        targetFacilityType: AlightingTargetFacilityType.escalator,
      ),
    ]);
    expect(transferAndElevator.carDoorLines, [
      '빠른 환승: 3-2',
      '엘리베이터 가까운 문: 4-1',
    ]);
    expect(
      transferAndElevator.semanticsLabel,
      '2호선 교대역 방면 탑승, 08:15 출발, '
      '빠른 환승 3호차 2번 문, 엘리베이터 가까운 4호차 1번 문, 1개 역 이동, 2분',
    );

    final escalatorAndStair = rideWith(const [
      JourneyAlightingCarDoor(
        carNumber: 7,
        doorNumber: 3,
        targetFacilityType: AlightingTargetFacilityType.escalator,
      ),
      JourneyAlightingCarDoor(
        carNumber: 2,
        doorNumber: 4,
        targetFacilityType: AlightingTargetFacilityType.stair,
      ),
    ]);
    expect(escalatorAndStair.carDoorLines, [
      '에스컬레이터 가까운 문: 7-3',
      '계단 가까운 문: 2-4',
    ]);
    expect(
      escalatorAndStair.semanticsLabel,
      '2호선 교대역 방면 탑승, 08:15 출발, '
      '에스컬레이터 가까운 7호차 3번 문, 계단 가까운 2호차 4번 문, 1개 역 이동, 2분',
    );

    expect(rideWith(const []).carDoorLines, isEmpty);
  });

  test('(8) 실시간 시각이 있으면 계획 시각보다 우선한다', () {
    final journey = _journey(
      departure: _kst(8, 12),
      arrival: _kst(8, 47),
      realtimeDeparture: _kst(8, 13),
      realtimeArrival: _kst(8, 49),
      timeSource: JourneyTimeSource.realtime,
      stairFree: true,
      legs: <JourneyLeg>[
        const JourneyEntryLeg(
          fromStationId: 'st-gangnam',
          durationSeconds: 120,
        ),
        _ride(
          from: 'st-gangnam',
          to: 'st-gyodae',
          departure: _kst(8, 15),
          arrival: _kst(8, 27),
          realtimeDeparture: _kst(8, 16),
          realtimeArrival: _kst(8, 30),
          stops: [
            _stop(
              'st-gangnam',
              plannedDeparture: _kst(8, 15),
              realtimeDeparture: _kst(8, 16),
            ),
            _stop(
              'st-yeoksam',
              plannedArrival: _kst(8, 17),
              realtimeArrival: _kst(8, 18),
            ),
            _stop(
              'st-seolleung',
              plannedDeparture: _kst(8, 19),
              realtimeDeparture: _kst(8, 20),
            ),
            _stop('st-samseong', plannedDeparture: _kst(8, 22)),
            _stop('st-sports'),
            _stop('st-gyodae', realtimeArrival: _kst(8, 30)),
          ],
        ),
        const JourneyExitLeg(fromStationId: 'st-gyodae', durationSeconds: 60),
      ],
    );

    final viewModel = _viewModel(journey);
    final ride = viewModel.timeline[1] as JourneyRideNode;

    expect(viewModel.summary.timesLabel, '오전 8:13 - 오전 8:49');
    expect(viewModel.summary.isStairFree, isTrue);
    expect(
      viewModel.summary.semanticsLabel,
      '35분 소요, 오전 8시 13분 출발, 오전 8시 49분 도착, 환승 없음, 1,550원',
    );
    expect(
      (viewModel.timeline.first as JourneyDepartureNode).departureTime,
      '08:13',
    );
    expect(
      (viewModel.timeline.last as JourneyArrivalNode).arrivalTime,
      '08:49',
    );
    expect(ride.departureTime, '08:16');
    expect(ride.arrivalTime, '08:30');
    expect(ride.rideMinutes, 14);
    expect(viewModel.segments[1].seconds, 14 * 60);
    expect(ride.intermediateStops.map((stop) => stop.time), [
      '08:18',
      '08:20',
      '08:22',
      null,
    ]);
    expect(ride.intermediateStops.last.name, '종합운동장');
  });

  group('상용 지하철 서비스 표현(#509)', () {
    Journey longRide({
      required DateTime departure,
      required DateTime arrival,
      DateTime? realtimeDeparture,
      DateTime? realtimeArrival,
    }) => _journey(
      departure: departure,
      arrival: arrival,
      durationSeconds: arrival.difference(departure).inSeconds,
      legs: <JourneyLeg>[
        _ride(
          lineId: 'line-1',
          from: 'st-gangnam',
          to: 'st-yeoksam',
          departure: departure,
          arrival: arrival,
          realtimeDeparture: realtimeDeparture,
          realtimeArrival: realtimeArrival,
          stops: [
            _stop('st-gangnam', plannedDeparture: departure),
            _stop('st-yeoksam', plannedArrival: arrival),
          ],
        ),
      ],
    );

    test('총시간이 1시간 이상이면 시간과 분으로 쓴다', () {
      final summary = _viewModel(
        longRide(departure: _kst(5, 11), arrival: _kst(7, 28)),
      ).summary;
      expect(summary.durationLabel, '2시간 17분');
      expect(summary.durationParts, [('2', '시간'), ('17', '분')]);
      expect(summary.timesLabel, '오전 5:11 - 오전 7:28');

      final exact = _viewModel(
        longRide(departure: _kst(5, 0), arrival: _kst(6, 0)),
      ).summary;
      expect(exact.durationLabel, '1시간');
      expect(exact.durationParts, [('1', '시간')]);
    });

    test('자정 시각은 오전 12시, 정오 뒤는 오후로 쓴다', () {
      // 자정 넘어 00:36 출발은 KST 다음 날 00:36이다.
      final midnight = _viewModel(
        longRide(
          departure: DateTime.utc(2026, 9, 30, 15, 36),
          arrival: DateTime.utc(2026, 9, 30, 16, 5),
        ),
      ).summary;
      expect(midnight.timesLabel, '오전 12:36 - 오전 1:05');
      expect(
        midnight.semanticsLabel,
        '29분 소요, 오전 12시 36분 출발, 오전 1시 5분 도착, 환승 없음, 1,550원',
      );

      final noon = _viewModel(
        longRide(departure: _kst(12, 5), arrival: _kst(13, 40)),
      ).summary;
      expect(noon.timesLabel, '오후 12:05 - 오후 1:40');
    });

    test('기준 시각 줄은 서버 기준 시각과 첫 열차 출발까지의 대기를 쓴다', () {
      final viewModel = JourneyResultViewModel.fromJourney(
        longRide(departure: _kst(5, 11), arrival: _kst(5, 56)),
        stationName: _name,
        basis: DateTime.utc(2026, 9, 29, 15, 36),
      );
      expect(viewModel.basisLabel, '오전 12:36 기준 (출발 대기 4시간 35분)');

      final noWait = JourneyResultViewModel.fromJourney(
        longRide(departure: _kst(8, 0), arrival: _kst(8, 10)),
        stationName: _name,
        basis: _kst(8, 0),
      );
      expect(noWait.basisLabel, '오전 8:00 기준');

      expect(
        _viewModel(
          longRide(departure: _kst(8, 0), arrival: _kst(8, 10)),
        ).basisLabel,
        isNull,
      );
    });

    test('남은 분은 서버가 실시간 출발을 준 탑승에만 만든다', () {
      final realtime = JourneyResultViewModel.fromJourney(
        longRide(
          departure: _kst(0, 55),
          arrival: _kst(1, 0),
          realtimeDeparture: _kst(0, 57),
          realtimeArrival: _kst(1, 1),
        ),
        stationName: _name,
        basis: _kst(0, 46),
      );
      final ride = realtime.timeline.single as JourneyRideNode;
      expect(ride.departureTime, '00:57');
      expect(ride.remainingLabel, '11분');
      expect(ride.trainSemanticsLabel, '00:57 출발 열차, 11분 남음');

      final timetable = JourneyResultViewModel.fromJourney(
        longRide(departure: _kst(0, 55), arrival: _kst(1, 0)),
        stationName: _name,
        basis: _kst(0, 46),
      );
      final planned = timetable.timeline.single as JourneyRideNode;
      expect(planned.remainingLabel, isNull);
      expect(planned.trainSemanticsLabel, '00:55 출발 열차');

      final noBasis = _viewModel(
        longRide(
          departure: _kst(0, 55),
          arrival: _kst(1, 0),
          realtimeDeparture: _kst(0, 57),
          realtimeArrival: _kst(1, 1),
        ),
      );
      expect(
        (noBasis.timeline.single as JourneyRideNode).remainingLabel,
        isNull,
      );
    });

    test('환승 대기가 1분 미만이면 대기 줄을 만들지 않는다', () {
      final journey = _journey(
        departure: _kst(8, 15),
        arrival: _kst(8, 44),
        transferCount: 1,
        legs: <JourneyLeg>[
          _ride(
            from: 'st-gangnam',
            to: 'st-gyodae',
            departure: _kst(8, 15),
            arrival: _kst(8, 27),
            stops: [
              _stop('st-gangnam', plannedDeparture: _kst(8, 15)),
              _stop('st-gyodae', plannedArrival: _kst(8, 27)),
            ],
          ),
          const JourneyTransferLeg(
            fromStationId: 'st-gyodae',
            toStationId: 'st-gyodae',
            durationSeconds: 180,
          ),
          _ride(
            lineId: 'line-3',
            from: 'st-gyodae',
            to: 'st-yangjae',
            departure: _kst(8, 30),
            arrival: _kst(8, 44),
            stops: [
              _stop('st-gyodae', plannedDeparture: _kst(8, 30)),
              _stop('st-yangjae', plannedArrival: _kst(8, 44)),
            ],
          ),
        ],
      );
      final transfer = _viewModel(journey).timeline[1] as JourneyTransferNode;
      expect(transfer.waitLabel, isNull);
      expect(transfer.semanticsLabel, '교대 환승, 도보 3분');
    });

    test('하차 단계는 하차역 이름과 도착 시각을 갖는다', () {
      final ride =
          _viewModel(_transferJourney()).timeline[1] as JourneyRideNode;
      expect(ride.boardingStationId, 'st-gangnam');
      expect(ride.alightingStationId, 'st-gyodae');
      expect(ride.arrivalTime, '08:27');
      expect(ride.boardingHeading, '강남역');
      expect(ride.alightingHeading, '교대역');
    });
  });

  test('노선명은 알려진 노선 ID만 이름으로 바꾸고 모르는 ID는 그대로 둔다', () {
    expect(journeyLineName('line-2'), '2호선');
    expect(journeyLineName('seoul-9'), '9호선');
    expect(journeyLineName('gyeonggang'), '경강선');
    expect(journeyLineName('korail-gyeongui-jungang'), '경의중앙선');
    expect(journeyLineName('line-private'), 'line-private');
  });

  // #441: 계단 없는 대안 상태(backend #471 JourneyStairFreeAlternative) 안내.
  group('계단 상태 안내', () {
    JourneyStairFreeAlternative alternative(
      JourneyStairFreeAlternativeStatus status,
      JourneyStairFreeFacilityStatus facility,
    ) => JourneyStairFreeAlternative(status: status, facilityStatus: facility);

    test('NOT_FOUND는 계단 없는 경로가 없고 모든 경로가 계단을 지난다고 안내한다', () {
      final notices = journeyStairStatusNotices(
        alternative(
          JourneyStairFreeAlternativeStatus.notFound,
          JourneyStairFreeFacilityStatus.applied,
        ),
      );

      expect(notices.map((notice) => notice.kind), [
        JourneyStairStatusNoticeKind.stairFreeNotFound,
      ]);
      expect(notices.single.title, '계단 없이 갈 수 있는 경로가 없어요');
      expect(notices.single.body, '찾은 경로는 모두 환승할 때 계단을 지나요.');
      expect(
        notices.single.semanticsLabel,
        '계단 없이 갈 수 있는 경로가 없어요. 찾은 경로는 모두 환승할 때 계단을 지나요.',
      );
    });

    test('확인되지 않은 것(UNDETERMINED·UNOBSERVED)은 아무 안내도 하지 않는다', () {
      // #443 QA: 상용 지하철 서비스처럼 "반영하지 못했어요" 류 면책 문구를 띄우지 않는다.
      for (final status in JourneyStairFreeAlternativeStatus.values.where(
        (status) => status != JourneyStairFreeAlternativeStatus.notFound,
      )) {
        for (final facility in JourneyStairFreeFacilityStatus.values) {
          expect(
            journeyStairStatusNotices(alternative(status, facility)),
            isEmpty,
            reason: '${status.wire}/${facility.wire}',
          );
        }
      }
    });

    test('NOT_FOUND는 시설 상태와 무관하게 계단 없는 경로가 없다는 사실만 안내한다', () {
      final notices = journeyStairStatusNotices(
        alternative(
          JourneyStairFreeAlternativeStatus.notFound,
          JourneyStairFreeFacilityStatus.unobserved,
        ),
      );

      expect(notices.map((notice) => notice.kind), [
        JourneyStairStatusNoticeKind.stairFreeNotFound,
      ]);
    });

    test('서버가 상태를 주지 않은 결과(프로필 검색)는 추정해 안내하지 않는다', () {
      expect(journeyStairStatusNotices(null), isEmpty);
    });
  });

  // #441: 계단 없는 경로만 요청했는데 서버가 422 ACCESSIBILITY_CONSTRAINT_UNSATISFIED를
  // 주면 사실과 다음 행동을 안내한다. 내부 판정 용어(검증 등)는 쓰지 않는다.
  test('계단 없는 경로 요청 422는 모바일 문구와 일반 경로 보기 행동을 준다', () {
    final disposition = JourneyErrorDispositions.lookup(
      JourneyOperation.searchJourneys,
      422,
      JourneyErrorCode.accessibilityConstraintUnsatisfied,
    );

    final copy = journeyFailureCopy(disposition);

    expect(copy.message, '계단 없이 갈 수 있는 경로를 찾지 못했어요.');
    expect(copy.detail, '일반 경로를 볼까요? 환승할 때 계단이 있는지 함께 알려 드려요.');
    expect(copy.offersStandardRoutes, isTrue);
    expect(copy.message, isNot(contains('검증')));
  });

  test('다른 거절 응답은 서버 문구를 그대로 쓰고 일반 경로 보기를 주지 않는다', () {
    final disposition = JourneyErrorDispositions.lookup(
      JourneyOperation.searchJourneys,
      422,
      JourneyErrorCode.routeNotFound,
    );

    final copy = journeyFailureCopy(disposition);

    expect(copy.message, '현재 조건에 맞는 경로가 없어요.');
    expect(copy.detail, isNull);
    expect(copy.offersStandardRoutes, isFalse);
    expect(journeyFailureCopy(null).message, '경로를 찾지 못했어요. 잠시 후 다시 시도해 주세요.');
  });
}
