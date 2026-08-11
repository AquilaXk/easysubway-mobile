import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('complete draft는 server-order 후보를 보여주고 exact ID만 선택한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository();
    final shared = <String>[];
    await _pumpScreen(
      tester,
      repository: repository,
      mobilityType: 'STANDARD',
      shareInvoker: (text, _) async => shared.add(text),
    );

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
    expect(find.text('선택 경로 상세'), findsOneWidget);
    final entry = find.text('승강장으로 이동');
    final ride = find.text('열차 탑승');
    final transfer = find.text('환승 이동');
    final exit = find.text('도착역 나가기');
    expect(tester.getTopLeft(entry).dy, lessThan(tester.getTopLeft(ride).dy));
    expect(
      tester.getTopLeft(ride).dy,
      lessThan(tester.getTopLeft(transfer).dy),
    );
    expect(
      tester.getTopLeft(transfer).dy,
      lessThan(tester.getTopLeft(exit).dy),
    );
    final shareButton = find.widgetWithText(OutlinedButton, '공유');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    expect(shared, hasLength(1));
    expect(shared.single, contains('용산역 → 춘천역'));
    expect(shared.single, contains('5분'));
    expect(shared.single, isNot(contains('journey-1')));
    expect(shared.single, isNot(contains('query-1')));
    expect(shared.single, isNot(contains('bundle-1')));
    expect(shared.single, isNot(contains('station-origin')));
    expect(shared.single, isNot(contains('a' * 64)));

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

  testWidgets('다른 후보·새 검색은 기존 Journey 알림 취소 성공 뒤에만 전환한다', (tester) async {
    final repository = _Repository();
    final alarm = _AlarmHarness();
    addTearDown(alarm.dispose);
    await _pumpScreen(
      tester,
      repository: repository,
      getOffAlarmController: alarm.controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
      getOffAlarmNow: () => DateTime.utc(2026, 8, 11, 23, 55),
    );
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journey-candidate-journey-1')));
    await tester.pump();
    final alarmToggle = find.byKey(const Key('journey-get-off-alarm-toggle'));
    await tester.ensureVisible(alarmToggle);
    await tester.tap(alarmToggle);
    for (var index = 0; index < 4; index++) {
      await tester.pump();
    }
    await tester.runAsync(
      () => alarm.repository.saved.future.timeout(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    alarm.notifier.cancelErrorOnce = StateError('cancel failed');
    await tester.tap(find.byKey(const Key('journey-candidate-journey-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-journey-journey-1')), findsOneWidget);
    expect(find.text('기존 하차 알림을 끄지 못해 경로를 바꾸지 않았어요.'), findsOneWidget);

    final requestsBefore = repository.requests.length;
    alarm.notifier.cancelErrorOnce = StateError('cancel failed');
    final searchButton = find.widgetWithText(FilledButton, '경로 찾기');
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(requestsBefore));
    expect(find.byKey(const Key('selected-journey-journey-1')), findsOneWidget);

    final nextCandidate = find.byKey(const Key('journey-candidate-journey-2'));
    await tester.ensureVisible(nextCandidate);
    await tester.tap(nextCandidate);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-journey-journey-2')), findsOneWidget);
    expect(alarm.repository.active, isNull);
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
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (_) async => throw PlatformException(code: 'share_failed'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );
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
    final candidate = find.byKey(const Key('journey-candidate-journey-1'));
    await tester.tap(candidate);
    await tester.pump();
    final shareButton = find.widgetWithText(OutlinedButton, '공유');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsOneWidget);
    expect(
      tester.getSemantics(candidate).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _Repository repository,
  RouteDraft? draft,
  String mobilityType = 'STANDARD',
  JourneyShareInvoker? shareInvoker,
  GetOffAlarmController? getOffAlarmController,
  Future<String> Function(String stationId)? stationNameResolver,
  DateTime Function()? getOffAlarmNow,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: JourneySearchScreen(
        repository: repository,
        attestor: const _Attestor(),
        draft: draft ?? _completeDraft(),
        mobilityType: mobilityType,
        onShellBackToHome: () {},
        shareInvoker: shareInvoker,
        getOffAlarmController: getOffAlarmController,
        stationNameResolver: stationNameResolver,
        getOffAlarmNow: getOffAlarmNow,
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
  legs: <JourneyLeg>[
    const JourneyEntryLeg(fromStationId: 'station-origin', durationSeconds: 60),
    JourneyRideLeg(
      lineId: 'line-private',
      tripId: 'trip-private',
      directionStationId: 'station-direction',
      fromStationId: 'station-origin',
      toStationId: 'station-transfer',
      plannedDepartureTime: now,
      plannedArrivalTime: now.add(const Duration(minutes: 3)),
      realtimeDepartureTime: null,
      realtimeArrivalTime: null,
    ),
    const JourneyTransferLeg(
      fromStationId: 'station-transfer',
      toStationId: 'station-destination',
      durationSeconds: 60,
    ),
    const JourneyExitLeg(
      fromStationId: 'station-destination',
      durationSeconds: 60,
    ),
  ],
);

class _AlarmHarness {
  _AlarmHarness() {
    controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: const _AlarmExactGate(),
      notificationPermissionProvider: const _AlarmPermission(),
      repository: repository,
      now: () => DateTime.utc(2026, 8, 11, 23, 55),
    );
  }

  final notifier = _AlarmNotifier();
  final repository = _AlarmRepository();
  late final GetOffAlarmController controller;

  void dispose() => controller.dispose();
}

class _AlarmNotifier implements GetOffAlarmNotifier {
  Object? cancelErrorOnce;

  @override
  Future<void> cancelAll() async {
    final error = cancelErrorOnce;
    cancelErrorOnce = null;
    if (error != null) throw error;
  }

  @override
  Future<int> pendingAlarmCount() async => 0;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async =>
      ScheduleDeliveryResult(scheduledCount: alarms.length, failedCount: 0);
}

class _AlarmRepository implements GetOffAlarmStateRepository {
  GetOffAlarmSubscription? active;
  final saved = Completer<void>();

  @override
  Future<void> clearActive() async => active = null;

  @override
  Future<GetOffAlarmSubscription?> loadActive() async => active;

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {
    active = subscription;
    if (!saved.isCompleted) saved.complete();
  }
}

class _AlarmExactGate implements ExactAlarmPermissionGate {
  const _AlarmExactGate();

  @override
  Future<bool> isExactAlarmPermitted() async => true;

  @override
  Future<bool> requestExactAlarmPermission() async => true;
}

class _AlarmPermission implements NotificationPermissionProvider {
  const _AlarmPermission();

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async =>
      NotificationPermissionStatus.granted;
}
