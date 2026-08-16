import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/journey/data/journey_api_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedPost {
  const _RecordedPost(this.path, this.body, this.headers);

  final String path;
  final Map<String, Object?> body;
  final Map<String, String> headers;
}

class _StubApiClient extends ApiClient {
  _StubApiClient(this._responses, {this.error})
    : super(baseUri: Uri.parse('https://journey.example.test'));

  final List<ApiResponse> _responses;
  final Object? error;
  final posts = <_RecordedPost>[];

  @override
  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    posts.add(_RecordedPost(path, Map<String, Object?>.of(body), headers));
    if (error != null) throw error!;
    return _responses.removeAt(0);
  }
}

final _sessionRequest = JourneySessionRequest(
  integrityToken: 'integrity-token',
  clientNonce: 'AAAAAAAAAAAAAAAAAAAAAA',
);

final _searchRequest = JourneySearchRequest(
  requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
  walkingPace: WalkingPace.standard,
  mobilityProfile: MobilityProfile.standard,
  constraintMode: ConstraintMode.none,
  maxTransfers: 2,
  alternativeCount: 2,
);

final _stepFreeSearchRequest = JourneySearchRequest(
  requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
  walkingPace: WalkingPace.standard,
  mobilityProfile: MobilityProfile.stepFree,
  constraintMode: ConstraintMode.requireStepFree,
  maxTransfers: 2,
  alternativeCount: 2,
);

final _singleAlternativeSearchRequest = JourneySearchRequest(
  requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
  walkingPace: WalkingPace.standard,
  mobilityProfile: MobilityProfile.standard,
  constraintMode: ConstraintMode.none,
  maxTransfers: 2,
  alternativeCount: 1,
);

final _realtimeSearchRequest = JourneySearchRequest(
  requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.realtimeRequired,
  walkingPace: WalkingPace.standard,
  mobilityProfile: MobilityProfile.standard,
  constraintMode: ConstraintMode.none,
  maxTransfers: 2,
  alternativeCount: 2,
);

Map<String, Object?> _sessionJson() => JourneySessionResponse(
  token: 'session-token',
  scope: JourneySessionScope.journeyV3,
  issuedAt: DateTime.parse('2026-08-11T00:00:00Z'),
  expiresAt: DateTime.parse('2026-08-11T01:00:00Z'),
).toJson();

Map<String, Object?> _successJson({
  String? requestId,
  List<String> journeyIds = const ['journey-2', 'journey-1'],
  JourneySearchRequest? request,
  List<bool>? stairFreeByJourney,
}) {
  final effectiveRequest = request ?? _searchRequest;
  final realtime = effectiveRequest.timePolicy == TimePolicy.realtimeRequired;
  final policy = JourneyRequestPolicy(
    timePolicy: effectiveRequest.timePolicy,
    walkingPace: effectiveRequest.walkingPace,
    mobilityProfile: effectiveRequest.mobilityProfile,
    constraintMode: effectiveRequest.constraintMode,
    maxTransfers: effectiveRequest.maxTransfers,
    alternativeCount: effectiveRequest.alternativeCount,
  );
  final journeys = journeyIds
      .asMap()
      .entries
      .map(
        (entry) => Journey(
          journeyId: entry.value,
          status: JourneyStatus.found,
          planSource: JourneyPlanSource.serverTimetableRaptor,
          plannedDepartureTime: DateTime.parse('2026-08-11T00:00:00Z'),
          plannedArrivalTime: DateTime.parse('2026-08-11T00:05:00Z'),
          realtimeDepartureTime: realtime
              ? DateTime.parse('2026-08-11T00:01:00Z')
              : null,
          realtimeArrivalTime: realtime
              ? DateTime.parse('2026-08-11T00:06:00Z')
              : null,
          durationSeconds: 300,
          transferCount: 0,
          walkingDistanceMeters: 0,
          timeSource: realtime
              ? JourneyTimeSource.realtime
              : JourneyTimeSource.timetable,
          accessibility: JourneyAccessibility(
            result: JourneyAccessibilityResult.verified,
            stairFree: stairFreeByJourney?[entry.key] ?? false,
            reasonCodes: const [],
          ),
          legs: realtime
              ? [
                  JourneyRideLeg(
                    lineId: 'line-1',
                    tripId: 'trip-1',
                    directionStationId: 'station-destination',
                    fromStationId: 'station-origin',
                    toStationId: 'station-destination',
                    plannedDepartureTime: DateTime.parse(
                      '2026-08-11T00:00:00Z',
                    ),
                    plannedArrivalTime: DateTime.parse('2026-08-11T00:05:00Z'),
                    realtimeDepartureTime: DateTime.parse(
                      '2026-08-11T00:01:00Z',
                    ),
                    realtimeArrivalTime: DateTime.parse('2026-08-11T00:06:00Z'),
                  ),
                ]
              : const [
                  JourneyEntryLeg(
                    fromStationId: 'station-origin',
                    durationSeconds: 0,
                  ),
                ],
        ),
      )
      .toList(growable: false);
  return JourneySearchSuccess(
    contractVersion: JourneyContractVersion.journeySearchV3,
    requestId: requestId ?? effectiveRequest.requestId,
    queryId: 'query-1',
    calculatedAt: DateTime.parse('2026-08-11T00:00:00Z'),
    validUntil: DateTime.parse('2026-08-11T00:05:00Z'),
    effectiveDepartureTime: DateTime.parse('2026-08-11T00:00:00Z'),
    serviceDate: JourneyDate.parse('2026-08-11'),
    serviceTimezone: 'Asia/Seoul',
    sourceIdentity: JourneySourceIdentity(
      routeBundleId: 'bundle-1',
      routeBundleSha256: 'a' * 64,
      timetableSnapshotId: 'timetable-1',
      accessibilitySnapshotId: 'accessibility-1',
      realtimeSnapshotId: realtime ? 'realtime-1' : null,
    ),
    requestPolicy: policy,
    journeys: journeys,
  ).toJson();
}

Map<String, Object?> _mutateFirstJourney(
  Map<String, Object?> body,
  void Function(Map<String, Object?> journey) mutate,
) {
  final result = Map<String, Object?>.of(body);
  final journeys = List<Object?>.of(result['journeys']! as List<Object?>);
  final first = Map<String, Object?>.of(
    journeys.first! as Map<String, Object?>,
  );
  mutate(first);
  journeys[0] = first;
  result['journeys'] = journeys;
  return result;
}

Map<String, Object?> _mutateFirstRide(
  Map<String, Object?> body,
  void Function(Map<String, Object?> ride) mutate,
) => _mutateFirstJourney(body, (journey) {
  final legs = List<Object?>.of(journey['legs']! as List<Object?>);
  final ride = Map<String, Object?>.of(legs.first! as Map<String, Object?>);
  mutate(ride);
  legs[0] = ride;
  journey['legs'] = legs;
});

Map<String, Object?> _errorJson(String code) => {
  'contractVersion': 'JOURNEY_ERROR_V1',
  'requestId': _searchRequest.requestId,
  'code': code,
  'retryable': false,
  'occurredAt': '2026-08-11T00:00:00Z',
};

void main() {
  test('session과 search는 exact V3 direct JSON으로 각각 한 번만 호출한다', () async {
    final client = _StubApiClient([
      ApiResponse(statusCode: 200, jsonBody: _sessionJson()),
      ApiResponse(statusCode: 200, jsonBody: _successJson()),
    ]);
    final repository = JourneyApiRepository(client);

    final session = await repository.issueSession(_sessionRequest);
    await repository.searchJourneys(
      _searchRequest,
      sessionToken: session.token,
    );

    expect(client.posts, hasLength(2));
    expect(client.posts[0].path, '/api/v3/journeys/session');
    expect(client.posts[0].body, _sessionRequest.toJson());
    expect(client.posts[0].headers, isEmpty);
    expect(client.posts[1].path, '/api/v3/journeys/search');
    expect(client.posts[1].body, _searchRequest.toJson());
    expect(client.posts[1].body['walkingPace'], 'STANDARD');
    expect(client.posts[1].headers, {'Authorization': 'Bearer session-token'});
  });

  test('valid search success의 identity·server order·source를 보존한다', () async {
    final client = _StubApiClient([
      ApiResponse(statusCode: 200, jsonBody: _successJson()),
    ]);
    final repository = JourneyApiRepository(client);

    final success = await repository.searchJourneys(
      _searchRequest,
      sessionToken: 'session-token',
    );

    expect(client.posts, hasLength(1));
    expect(success.requestId, _searchRequest.requestId);
    expect(success.journeys.map((value) => value.journeyId), [
      'journey-2',
      'journey-1',
    ]);
    expect(
      success.journeys.every(
        (value) => value.planSource == JourneyPlanSource.serverTimetableRaptor,
      ),
      isTrue,
    );
    expect(success.sourceIdentity.routeBundleId, 'bundle-1');
    expect(success.sourceIdentity.routeBundleSha256, 'a' * 64);
    expect(success.sourceIdentity.timetableSnapshotId, 'timetable-1');
    expect(success.sourceIdentity.accessibilitySnapshotId, 'accessibility-1');
    expect(success.sourceIdentity.realtimeSnapshotId, isNull);
    expect(success.requestPolicy.walkingPace, WalkingPace.standard);
    expect(
      success.journeys.every((journey) => !journey.accessibility.stairFree),
      isTrue,
    );
  });

  test('REQUIRE_STEP_FREE는 모든 candidate의 verified stair-free를 요구한다', () async {
    final invalidClient = _StubApiClient([
      ApiResponse(
        statusCode: 200,
        jsonBody: _successJson(
          request: _stepFreeSearchRequest,
          stairFreeByJourney: const [true, false],
        ),
      ),
    ]);
    final validClient = _StubApiClient([
      ApiResponse(
        statusCode: 200,
        jsonBody: _successJson(
          request: _stepFreeSearchRequest,
          stairFreeByJourney: const [true, true],
        ),
      ),
    ]);

    await expectLater(
      JourneyApiRepository(
        invalidClient,
      ).searchJourneys(_stepFreeSearchRequest, sessionToken: 'session-token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    final success = await JourneyApiRepository(
      validClient,
    ).searchJourneys(_stepFreeSearchRequest, sessionToken: 'session-token');

    expect(invalidClient.posts, hasLength(1));
    expect(validClient.posts, hasLength(1));
    expect(
      success.journeys.every((journey) => journey.accessibility.stairFree),
      isTrue,
    );
  });

  test('Backend-domain response 교차필드 invariant 위반은 전체 실패다', () async {
    final expired = Map<String, Object?>.of(_successJson())
      ..['validUntil'] = '2026-08-11T00:00:00.000Z';
    final wrongServiceDate = Map<String, Object?>.of(_successJson())
      ..['serviceDate'] = '2026-08-12';
    final excessCandidates = _successJson(
      request: _singleAlternativeSearchRequest,
      journeyIds: const ['journey-1', 'journey-2'],
    );
    final reversedCandidatePlanned = _mutateFirstJourney(_successJson(), (
      journey,
    ) {
      journey['plannedArrivalTime'] = '2026-08-10T23:59:00.000Z';
    });
    final reversedCandidateRealtime = _mutateFirstJourney(
      _successJson(request: _realtimeSearchRequest),
      (journey) {
        journey['realtimeArrivalTime'] = '2026-08-11T00:00:30.000Z';
      },
    );
    final reversedRidePlanned = _mutateFirstRide(
      _successJson(request: _realtimeSearchRequest),
      (ride) {
        ride['plannedArrivalTime'] = '2026-08-10T23:59:00.000Z';
      },
    );
    final reversedRideRealtime = _mutateFirstRide(
      _successJson(request: _realtimeSearchRequest),
      (ride) {
        ride['realtimeArrivalTime'] = '2026-08-11T00:00:30.000Z';
      },
    );
    final blankAccessibilityReason = _mutateFirstJourney(_successJson(), (
      journey,
    ) {
      final accessibility = Map<String, Object?>.of(
        journey['accessibility']! as Map<String, Object?>,
      )..['reasonCodes'] = const ['   '];
      journey['accessibility'] = accessibility;
    });
    final cases = <(JourneySearchRequest, Map<String, Object?>)>[
      (_searchRequest, expired),
      (_searchRequest, wrongServiceDate),
      (_singleAlternativeSearchRequest, excessCandidates),
      (_searchRequest, reversedCandidatePlanned),
      (_realtimeSearchRequest, reversedCandidateRealtime),
      (_realtimeSearchRequest, reversedRidePlanned),
      (_realtimeSearchRequest, reversedRideRealtime),
      (_searchRequest, blankAccessibilityReason),
    ];

    for (final (request, body) in cases) {
      final client = _StubApiClient([
        ApiResponse(statusCode: 200, jsonBody: body),
      ]);

      await expectLater(
        JourneyApiRepository(
          client,
        ).searchJourneys(request, sessionToken: 'session-token'),
        throwsA(isA<JourneyProtocolFailure>()),
      );
      expect(client.posts, hasLength(1));
    }
  });

  test(
    'representative rejected response와 generated disposition table을 보존한다',
    () async {
      const searchCases = [
        (400, 'INVALID_JOURNEY_REQUEST'),
        (404, 'STATION_NOT_FOUND'),
        (422, 'ROUTE_NOT_FOUND'),
        (422, 'ACCESSIBILITY_CONSTRAINT_UNSATISFIED'),
        (503, 'ROUTING_BUNDLE_UNAVAILABLE'),
        (503, 'ROUTING_BUNDLE_STALE'),
        (503, 'TIMETABLE_UNAVAILABLE'),
        (503, 'TIMETABLE_STALE'),
        (503, 'REALTIME_REQUIRED_UNAVAILABLE'),
        (503, 'ROUTING_IDENTITY_MISMATCH'),
        (503, 'ROUTE_SERVICE_UNAVAILABLE'),
        (504, 'JOURNEY_SEARCH_TIMEOUT'),
        (401, 'ROUTE_SESSION_REQUIRED'),
        (429, 'ROUTE_RATE_LIMITED'),
      ];
      const sessionCases = [
        (400, 'INVALID_JOURNEY_SESSION_REQUEST'),
        (403, 'ROUTE_SESSION_ATTESTATION_REJECTED'),
        (503, 'ROUTE_SESSION_ATTESTATION_UNAVAILABLE'),
      ];

      final representativeClient = _StubApiClient([
        ApiResponse(
          statusCode: 401,
          jsonBody: _errorJson('ROUTE_SESSION_REQUIRED'),
        ),
      ]);
      final representative = JourneyApiRepository(representativeClient);
      await expectLater(
        representative.searchJourneys(
          _searchRequest,
          sessionToken: 'expired-token',
        ),
        throwsA(
          isA<JourneyRejectedFailure>()
              .having(
                (value) => value.error.code,
                'code',
                JourneyErrorCode.routeSessionRequired,
              )
              .having((value) => value.disposition.httpStatus, 'status', 401),
        ),
      );
      expect(representativeClient.posts, hasLength(1));

      for (final (statusCode, code) in searchCases) {
        final repository = JourneyApiRepository(
          _StubApiClient([
            ApiResponse(statusCode: statusCode, jsonBody: _errorJson(code)),
          ]),
        );
        await expectLater(
          repository.searchJourneys(_searchRequest, sessionToken: 'token'),
          throwsA(
            isA<JourneyRejectedFailure>()
                .having((value) => value.statusCode, 'status', statusCode)
                .having((value) => value.error.code.wire, 'code', code),
          ),
        );
      }
      for (final (statusCode, code) in sessionCases) {
        final repository = JourneyApiRepository(
          _StubApiClient([
            ApiResponse(statusCode: statusCode, jsonBody: _errorJson(code)),
          ]),
        );
        await expectLater(
          repository.issueSession(_sessionRequest),
          throwsA(
            isA<JourneyRejectedFailure>()
                .having((value) => value.statusCode, 'status', statusCode)
                .having((value) => value.error.code.wire, 'code', code),
          ),
        );
      }
    },
  );

  test('malformed response matrix는 protocol failure로 fail closed한다', () async {
    final malformedSession = Map<String, Object?>.of(_sessionJson())
      ..['unexpected'] = true;
    final malformedSessionRepository = JourneyApiRepository(
      _StubApiClient([
        ApiResponse(statusCode: 200, jsonBody: malformedSession),
      ]),
    );
    final mismatch = JourneyApiRepository(
      _StubApiClient([
        ApiResponse(
          statusCode: 200,
          jsonBody: _successJson(requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAW'),
        ),
      ]),
    );
    final duplicate = JourneyApiRepository(
      _StubApiClient([
        ApiResponse(
          statusCode: 200,
          jsonBody: _successJson(journeyIds: ['journey-1', 'journey-1']),
        ),
      ]),
    );
    final invalidPair = JourneyApiRepository(
      _StubApiClient([
        ApiResponse(
          statusCode: 400,
          jsonBody: _errorJson('ROUTE_SESSION_REQUIRED'),
        ),
      ]),
    );

    final nonObject = JourneyApiRepository(
      _StubApiClient([const ApiResponse(statusCode: 200, jsonBody: null)]),
    );
    final extraSuccess = Map<String, Object?>.of(_successJson())
      ..['unexpected'] = true;
    final extraSuccessRepository = JourneyApiRepository(
      _StubApiClient([ApiResponse(statusCode: 200, jsonBody: extraSuccess)]),
    );
    final policy = Map<String, Object?>.of(_successJson());
    final policyBody = Map<String, Object?>.of(
      policy['requestPolicy']! as Map<String, Object?>,
    )..['walkingPace'] = 'FAST';
    policy['requestPolicy'] = policyBody;
    final policyMismatch = JourneyApiRepository(
      _StubApiClient([ApiResponse(statusCode: 200, jsonBody: policy)]),
    );
    final missingError = Map<String, Object?>.of(
      _errorJson('ROUTE_SERVICE_UNAVAILABLE'),
    )..remove('code');
    final extraError = Map<String, Object?>.of(
      _errorJson('ROUTE_SERVICE_UNAVAILABLE'),
    )..['unexpected'] = true;
    final errorBodies = <Object?>[
      null,
      _errorJson('UNKNOWN_ERROR_CODE'),
      missingError,
      extraError,
    ];
    final invalidSuccessBodies = <Map<String, Object?>>[
      Map<String, Object?>.of(_successJson())
        ..['contractVersion'] = 'UNKNOWN_CONTRACT',
      Map<String, Object?>.of(_successJson())..['serviceTimezone'] = 'UTC',
      Map<String, Object?>.of(_successJson())..['journeys'] = <Object?>[],
    ];
    final realtimeSource = Map<String, Object?>.of(_successJson());
    realtimeSource['sourceIdentity'] = Map<String, Object?>.of(
      realtimeSource['sourceIdentity']! as Map<String, Object?>,
    )..['realtimeSnapshotId'] = 'realtime-1';
    invalidSuccessBodies.add(realtimeSource);
    final unsupportedBody = Map<String, Object?>.of(_successJson());
    final journeys = List<Object?>.of(
      unsupportedBody['journeys']! as List<Object?>,
    );
    journeys[0] = Map<String, Object?>.of(journeys[0]! as Map<String, Object?>)
      ..['planSource'] = 'UNSUPPORTED';
    unsupportedBody['journeys'] = journeys;
    final unsupported = JourneyApiRepository(
      _StubApiClient([ApiResponse(statusCode: 200, jsonBody: unsupportedBody)]),
    );

    await expectLater(
      mismatch.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    await expectLater(
      malformedSessionRepository.issueSession(_sessionRequest),
      throwsA(
        isA<JourneyProtocolFailure>()
            .having(
              (value) => value.operation,
              'operation',
              JourneyOperation.issueJourneySession,
            )
            .having((value) => value.statusCode, 'status', 200),
      ),
    );
    await expectLater(
      duplicate.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    await expectLater(
      invalidPair.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    await expectLater(
      nonObject.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    await expectLater(
      extraSuccessRepository.searchJourneys(
        _searchRequest,
        sessionToken: 'token',
      ),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    await expectLater(
      policyMismatch.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    for (final body in errorBodies) {
      final client = _StubApiClient([
        ApiResponse(statusCode: 503, jsonBody: body),
      ]);
      final repository = JourneyApiRepository(client);
      await expectLater(
        repository.searchJourneys(_searchRequest, sessionToken: 'token'),
        throwsA(isA<JourneyProtocolFailure>()),
      );
      expect(client.posts, hasLength(1));
    }
    for (final body in invalidSuccessBodies) {
      final client = _StubApiClient([
        ApiResponse(statusCode: 200, jsonBody: body),
      ]);
      final repository = JourneyApiRepository(client);
      await expectLater(
        repository.searchJourneys(_searchRequest, sessionToken: 'token'),
        throwsA(isA<JourneyProtocolFailure>()),
      );
      expect(client.posts, hasLength(1));
    }
    await expectLater(
      unsupported.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyProtocolFailure>()),
    );
  });

  test('transport는 한 번만 시도하고 retry·session refresh 없이 fail closed한다', () async {
    final blankTokenClient = _StubApiClient([
      ApiResponse(statusCode: 200, jsonBody: _successJson()),
    ]);
    final blankToken = JourneyApiRepository(blankTokenClient);
    final client = _StubApiClient(
      const [],
      error: const ApiException('timeout', path: '/api/v3/journeys/search'),
    );
    final repository = JourneyApiRepository(client);
    final statusClient = _StubApiClient(
      const [],
      error: const ApiException(
        'upstream rejected',
        statusCode: 503,
        path: '/api/v3/journeys/search',
      ),
    );
    final statusRepository = JourneyApiRepository(statusClient);
    final unexpectedClient = _StubApiClient(
      const [],
      error: StateError('unexpected transport failure'),
    );
    final unexpectedRepository = JourneyApiRepository(unexpectedClient);

    await expectLater(
      repository.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(isA<JourneyTransportFailure>()),
    );
    expect(client.posts, hasLength(1));
    await expectLater(
      statusRepository.searchJourneys(_searchRequest, sessionToken: 'token'),
      throwsA(
        isA<JourneyProtocolFailure>().having(
          (value) => value.statusCode,
          'status',
          503,
        ),
      ),
    );
    expect(statusClient.posts, hasLength(1));
    await expectLater(
      unexpectedRepository.searchJourneys(
        _searchRequest,
        sessionToken: 'token',
      ),
      throwsA(isA<JourneyTransportFailure>()),
    );
    expect(unexpectedClient.posts, hasLength(1));
    await expectLater(
      blankToken.searchJourneys(_searchRequest, sessionToken: '   '),
      throwsA(isA<JourneyProtocolFailure>()),
    );
    expect(blankTokenClient.posts, isEmpty);
  });
}
