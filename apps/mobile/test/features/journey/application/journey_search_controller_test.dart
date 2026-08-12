import 'dart:async';

import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('검색은 V3 세션 한 번과 search 한 번만 실행하고 IDLE에서 SEARCHING으로 전이한다', () async {
    final repository = _Repository();
    final attestor = _Attestor();
    final controller = JourneySearchController(
      repository: repository,
      attestor: attestor,
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
    );
    final command = JourneySearchCommand(
      originStationId: 'origin',
      destinationStationId: 'destination',
      departure: const JourneyDepartureNow(),
      timePolicy: TimePolicy.timetableRequired,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 1,
      alternativeCount: 1,
    );

    final future = controller.search(command);

    expect(controller.state.status, JourneySearchStatus.searching);
    await future;

    expect(repository.sessionRequests, 1);
    expect(repository.searchRequests, 1);
    expect(attestor.hashes, hasLength(1));
    expect(attestor.hashes.single, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(controller.state.status, JourneySearchStatus.failure);
    expect(controller.state.failure, JourneySearchFailure.unavailable);
  });

  test('retry는 완료된 마지막 command만 새 ULID로 한 번 재시도하고 유효 session을 재사용한다', () async {
    final repository = _Repository();
    final ids = <String>[
      '01J9VV0K000000000000000000',
      '01J9VV0K000000000000000001',
    ].iterator;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () {
        ids.moveNext();
        return ids.current;
      },
    );
    final command = JourneySearchCommand(
      originStationId: 'origin',
      destinationStationId: 'destination',
      departure: const JourneyDepartureNow(),
      timePolicy: TimePolicy.timetableRequired,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 1,
      alternativeCount: 1,
    );

    await controller.search(command);
    await controller.retry();

    expect(repository.sessionRequests, 1);
    expect(repository.requestIds, <String>[
      '01J9VV0K000000000000000000',
      '01J9VV0K000000000000000001',
    ]);
  });

  test('동일 command는 값 동등성과 hash를 보존한다', () {
    final equal = _command();

    expect(equal, _command());
    expect(equal.hashCode, _command().hashCode);
    expect(
      equal,
      isNot(
        JourneySearchCommand(
          originStationId: 'other',
          destinationStationId: 'destination',
          departure: const JourneyDepartureNow(),
          timePolicy: TimePolicy.timetableRequired,
          mobilityProfile: MobilityProfile.standard,
          constraintMode: ConstraintMode.none,
          maxTransfers: 1,
          alternativeCount: 1,
        ),
      ),
    );
  });

  test(
    'SEARCHING listener reset은 session·search·cache side effect 없이 현재 task를 폐기한다',
    () async {
      final repository = _Repository();
      final controller = JourneySearchController(
        repository: repository,
        attestor: _Attestor(),
        now: () => DateTime.utc(2026, 8, 12),
      );
      controller.addListener(() {
        if (controller.state.status == JourneySearchStatus.searching) {
          controller.reset();
        }
      });

      await controller.search(_command());

      expect(repository.sessionRequests, 0);
      expect(repository.searchRequests, 0);
      expect(controller.state.status, JourneySearchStatus.idle);
    },
  );

  test(
    'SEARCHING listener의 supersede는 inner task를 current in-flight로 보존한다',
    () async {
      final repository = _Repository();
      final controller = JourneySearchController(
        repository: repository,
        attestor: _Attestor(),
        now: () => DateTime.utc(2026, 8, 12),
      );
      final replacement = JourneySearchCommand(
        originStationId: 'replacement',
        destinationStationId: 'destination',
        departure: const JourneyDepartureNow(),
        timePolicy: TimePolicy.timetableRequired,
        mobilityProfile: MobilityProfile.standard,
        constraintMode: ConstraintMode.none,
        maxTransfers: 1,
        alternativeCount: 1,
      );
      Future<void>? replacementTask;
      var replaced = false;
      controller.addListener(() {
        if (!replaced &&
            controller.state.status == JourneySearchStatus.searching) {
          replaced = true;
          replacementTask = controller.search(replacement);
        }
      });

      await controller.search(_command());
      await replacementTask;

      expect(repository.searchRequests, 1);
      expect(repository.originIds, <String>['replacement']);
    },
  );

  test('401은 cache를 무효화하지만 자동 재시도 없이 다음 명시 search만 새 session을 발급한다', () async {
    final repository = _Repository()
      ..searchFailures.add(
        JourneyRejectedFailure(
          JourneyOperation.searchJourneys,
          statusCode: 401,
          error: JourneyV3Error(
            contractVersion: JourneyErrorContractVersion.journeyErrorV1,
            requestId: '01J9VV0K000000000000000000',
            code: JourneyErrorCode.routeSessionRequired,
            retryable: false,
            occurredAt: DateTime.utc(2026, 8, 12),
          ),
          disposition: JourneyErrorDispositions.lookup(
            JourneyOperation.searchJourneys,
            401,
            JourneyErrorCode.routeSessionRequired,
          ),
        ),
      );
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
    );

    await controller.search(_command());
    expect(repository.sessionRequests, 1);
    expect(repository.searchRequests, 1);
    await controller.search(_command());

    expect(repository.sessionRequests, 2);
    expect(repository.searchRequests, 2);
  });

  test('stale 401은 newer session cache를 무효화하지 않는다', () async {
    final repository = _Repository()..pendingSearch = true;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
    );
    final newer = JourneySearchCommand(
      originStationId: 'newer',
      destinationStationId: 'destination',
      departure: const JourneyDepartureNow(),
      timePolicy: TimePolicy.timetableRequired,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 1,
      alternativeCount: 1,
    );

    final old = controller.search(_command());
    await Future<void>.delayed(Duration.zero);
    repository.pendingSearch = false;
    await controller.search(newer);
    repository.completePendingSearchError(_sessionRequired401());
    await old;
    await controller.search(newer);

    expect(repository.sessionRequests, 1);
    expect(repository.searchRequests, 3);
  });

  test(
    'session issuance transport failure는 cache를 남기지 않고 다음 명시 search에서 다시 발급한다',
    () async {
      final repository = _Repository()
        ..sessionFailures.add(
          const JourneyTransportFailure(
            JourneyOperation.issueJourneySession,
            'private provider failure',
          ),
        );
      final controller = JourneySearchController(
        repository: repository,
        attestor: _Attestor(),
        now: () => DateTime.utc(2026, 8, 12),
        requestIdGenerator: () => '01J9VV0K000000000000000000',
      );

      await controller.search(_command());
      expect(controller.state.failure, JourneySearchFailure.sessionUnavailable);
      expect(repository.sessionRequests, 1);
      await controller.search(_command());

      expect(repository.sessionRequests, 2);
      expect(repository.searchRequests, 1);
    },
  );

  test('command 없음·in-flight·dispose 상태의 retry는 fail-closed no-op이다', () async {
    final repository = _Repository()..pendingSession = true;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
    );

    await controller.retry();
    final pending = controller.search(_command());
    await Future<void>.delayed(Duration.zero);
    await controller.retry();
    expect(repository.sessionRequests, 1);
    controller.dispose();
    await controller.retry();
    repository.completeSession();
    await pending;
    expect(repository.searchRequests, 0);
  });

  test(
    'protocol·rejected·unknown 오류는 raw detail 없이 안전한 enum으로만 노출한다',
    () async {
      final cases = <(Object, JourneySearchFailure)>[
        (
          const JourneyProtocolFailure(
            JourneyOperation.searchJourneys,
            cause: 'private protocol body',
          ),
          JourneySearchFailure.protocol,
        ),
        (
          JourneyRejectedFailure(
            JourneyOperation.searchJourneys,
            statusCode: 422,
            error: JourneyV3Error(
              contractVersion: JourneyErrorContractVersion.journeyErrorV1,
              requestId: '01J9VV0K000000000000000000',
              code: JourneyErrorCode.routeNotFound,
              retryable: false,
              occurredAt: DateTime.utc(2026, 8, 12),
            ),
            disposition: JourneyErrorDispositions.lookup(
              JourneyOperation.searchJourneys,
              422,
              JourneyErrorCode.routeNotFound,
            ),
          ),
          JourneySearchFailure.requestRejected,
        ),
        (
          StateError('raw token should never surface'),
          JourneySearchFailure.sessionUnavailable,
        ),
      ];
      for (final (failure, expected) in cases) {
        final controller = JourneySearchController(
          repository: _Repository()..searchFailure = failure,
          attestor: _Attestor(),
          now: () => DateTime.utc(2026, 8, 12),
        );
        await controller.search(_command());
        expect(controller.state.failure, expected);
        expect(controller.state.failure.toString(), isNot(contains('raw')));
      }
    },
  );

  test('reset 뒤 late session issuance는 search 또는 cache를 재개하지 않는다', () async {
    final repository = _Repository()..pendingSession = true;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
    );
    final command = JourneySearchCommand(
      originStationId: 'origin',
      destinationStationId: 'destination',
      departure: const JourneyDepartureNow(),
      timePolicy: TimePolicy.timetableRequired,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 1,
      alternativeCount: 1,
    );

    final search = controller.search(command);
    await Future<void>.delayed(Duration.zero);
    controller.reset();
    repository.completeSession();
    await search;

    expect(repository.searchRequests, 0);
    expect(controller.state.status, JourneySearchStatus.idle);
    await controller.search(command);
    expect(repository.sessionRequests, 2);
  });

  test('reset 직후 새 search는 이전 issuance를 재사용하지 않고 새 session만 사용한다', () async {
    final repository = _Repository()..pendingSession = true;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
    );

    final old = controller.search(_command());
    await Future<void>.delayed(Duration.zero);
    controller.reset();
    final current = controller.search(_command());
    await Future<void>.delayed(Duration.zero);
    expect(repository.sessionRequests, 2);

    repository.completeSessionAt(1);
    await current;
    expect(repository.searchRequests, 1);
    repository.completeSessionAt(0);
    await old;

    expect(repository.searchRequests, 1);
    await controller.search(_command());
    expect(repository.sessionRequests, 2);
  });

  test('superseded shared-session waiter는 backend search를 시작하지 않는다', () async {
    final repository = _Repository()..pendingSession = true;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
    );
    final other = JourneySearchCommand(
      originStationId: 'other-origin',
      destinationStationId: 'destination',
      departure: const JourneyDepartureNow(),
      timePolicy: TimePolicy.timetableRequired,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 1,
      alternativeCount: 1,
    );

    final first = controller.search(_command());
    await Future<void>.delayed(Duration.zero);
    final second = controller.search(other);
    repository.completeSession();
    await Future.wait(<Future<void>>[first, second]);

    expect(repository.searchRequests, 1);
    expect(repository.originIds, <String>['other-origin']);
  });

  test(
    'generated integrity spec의 canonical nonce hash를 그대로 attestor에 보낸다',
    () async {
      final attestor = _Attestor();
      final controller = JourneySearchController(
        repository: _Repository(),
        attestor: attestor,
        now: () => DateTime.utc(2026, 8, 12),
        requestIdGenerator: () => '01J9VV0K000000000000000000',
        nonceGenerator: (_) => 'AAAAAAAAAAAAAAAAAAAAAA',
      );

      await controller.search(_command());

      expect(attestor.hashes, <String>[
        'oiyD4z8SIUGWUKR8znsbTQ1Z26WO43JHm3RUZLuwErU',
      ]);
    },
  );

  test('dispose 뒤 late issuance는 backend·state·notify를 건드리지 않는다', () async {
    final repository = _Repository()..pendingSession = true;
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    final pending = controller.search(_command());
    await Future<void>.delayed(Duration.zero);
    final beforeDispose = notifications;
    controller.dispose();
    repository.completeSession();
    await pending;

    expect(repository.searchRequests, 0);
    expect(notifications, beforeDispose);
  });

  test('이미 만료된 response는 current success 없이 protocol failure로 닫는다', () async {
    final timers = <_ManualTimer>[];
    final controller = JourneySearchController(
      repository: _Repository()..success = _success(),
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12, 0, 5),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
      expiryTimerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await controller.search(_command());

    expect(controller.state.status, JourneySearchStatus.failure);
    expect(controller.state.failure, JourneySearchFailure.protocol);
    expect(controller.state.response, isNull);
    expect(controller.state.selectedSnapshot, isNull);
    expect(timers, isEmpty);
  });

  test(
    'backward clock correction은 still-valid response expiry를 재예약한다',
    () async {
      var current = DateTime.utc(2026, 8, 12);
      final timers = <_ManualTimer>[];
      final controller = JourneySearchController(
        repository: _Repository()..success = _success(),
        attestor: _Attestor(),
        now: () => current,
        requestIdGenerator: () => '01J9VV0K000000000000000000',
        expiryTimerFactory: (duration, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );

      await controller.search(_command());
      current = DateTime.utc(2026, 8, 11, 23, 59);
      timers.single.invokeEvenIfCancelled();

      expect(controller.state.status, JourneySearchStatus.success);
      expect(timers, hasLength(2));

      current = DateTime.utc(2026, 8, 12, 0, 5);
      timers.last.invokeEvenIfCancelled();
      expect(controller.state.status, JourneySearchStatus.failure);
      expect(controller.state.failure, JourneySearchFailure.protocol);
    },
  );

  test('forward clock correction은 selection 전에 stale success를 제거한다', () async {
    var current = DateTime.utc(2026, 8, 12);
    final timers = <_ManualTimer>[];
    final controller = JourneySearchController(
      repository: _Repository()..success = _success(),
      attestor: _Attestor(),
      now: () => current,
      requestIdGenerator: () => '01J9VV0K000000000000000000',
      expiryTimerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await controller.search(_command());
    current = DateTime.utc(2026, 8, 12, 0, 6);

    expect(controller.selectJourney('journey-1'), isFalse);
    expect(controller.state.status, JourneySearchStatus.failure);
    expect(controller.state.failure, JourneySearchFailure.protocol);
    expect(controller.state.response, isNull);
    expect(timers.single.isActive, isFalse);
  });

  test('old expiry는 newer response·reset·dispose state를 무효화하지 않는다', () async {
    final timers = <_ManualTimer>[];
    final repository = _Repository()..success = _success();
    final controller = JourneySearchController(
      repository: repository,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
      expiryTimerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await controller.search(_command());
    final oldTimer = timers.single;
    repository.success = _success(
      queryId: 'replacement-query',
      validUntil: DateTime.utc(2026, 8, 12, 0, 10),
    );
    await controller.search(
      JourneySearchCommand(
        originStationId: 'replacement-origin',
        destinationStationId: 'destination',
        departure: const JourneyDepartureNow(),
        timePolicy: TimePolicy.timetableRequired,
        mobilityProfile: MobilityProfile.standard,
        constraintMode: ConstraintMode.none,
        maxTransfers: 1,
        alternativeCount: 1,
      ),
    );

    expect(oldTimer.isActive, isFalse);
    oldTimer.invokeEvenIfCancelled();
    expect(controller.state.response!.queryId, 'replacement-query');

    final replacementTimer = timers.last;
    controller.reset();
    expect(replacementTimer.isActive, isFalse);
    replacementTimer.invokeEvenIfCancelled();
    expect(controller.state.status, JourneySearchStatus.idle);

    controller.dispose();
    replacementTimer.invokeEvenIfCancelled();
  });

  test('성공 후보는 exact journeyId만 명시 선택하고 새 검색은 선택을 지운다', () async {
    final response = _success();
    final controller = JourneySearchController(
      repository: _Repository()..success = response,
      attestor: _Attestor(),
      now: () => DateTime.utc(2026, 8, 12),
      requestIdGenerator: () => '01J9VV0K000000000000000000',
    );

    await controller.search(_command());

    expect(controller.state.status, JourneySearchStatus.success);
    expect(controller.state.response, same(response));
    expect(controller.state.failure, isNull);
    expect(controller.state.selectedJourneyId, isNull);
    expect(controller.state.selectedSnapshot, isNull);

    expect(controller.selectJourney('journey-1'), isTrue);
    expect(controller.state.response, same(response));
    expect(controller.state.selectedJourneyId, 'journey-1');
    final snapshot = controller.state.selectedSnapshot!;
    expect(snapshot.contractVersion, response.contractVersion);
    expect(snapshot.requestId, response.requestId);
    expect(snapshot.queryId, response.queryId);
    expect(snapshot.calculatedAt, response.calculatedAt);
    expect(snapshot.validUntil, response.validUntil);
    expect(snapshot.effectiveDepartureTime, response.effectiveDepartureTime);
    expect(snapshot.serviceDate.toString(), response.serviceDate.toString());
    expect(snapshot.serviceTimezone, response.serviceTimezone);
    expect(
      snapshot.requestPolicy.timePolicy,
      response.requestPolicy.timePolicy,
    );
    expect(
      snapshot.requestPolicy.mobilityProfile,
      response.requestPolicy.mobilityProfile,
    );
    expect(
      snapshot.requestPolicy.constraintMode,
      response.requestPolicy.constraintMode,
    );
    expect(snapshot.requestPolicy.maxTransfers, 1);
    expect(snapshot.requestPolicy.alternativeCount, 1);
    expect(snapshot.sourceIdentity.routeBundleId, 'route');
    expect(snapshot.sourceIdentity.routeBundleSha256, 'a' * 64);
    expect(snapshot.sourceIdentity.timetableSnapshotId, 'timetable');
    expect(snapshot.sourceIdentity.accessibilitySnapshotId, 'accessibility');
    expect(snapshot.sourceIdentity.realtimeSnapshotId, isNull);
    expect(snapshot.journey.journeyId, 'journey-1');
    expect(
      () => snapshot.journey.accessibility.reasonCodes.add('MUTATED'),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.journey.legs.add(
        const JourneyExitLeg(fromStationId: 'destination', durationSeconds: 0),
      ),
      throwsUnsupportedError,
    );
    expect(controller.selectJourney('missing'), isFalse);
    expect(controller.state.selectedSnapshot, same(snapshot));

    final next = controller.search(_command());
    expect(controller.state.status, JourneySearchStatus.searching);
    expect(controller.state.selectedJourneyId, isNull);
    expect(controller.state.selectedSnapshot, isNull);
    await next;
    expect(controller.state.status, JourneySearchStatus.success);
    expect(controller.state.selectedJourneyId, isNull);
    expect(controller.state.selectedSnapshot, isNull);
  });
}

JourneySearchCommand _command() => JourneySearchCommand(
  originStationId: 'origin',
  destinationStationId: 'destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
  mobilityProfile: MobilityProfile.standard,
  constraintMode: ConstraintMode.none,
  maxTransfers: 1,
  alternativeCount: 1,
);

JourneySearchSuccess _success({
  String queryId = 'query',
  DateTime? validUntil,
}) => JourneySearchSuccess(
  contractVersion: JourneyContractVersion.journeySearchV3,
  requestId: '01J9VV0K000000000000000000',
  queryId: queryId,
  calculatedAt: DateTime.utc(2026, 8, 12),
  validUntil: validUntil ?? DateTime.utc(2026, 8, 12, 0, 5),
  effectiveDepartureTime: DateTime.utc(2026, 8, 12),
  serviceDate: JourneyDate.parse('2026-08-12'),
  serviceTimezone: 'Asia/Seoul',
  sourceIdentity: JourneySourceIdentity(
    routeBundleId: 'route',
    routeBundleSha256: 'a' * 64,
    timetableSnapshotId: 'timetable',
    accessibilitySnapshotId: 'accessibility',
    realtimeSnapshotId: null,
  ),
  requestPolicy: const JourneyRequestPolicy(
    timePolicy: TimePolicy.timetableRequired,
    mobilityProfile: MobilityProfile.standard,
    constraintMode: ConstraintMode.none,
    maxTransfers: 1,
    alternativeCount: 1,
  ),
  journeys: <Journey>[_journey('journey-2'), _journey('journey-1')],
);

Journey _journey(String id) => Journey(
  journeyId: id,
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: DateTime.utc(2026, 8, 12),
  plannedArrivalTime: DateTime.utc(2026, 8, 12, 0, 5),
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  durationSeconds: 300,
  transferCount: 0,
  walkingDistanceMeters: 0,
  timeSource: JourneyTimeSource.timetable,
  accessibility: const JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: false,
    reasonCodes: <String>[],
  ),
  legs: const <JourneyLeg>[
    JourneyEntryLeg(fromStationId: 'origin', durationSeconds: 0),
  ],
);

JourneyRejectedFailure _sessionRequired401() => JourneyRejectedFailure(
  JourneyOperation.searchJourneys,
  statusCode: 401,
  error: JourneyV3Error(
    contractVersion: JourneyErrorContractVersion.journeyErrorV1,
    requestId: '01J9VV0K000000000000000000',
    code: JourneyErrorCode.routeSessionRequired,
    retryable: false,
    occurredAt: DateTime.utc(2026, 8, 12),
  ),
  disposition: JourneyErrorDispositions.lookup(
    JourneyOperation.searchJourneys,
    401,
    JourneyErrorCode.routeSessionRequired,
  ),
);

class _Attestor implements JourneyV3IntegrityAttestor {
  final List<String> hashes = <String>[];

  @override
  Future<String> attest(String requestHash) async {
    hashes.add(requestHash);
    return 'integrity-token';
  }
}

class _Repository implements JourneyRepository {
  int sessionRequests = 0;
  int searchRequests = 0;
  final List<String> requestIds = <String>[];
  final List<String> originIds = <String>[];
  bool pendingSession = false;
  JourneySearchSuccess? success;
  Object? searchFailure;
  bool pendingSearch = false;
  final List<Object> searchFailures = <Object>[];
  final List<Object> sessionFailures = <Object>[];
  final List<Completer<JourneySessionResponse>> _sessionCompleters =
      <Completer<JourneySessionResponse>>[];
  final _pendingSearch = Completer<JourneySearchSuccess>();

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    sessionRequests++;
    if (sessionFailures.isNotEmpty) throw sessionFailures.removeAt(0);
    if (pendingSession) {
      final completer = Completer<JourneySessionResponse>();
      _sessionCompleters.add(completer);
      return completer.future;
    }
    return JourneySessionResponse(
      token: 'session-token',
      scope: JourneySessionScope.journeyV3,
      issuedAt: DateTime.utc(2026, 8, 12),
      expiresAt: DateTime.utc(2026, 8, 12, 0, 10),
    );
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    searchRequests++;
    requestIds.add(request.requestId);
    originIds.add(request.originStationId);
    if (pendingSearch) return _pendingSearch.future;
    final successful = success;
    if (successful != null) return successful;
    final failure = searchFailure;
    if (failure != null) throw failure;
    if (searchFailures.isNotEmpty) throw searchFailures.removeAt(0);
    throw const JourneyTransportFailure(
      JourneyOperation.searchJourneys,
      'offline',
    );
  }

  void completeSession() {
    completeSessionAt(0);
  }

  void completeSessionAt(int index) {
    pendingSession = false;
    _sessionCompleters[index].complete(
      JourneySessionResponse(
        token: 'session-token',
        scope: JourneySessionScope.journeyV3,
        issuedAt: DateTime.utc(2026, 8, 12),
        expiresAt: DateTime.utc(2026, 8, 12, 0, 10),
      ),
    );
  }

  void completePendingSearchError(Object error) {
    _pendingSearch.completeError(error);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void invokeEvenIfCancelled() => _callback();
}
