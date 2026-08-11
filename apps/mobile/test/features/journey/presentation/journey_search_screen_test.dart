import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('complete draft는 server-order 후보를 보여주고 exact ID만 선택한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository();
    await _pumpScreen(tester, repository: repository, mobilityType: 'STANDARD');

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(repository.sessionRequests, 1);
    expect(repository.requests, hasLength(1));
    final request = repository.requests.single;
    expect(request.originStationId, 'station-origin');
    expect(request.destinationStationId, 'station-destination');
    expect(request.departure, isA<JourneyDepartureNow>());
    expect(request.timePolicy, TimePolicy.timetableRequired);
    expect(request.mobilityProfile, MobilityProfile.standard);
    expect(request.constraintMode, ConstraintMode.none);
    expect(request.maxTransfers, 3);
    expect(request.alternativeCount, 3);
    expect(find.text('경로 후보 2개'), findsOneWidget);
    final second = find.byKey(const Key('journey-candidate-journey-1'));
    final first = find.byKey(const Key('journey-candidate-journey-2'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(find.textContaining('09:05 도착'), findsNWidgets(2));
    expect(find.textContaining('환승 2회'), findsOneWidget);
    expect(
      tester.getSemantics(first).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    expect(tester.getSize(second).height, greaterThanOrEqualTo(48));

    final candidateSemantics = tester.getSemantics(second);
    expect(
      candidateSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    candidateSemantics.owner!.performAction(
      candidateSemantics.id,
      SemanticsAction.tap,
    );
    await tester.pump();
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.byKey(const Key('selected-journey-journey-1')), findsOneWidget);
    await tester.pump();
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.text('상세'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    final single = _Repository()..journeyIds = <String>['journey-only'];
    await _pumpScreen(tester, repository: single);
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 1개'), findsOneWidget);
    expect(
      find.byKey(const Key('journey-candidate-journey-only')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('계단 회피 profile은 REQUIRE_STEP_FREE로 전송한다', (tester) async {
    final repository = _Repository();
    await _pumpScreen(tester, repository: repository, mobilityType: 'LUGGAGE');

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(
      repository.requests.single.mobilityProfile,
      MobilityProfile.noStairs,
    );
    expect(
      repository.requests.single.constraintMode,
      ConstraintMode.requireStepFree,
    );

    final stepFree = _Repository();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, repository: stepFree, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(stepFree.requests.single.mobilityProfile, MobilityProfile.stepFree);
    expect(
      stepFree.requests.single.constraintMode,
      ConstraintMode.requireStepFree,
    );
  });

  testWidgets('세션 발급 중에는 검색 진행 상태를 보여준다', (tester) async {
    final repository = _Repository();
    final session = Completer<JourneySessionResponse>();
    repository.sessionCompleter = session;
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    session.complete(_sessionResponse());
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 2개'), findsOneWidget);
  });

  testWidgets('incomplete 또는 waypoint draft는 request를 만들지 않는다', (tester) async {
    final incomplete = _Repository();
    await _pumpScreen(
      tester,
      repository: incomplete,
      draft: const RouteDraft.empty(),
    );
    expect(find.text('출발역과 도착역을 다시 확인해 주세요.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(incomplete.requests, isEmpty);

    final waypoint = _Repository();
    await _pumpScreen(
      tester,
      repository: waypoint,
      draft: _completeDraft(waypoint: _station('station-waypoint', '서울')),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(waypoint.requests, isEmpty);
  });

  testWidgets('failure는 안전한 retry만 노출하고 명시 retry가 새 search를 실행한다', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = _Repository()..failuresRemaining = 1;
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, '다시 시도')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.sessionRequests, 1);
    expect(repository.requests, hasLength(2));
    expect(find.text('경로 후보 2개'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _Repository repository,
  RouteDraft? draft,
  String mobilityType = 'STANDARD',
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: JourneySearchScreen(
        repository: repository,
        attestor: const _Attestor(),
        draft: draft ?? _completeDraft(),
        mobilityType: mobilityType,
        onShellBackToHome: () {},
      ),
    ),
  );
}

RouteDraft _completeDraft({RouteDraftStation? waypoint}) => RouteDraft(
  origin: _station('station-origin', '용산'),
  destination: _station('station-destination', '춘천'),
  waypoint: waypoint,
  lastModifiedAt: DateTime.utc(2026, 8, 12),
);

RouteDraftStation _station(String id, String name) =>
    RouteDraftStation(id: id, nameKo: name);

class _Attestor implements JourneyV3IntegrityAttestor {
  const _Attestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class _Repository implements JourneyRepository {
  int sessionRequests = 0;
  int failuresRemaining = 0;
  Completer<JourneySessionResponse>? sessionCompleter;
  List<String> journeyIds = <String>['journey-2', 'journey-1'];
  final List<JourneySearchRequest> requests = <JourneySearchRequest>[];

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    sessionRequests++;
    return sessionCompleter?.future ?? _sessionResponse();
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    requests.add(request);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const JourneyTransportFailure(
        JourneyOperation.searchJourneys,
        'private transport detail',
      );
    }
    return _success(request, journeyIds);
  }
}

JourneySessionResponse _sessionResponse() {
  final now = DateTime.now().toUtc();
  return JourneySessionResponse(
    token: 'session-token',
    scope: JourneySessionScope.journeyV3,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
  );
}

JourneySearchSuccess _success(
  JourneySearchRequest request,
  List<String> journeyIds,
) {
  final now = DateTime.utc(2026, 8, 12);
  return JourneySearchSuccess(
    contractVersion: JourneyContractVersion.journeySearchV3,
    requestId: request.requestId,
    queryId: 'query-1',
    calculatedAt: now,
    validUntil: now.add(const Duration(minutes: 5)),
    effectiveDepartureTime: now,
    serviceDate: JourneyDate.parse('2026-08-12'),
    serviceTimezone: 'Asia/Seoul',
    sourceIdentity: JourneySourceIdentity(
      routeBundleId: 'bundle-1',
      routeBundleSha256: 'a' * 64,
      timetableSnapshotId: 'timetable-1',
      accessibilitySnapshotId: 'accessibility-1',
      realtimeSnapshotId: null,
    ),
    requestPolicy: JourneyRequestPolicy(
      timePolicy: request.timePolicy,
      mobilityProfile: request.mobilityProfile,
      constraintMode: request.constraintMode,
      maxTransfers: request.maxTransfers,
      alternativeCount: request.alternativeCount,
    ),
    journeys: journeyIds.map((id) => _journey(id, now)).toList(growable: false),
  );
}

Journey _journey(String id, DateTime now) => Journey(
  journeyId: id,
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: now,
  plannedArrivalTime: now.add(const Duration(minutes: 5)),
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  durationSeconds: 300,
  transferCount: id == 'journey-1' ? 2 : 0,
  walkingDistanceMeters: 0,
  timeSource: JourneyTimeSource.timetable,
  accessibility: const JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: false,
    reasonCodes: <String>[],
  ),
  legs: const <JourneyLeg>[
    JourneyEntryLeg(fromStationId: 'station-origin', durationSeconds: 0),
  ],
);
