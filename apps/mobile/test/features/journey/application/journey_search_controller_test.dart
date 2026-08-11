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

  test('성공 상태는 서버 응답 객체 전체를 보존하고 선택 상태를 만들지 않는다', () async {
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

JourneySearchSuccess _success() => JourneySearchSuccess(
  contractVersion: JourneyContractVersion.journeySearchV3,
  requestId: '01J9VV0K000000000000000000',
  queryId: 'query',
  calculatedAt: DateTime.utc(2026, 8, 12),
  validUntil: DateTime.utc(2026, 8, 12, 0, 5),
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
  journeys: const <Journey>[],
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
  final List<Completer<JourneySessionResponse>> _sessionCompleters =
      <Completer<JourneySessionResponse>>[];

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    sessionRequests++;
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
    final successful = success;
    if (successful != null) return successful;
    final failure = searchFailure;
    if (failure != null) throw failure;
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
}
