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
  clientNonce: 'aaaaaaaaaaaaaaaaaaaaaa',
);

final _searchRequest = JourneySearchRequest(
  requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
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
}) {
  final policy = JourneyRequestPolicy(
    timePolicy: _searchRequest.timePolicy,
    mobilityProfile: _searchRequest.mobilityProfile,
    constraintMode: _searchRequest.constraintMode,
    maxTransfers: _searchRequest.maxTransfers,
    alternativeCount: _searchRequest.alternativeCount,
  );
  final journeys = journeyIds
      .map(
        (id) => Journey(
          journeyId: id,
          status: JourneyStatus.found,
          planSource: JourneyPlanSource.serverTimetableRaptor,
          plannedDepartureTime: DateTime.parse('2026-08-11T00:00:00Z'),
          plannedArrivalTime: DateTime.parse('2026-08-11T00:05:00Z'),
          realtimeDepartureTime: null,
          realtimeArrivalTime: null,
          durationSeconds: 300,
          transferCount: 0,
          walkingDistanceMeters: 0,
          timeSource: JourneyTimeSource.timetable,
          accessibility: const JourneyAccessibility(
            result: JourneyAccessibilityResult.verified,
            stairFree: false,
            reasonCodes: [],
          ),
          legs: const [
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
    requestId: requestId ?? _searchRequest.requestId,
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
      realtimeSnapshotId: null,
    ),
    requestPolicy: policy,
    journeys: journeys,
  ).toJson();
}

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
    )..['maxTransfers'] = 1;
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
