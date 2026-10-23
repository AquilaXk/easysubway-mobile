import 'dart:ui' show SemanticsAction, Tristate;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/core/ui/route_role_dot.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/journey/presentation/result/journey_result_widgets.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 시각은 KST로 적고 UTC로 바꿔 넣는다. 기대값은 손으로 적는다.
DateTime _kst(int day, int hour, int minute) => DateTime.utc(
  2026,
  10,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 9));

final _basis = _kst(24, 0, 36);

const _names = <String, String>{
  'st-soyosan': '소요산',
  'st-dongducheon': '동두천',
  'st-bosan': '보산',
  'st-changdong': '창동',
  'st-ssangmun': '쌍문',
  'st-sanggroksu': '상록수',
  'st-geumjeong': '금정',
  'st-direction-1': '동두천',
  'st-direction-4': '쌍문',
};

Future<String> _stationName(String id) async => _names[id] ?? id;

JourneyRideStop _stop(String id, DateTime? at) => JourneyRideStop(
  stationId: id,
  plannedArrivalTime: at,
  plannedDepartureTime: at,
  realtimeArrivalTime: null,
  realtimeDepartureTime: null,
);

JourneyRideLeg _lineOne({
  DateTime? realtimeDeparture,
  List<JourneyAlightingCarDoor> doors = const [
    JourneyAlightingCarDoor(
      carNumber: 8,
      doorNumber: 1,
      targetFacilityType: AlightingTargetFacilityType.transfer,
    ),
  ],
}) => JourneyRideLeg(
  lineId: 'line-1',
  tripId: 'trip-1',
  directionStationId: 'st-direction-1',
  fromStationId: 'st-soyosan',
  toStationId: 'st-changdong',
  plannedDepartureTime: _kst(24, 5, 11),
  plannedArrivalTime: _kst(24, 5, 56),
  realtimeDepartureTime: realtimeDeparture,
  realtimeArrivalTime: realtimeDeparture == null ? null : _kst(24, 5, 56),
  servicePattern: JourneyServicePattern.local,
  stops: [
    _stop('st-soyosan', _kst(24, 5, 11)),
    _stop('st-dongducheon', _kst(24, 5, 14)),
    _stop('st-bosan', _kst(24, 5, 17)),
    _stop('st-changdong', _kst(24, 5, 56)),
  ],
  alightingCarDoors: doors,
);

JourneyRideLeg _lineFour() => JourneyRideLeg(
  lineId: 'line-4',
  tripId: 'trip-4',
  directionStationId: 'st-direction-4',
  fromStationId: 'st-changdong',
  toStationId: 'st-sanggroksu',
  plannedDepartureTime: _kst(24, 6, 1),
  plannedArrivalTime: _kst(24, 7, 28),
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  servicePattern: JourneyServicePattern.local,
  stops: [
    _stop('st-changdong', _kst(24, 6, 1)),
    _stop('st-ssangmun', _kst(24, 6, 3)),
    _stop('st-sanggroksu', _kst(24, 7, 28)),
  ],
  alightingCarDoors: const [],
);

const _availableFare = JourneyFare(
  status: JourneyFareStatus.available,
  adultCardWon: 2850,
  adultCashWon: 2950,
  sourceSnapshotIds: <String>['fare-1'],
);

const _unavailableFare = JourneyFare(
  status: JourneyFareStatus.unavailable,
  sourceSnapshotIds: <String>[],
);

Journey _morning({
  String id = 'journey-fast',
  JourneyFare fare = _availableFare,
  DateTime? realtimeDeparture,
  List<JourneyAlternativeCategory> categories = const [
    JourneyAlternativeCategory.fastest,
  ],
}) => Journey(
  journeyId: id,
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: _kst(24, 5, 11),
  plannedArrivalTime: _kst(24, 7, 28),
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  durationSeconds: 137 * 60,
  transferCount: 1,
  walkingDistanceMeters: 185,
  timeSource: JourneyTimeSource.timetable,
  accessibility: const JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: false,
    reasonCodes: <String>[],
  ),
  legs: [
    _lineOne(realtimeDeparture: realtimeDeparture),
    const JourneyTransferLeg(
      fromStationId: 'st-changdong',
      toStationId: 'st-changdong',
      durationSeconds: 120,
    ),
    _lineFour(),
  ],
  fare: fare,
  alternativeCategories: categories,
);

Journey _fewestTransfers() => Journey(
  journeyId: 'journey-few',
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: _kst(24, 5, 11),
  plannedArrivalTime: _kst(24, 5, 56),
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  durationSeconds: 45 * 60,
  transferCount: 0,
  walkingDistanceMeters: 0,
  timeSource: JourneyTimeSource.timetable,
  accessibility: const JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: false,
    reasonCodes: <String>[],
  ),
  legs: [_lineOne()],
  fare: _availableFare,
  alternativeCategories: const [JourneyAlternativeCategory.fewestTransfers],
);

class _Attestor implements JourneyV3IntegrityAttestor {
  const _Attestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class _Repository implements JourneyRepository {
  _Repository(this.journeys);

  List<Journey> journeys;
  final requests = <JourneySearchRequest>[];
  final profileRequests = <JourneyProfileRequest>[];

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async => JourneySessionResponse(
    token: 'session-token',
    scope: JourneySessionScope.journeyV3,
    issuedAt: _basis,
    expiresAt: _basis.add(const Duration(minutes: 5)),
  );

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    requests.add(request);
    return JourneySearchSuccess(
      contractVersion: JourneyContractVersion.journeySearchV3,
      requestId: request.requestId,
      queryId: 'query-1',
      calculatedAt: _basis,
      validUntil: _basis.add(const Duration(minutes: 5)),
      effectiveDepartureTime: _basis,
      serviceDate: JourneyDate.parse('2026-10-24'),
      serviceTimezone: 'Asia/Seoul',
      serviceDayCutoff: '03:00',
      stairFreeAlternative: null,
      sourceIdentity: JourneySourceIdentity(
        routeBundleId: 'bundle-1',
        routeBundleSha256: 'a' * 64,
        timetableSnapshotId: 'timetable-1',
        accessibilitySnapshotId: 'accessibility-1',
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

  @override
  Future<JourneyProfileSuccess> profileJourneys(
    JourneyProfileRequest request, {
    required String sessionToken,
  }) async {
    profileRequests.add(request);
    return JourneyProfileSuccess(
      contractVersion: 'JOURNEY_PROFILE_V1',
      requestId: request.requestId,
      queryId: 'profile-1',
      calculatedAt: _basis,
      validUntil: _basis.add(const Duration(minutes: 5)),
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
            readyAt: journey.plannedDepartureTime,
            journeyStartTime: journey.plannedDepartureTime,
            firstBoardingTime: journey.plannedDepartureTime,
            arrivalAtPlatform: journey.plannedArrivalTime,
            arrivalAtDestination: journey.plannedArrivalTime,
            objectiveTags: const ['LAST_CONNECTION'],
            journey: journey,
          ),
      ],
    );
  }

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) => throw UnimplementedError('경로 화면은 역 시간표를 직접 부르지 않는다.');
}

RouteDraft _draft() => RouteDraft(
  origin: const RouteDraftStation(
    id: 'st-soyosan',
    nameKo: '소요산',
    lineId: 'line-1',
    lineName: '1호선',
  ),
  destination: const RouteDraftStation(
    id: 'st-sanggroksu',
    nameKo: '상록수',
    lineId: 'line-4',
    lineName: '4호선',
  ),
  lastModifiedAt: _basis,
);

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  double textScale = 1.0,
  double width = 411,
  ValueChanged<String>? onOpenStation,
  ValueChanged<String>? onOpenStationTimetable,
  String mobilityType = 'STANDARD',
}) async {
  tester.view.physicalSize = Size(width, 915) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: JourneySearchScreen(
        repository: repository,
        attestor: const _Attestor(),
        draft: _draft(),
        mobilityType: mobilityType,
        onShellBackToHome: () {},
        journeyNow: () => _basis,
        stationNameResolver: _stationName,
        onOpenStation: onOpenStation,
        onOpenStationTimetable: onOpenStationTimetable,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester) async {
  final submit = find.byKey(const Key('journey-search-submit-button'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Color? _textColor(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style?.color;

void main() {
  group('입력 카드(7-46)', () {
    testWidgets('출발은 초록 점, 도착은 빨강 점이고 노선 마크와 역할 배지가 없다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _Repository([_morning()]));

      final card = find.byKey(const Key('journey-route-input-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(LineMark)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('출발')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('도착')),
        findsNothing,
      );

      final origin = tester.widget<RouteRoleDot>(
        find.byKey(const Key('journey-route-dot-origin')),
      );
      final destination = tester.widget<RouteRoleDot>(
        find.byKey(const Key('journey-route-dot-destination')),
      );
      expect(origin.color, EasySubwayRouteDotColors.origin);
      expect(destination.color, EasySubwayRouteDotColors.destination);
      expect(find.bySemanticsLabel('출발 소요산역'), findsOneWidget);
      expect(find.bySemanticsLabel('도착 상록수역'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('시간 줄과 출발 시각 시트(7-49, 7-52)', () {
    testWidgets('지금 출발은 오늘 HH:MM 출발이고 다음열차는 결과 전에는 누를 수 없다', (tester) async {
      await _pump(tester, _Repository([_morning()]));

      expect(find.text('오늘 00:36 출발'), findsOneWidget);
      expect(find.text('이전열차'), findsNothing);
      final next = tester.widget<TextButton>(
        find.byKey(const Key('journey-departure-bar-next')),
      );
      expect(next.onPressed, isNull);
      expect(find.text('출발 대안'), findsNothing);
      expect(find.text('안심 막차'), findsNothing);
    });

    testWidgets('다음열차는 고른 경로 첫 열차 출발 1분 뒤로 다시 검색한다', (tester) async {
      final repository = _Repository([_morning()]);
      await _pump(tester, repository);
      await _search(tester);

      await tester.tap(find.byKey(const Key('journey-departure-bar-next')));
      await tester.pumpAndSettle();

      expect(repository.requests, hasLength(2));
      final departure = repository.requests.last.departure;
      expect(departure, isA<JourneyDepartureScheduled>());
      expect(
        (departure as JourneyDepartureScheduled).requestedAt,
        _kst(24, 5, 12),
      );
      expect(find.text('오늘 05:12 출발'), findsOneWidget);
    });

    testWidgets('시트는 서버가 받는 출발 시각과 막차만 고르게 한다', (tester) async {
      final repository = _Repository([_morning()]);
      await _pump(tester, repository);

      await tester.tap(find.byKey(const Key('journey-departure-bar-time')));
      await tester.pumpAndSettle();

      expect(find.text('출발 시각 설정'), findsOneWidget);
      expect(find.text('출발 시각'), findsOneWidget);
      expect(find.text('막차'), findsWidgets);
      expect(find.text('도착 시각'), findsNothing);
      expect(find.text('첫차'), findsNothing);
      expect(find.text('지금 출발'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
      expect(
        find.byKey(const Key('journey-departure-sheet-hour')),
        findsOneWidget,
      );
      expect(find.text('오늘'), findsWidgets);
      expect(find.text('내일'), findsWidgets);
      expect(find.text('10월 26일(월)'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-mode-lastTrain')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('journey-departure-sheet-hour')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('journey-departure-sheet-ampm')),
        findsNothing,
      );

      // 00:36은 운행일 경계(03:00) 전이라 지금 운행일은 10월 23일이다.
      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('10월 23일(금) 막차'), findsOneWidget);

      await _search(tester);
      expect(repository.profileRequests, hasLength(1));
      final query = repository.profileRequests.single.temporalQuery;
      expect(query, isA<JourneyLastConnectionQuery>());
      expect((query as JourneyLastConnectionQuery).serviceDate, '2026-10-23');
    });

    testWidgets('확인은 휠에서 고른 날짜와 시각으로 출발 시각을 정한다', (tester) async {
      final repository = _Repository([_morning()]);
      await _pump(tester, repository);
      await tester.tap(find.byKey(const Key('journey-departure-bar-time')));
      await tester.pumpAndSettle();

      // 처음 값은 지금(오늘 오전 12시 36분)이다. 날짜를 한 칸 내려 내일, 시를 한 칸
      // 올려 11시, 분을 한 칸 내려 37분으로 고른다.
      await _nudgeWheel(tester, 'journey-departure-sheet-date', 1);
      await _nudgeWheel(tester, 'journey-departure-sheet-hour', -1);
      await _nudgeWheel(tester, 'journey-departure-sheet-minute', 1);
      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('내일 11:37 출발'), findsOneWidget);
      await _search(tester);
      final departure =
          repository.requests.single.departure as JourneyDepartureScheduled;
      expect(departure.requestedAt, _kst(25, 11, 37));
    });

    testWidgets('막차를 고른 뒤 시트를 다시 열면 막차와 날짜 휠만 보이고, 출발 시각으로 돌아가면 시각을 지킨다', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _Repository([_morning()]));
      final bar = find.byKey(const Key('journey-departure-bar-time'));
      final lastTrain = find.byKey(
        const Key('journey-departure-sheet-mode-lastTrain'),
      );

      await tester.tap(bar);
      await tester.pumpAndSettle();
      await tester.tap(lastTrain);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(lastTrain).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        find.byKey(const Key('journey-departure-sheet-hour')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-mode-departAt')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const Key('journey-departure-sheet-hour')))
            .value,
        '12',
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const Key('journey-departure-sheet-minute')),
            )
            .value,
        '36',
      );
      semantics.dispose();
    });

    testWidgets('휠은 스크린리더의 올리기·내리기로 한 칸씩 움직이고 오전·오후를 바꿀 수 있다', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _Repository([_morning()]);
      await _pump(tester, repository);
      await tester.tap(find.byKey(const Key('journey-departure-bar-time')));
      await tester.pumpAndSettle();

      final minute = find.byKey(const Key('journey-departure-sheet-minute'));
      var node = tester.getSemantics(minute);
      expect(node.value, '36');
      expect(node.increasedValue, '37');
      expect(node.decreasedValue, '35');
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      node = tester.getSemantics(minute);
      expect(node.value, '37');
      node.owner!.performAction(node.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      node.owner!.performAction(node.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(minute).value, '35');

      await _nudgeWheel(tester, 'journey-departure-sheet-ampm', 1);
      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('오늘 12:35 출발'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('지금 출발은 지금 출발 검색으로 돌아간다', (tester) async {
      final repository = _Repository([_morning()]);
      await _pump(tester, repository);
      await tester.tap(find.byKey(const Key('journey-departure-bar-time')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('journey-departure-sheet-mode-lastTrain')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('journey-departure-sheet-now')));
      await tester.pumpAndSettle();

      expect(find.text('오늘 00:36 출발'), findsOneWidget);
      await _search(tester);
      expect(repository.requests.single.departure, isA<JourneyDepartureNow>());
    });
  });

  group('기준 탭과 요약(7-49)', () {
    testWidgets('탭은 최단시간·최소환승이고 최저요금은 없다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _Repository([_morning(), _fewestTransfers()]));
      await _search(tester);

      expect(find.text('최단시간'), findsOneWidget);
      expect(find.text('최소환승'), findsOneWidget);
      expect(find.text('최저요금'), findsNothing);
      expect(find.text('경로 후보 2개'), findsNothing);
      expect(find.text('2시간 17분'), findsOneWidget);
      // 기준 탭은 한 줄에 왼쪽부터 놓인다.
      final fastest = find.byKey(const Key('journey-criterion-fastest'));
      final fewest = find.byKey(const Key('journey-criterion-fewestTransfers'));
      expect(
        tester.getTopLeft(fastest).dx,
        lessThan(tester.getTopLeft(fewest).dx),
      );
      expect(tester.getTopLeft(fastest).dy, tester.getTopLeft(fewest).dy);
      expect(find.bySemanticsLabel(RegExp('^2시간 17분 소요')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('journey-criterion-fewestTransfers')),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^45분 소요')), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.byKey(const Key('journey-criterion-fewestTransfers')),
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      semantics.dispose();
    });

    testWidgets('막차 탭은 지금 운행일(03:00 경계)의 막차를 검색한다', (tester) async {
      final repository = _Repository([_morning()]);
      await _pump(tester, repository);
      await _search(tester);

      await tester.tap(find.byKey(const Key('journey-last-train-tab')));
      await tester.pumpAndSettle();

      final query =
          repository.profileRequests.single.temporalQuery
              as JourneyLastConnectionQuery;
      expect(query.serviceDate, '2026-10-23');
      expect(find.text('10월 23일(금) 막차'), findsOneWidget);
    });

    testWidgets('요약은 큰 총시간, 오전 시각 범위와 운임 한 줄이다', (tester) async {
      await _pump(tester, _Repository([_morning()]));
      await _search(tester);

      final summary = find.byKey(const Key('journey-summary'));
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('오전 5:11 - 오전 7:28'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('2,850원')),
        findsOneWidget,
      );
      expect(find.textContaining('카드'), findsNothing);
      expect(find.textContaining('도보 185m'), findsNothing);
    });

    testWidgets('운임이 없으면 운임 칸을 숨긴다', (tester) async {
      await _pump(tester, _Repository([_morning(fare: _unavailableFare)]));
      await _search(tester);

      final summary = find.byKey(const Key('journey-summary'));
      expect(
        find.descendant(of: summary, matching: find.textContaining('원')),
        findsNothing,
      );
      expect(
        find.descendant(of: summary, matching: find.text('오전 5:11 - 오전 7:28')),
        findsOneWidget,
      );
    });

    testWidgets('구간 막대는 위에 출발 시각, 아래에 승차역을 노선 글자색으로 쓴다', (tester) async {
      await _pump(tester, _Repository([_morning()]));
      await _search(tester);

      final bar = find.byKey(const Key('journey-segment-bar'));
      expect(
        find.descendant(of: bar, matching: find.text('05:11')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('06:01')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('45분')),
        findsOneWidget,
      );
      final soyosan = find.descendant(of: bar, matching: find.text('소요산'));
      expect(soyosan, findsOneWidget);
      expect(
        _textColor(tester, soyosan),
        lineInkOnWhite(journeyLineColor('line-1')),
      );
      // 4호선 하늘색은 흰 바탕 대비가 모자라 같은 색상에서 어둡게 쓴다.
      final changdong = find.descendant(of: bar, matching: find.text('창동'));
      final lineFour = journeyLineColor('line-4');
      expect(_textColor(tester, changdong), lineInkOnWhite(lineFour));
      expect(_textColor(tester, changdong), isNot(lineFour));
      expect(
        find.descendant(of: bar, matching: find.byType(LineMark)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: bar, matching: find.textContaining('(첫)')),
        findsNothing,
      );
    });
  });

  group('상세 타임라인(7-51)', () {
    testWidgets('기준 시각 줄과 승차·하차·환승 단계를 서버 값으로만 그린다', (tester) async {
      await _pump(tester, _Repository([_morning()]));
      await _search(tester);

      expect(find.text('오전 12:36 기준 (출발 대기 4시간 35분)'), findsOneWidget);
      expect(find.text('1호선 소요산역', findRichText: true), findsOneWidget);
      expect(find.text('동두천역 방면'), findsOneWidget);
      expect(find.text('빠른 환승: 8-1'), findsOneWidget);
      expect(find.text('창동역', findRichText: true), findsOneWidget);
      expect(find.text('도보 2분'), findsOneWidget);
      expect(find.text('환승 대기 3분'), findsOneWidget);
      expect(find.text('3개 역 이동 · 45분'), findsOneWidget);

      // 서버 응답에 없는 값의 줄은 없다.
      expect(find.textContaining('타는 곳'), findsNothing);
      expect(find.textContaining('내리는 문'), findsNothing);
      expect(find.textContaining('빠른 하차'), findsNothing);
      expect(find.textContaining('행'), findsNothing);
      expect(find.textContaining('(첫)'), findsNothing);
      expect(find.textContaining('운행 종료'), findsNothing);
    });

    testWidgets('정차역을 펼치면 시각과 역 이름이 나온다', (tester) async {
      await _pump(tester, _Repository([_morning()]));
      await _search(tester);

      final toggle = find.byKey(const Key('journey-ride-stops-toggle-0'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.text('05:14'), findsOneWidget);
      expect(find.text('동두천역'), findsOneWidget);
      expect(find.text('05:17'), findsOneWidget);
      expect(find.text('보산역'), findsOneWidget);
    });

    testWidgets('열차 카드의 남은 분은 실시간 출발이 있을 때만 빨강으로 쓴다', (tester) async {
      await _pump(
        tester,
        _Repository([_morning(realtimeDeparture: _kst(24, 0, 47))]),
      );
      await _search(tester);

      final remaining = find.byKey(const Key('journey-train-remaining-0'));
      expect(remaining, findsOneWidget);
      expect(tester.widget<Text>(remaining).data, '11분');
      expect(
        _textColor(tester, remaining),
        EasySubwayAccessibleColors.statusDangerContent,
      );
      expect(find.byKey(const Key('journey-train-remaining-2')), findsNothing);
    });

    testWidgets('실시간·시간표 칩과 역 이름은 기존 역 화면을 연다', (tester) async {
      final opened = <String>[];
      final timetables = <String>[];
      await _pump(
        tester,
        _Repository([_morning()]),
        onOpenStation: opened.add,
        onOpenStationTimetable: timetables.add,
      );
      await _search(tester);

      final realtime = find.byKey(const Key('journey-ride-realtime-0'));
      await tester.ensureVisible(realtime);
      await tester.tap(realtime);
      await tester.tap(find.byKey(const Key('journey-ride-timetable-0')));
      await tester.tap(find.byKey(const Key('journey-ride-heading-0')));
      await tester.pumpAndSettle();

      expect(opened, ['st-soyosan', 'st-soyosan']);
      expect(timetables, ['st-soyosan']);
    });

    testWidgets('연결할 화면이 없으면 칩을 그리지 않는다', (tester) async {
      await _pump(tester, _Repository([_morning()]));
      await _search(tester);

      expect(find.byKey(const Key('journey-ride-realtime-0')), findsNothing);
      expect(find.byKey(const Key('journey-ride-timetable-0')), findsNothing);
    });
  });

  testWidgets('글자 2.0배에서 결과와 상세가 넘치지 않는다', (tester) async {
    await _pump(
      tester,
      _Repository([_morning(realtimeDeparture: _kst(24, 0, 47))]),
      textScale: 2.0,
      width: 360,
      onOpenStation: (_) {},
      onOpenStationTimetable: (_) {},
    );
    await _search(tester);
    expect(tester.takeException(), isNull);

    final toggle = find.byKey(const Key('journey-ride-stops-toggle-0'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('journey-departure-bar-time')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// 휠을 [items]칸 돌린다. 양수는 다음 값(아래 칸)이다. 휠 한 칸은 글자 1.0배에서 40dp다.
Future<void> _nudgeWheel(WidgetTester tester, String key, int items) async {
  await tester.timedDrag(
    find.byKey(Key(key)),
    Offset(0, -40.0 * items),
    const Duration(milliseconds: 600),
  );
  await tester.pumpAndSettle();
}
