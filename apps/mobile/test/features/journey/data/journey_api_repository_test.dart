import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/journey/data/journey_api_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_enums.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _requestId = '01K1Y000000000000000000000';
const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test(
    'session/search는 exact V3 request를 각 1회 보내고 direct success를 보존한다',
    () async {
      final api = _RecordingApiClient([
        ApiResponse(statusCode: 200, jsonBody: _sessionSuccess()),
        ApiResponse(
          statusCode: 200,
          jsonBody: _searchSuccess(
            journeyIds: const ['journey-b', 'journey-a'],
          ),
        ),
      ]);
      final repository = JourneyApiRepository(api);
      final sessionRequest = JourneySessionRequest(
        integrityToken: 'integrity-token',
        clientNonce: 'A234567890123456789012',
      );
      final searchRequest = _searchRequest();

      final session = await repository.issueSession(sessionRequest);
      final result = await repository.searchJourneys(
        searchRequest,
        sessionToken: session.token,
      );

      expect(session.token, 'session-token');
      expect(result.requestId, searchRequest.requestId);
      expect(result.journeys.map((journey) => journey.journeyId), [
        'journey-b',
        'journey-a',
      ]);
      expect(result.sourceIdentity.routeBundleId, 'bundle-7');
      expect(result.sourceIdentity.routeBundleSha256, _shaA);
      expect(api.calls, hasLength(2));
      expect(api.calls[0].path, '/api/v3/journeys/session');
      expect(api.calls[0].body, sessionRequest.toJson());
      expect(api.calls[0].headers, isEmpty);
      expect(api.calls[1].path, '/api/v3/journeys/search');
      expect(api.calls[1].body, searchRequest.toJson());
      expect(api.calls[1].headers, {'Authorization': 'Bearer session-token'});
    },
  );

  test(
    'generated session/search status-code table을 typed rejection으로 보존한다',
    () async {
      for (final row in _errorRows) {
        final api = _RecordingApiClient([
          ApiResponse(
            statusCode: row.httpStatus,
            jsonBody: _errorBody(row.code.wire),
          ),
        ]);
        final repository = JourneyApiRepository(api);
        final invocation = row.operation == JourneyOperation.issueJourneySession
            ? () => repository.issueSession(
                JourneySessionRequest(
                  integrityToken: 'integrity-token',
                  clientNonce: 'A234567890123456789012',
                ),
              )
            : () => repository.searchJourneys(
                _searchRequest(),
                sessionToken: 'session-token',
              );

        await expectLater(
          invocation,
          throwsA(
            isA<JourneyRejectedFailure>()
                .having(
                  (failure) => failure.operation,
                  'operation',
                  row.operation,
                )
                .having(
                  (failure) => failure.httpStatus,
                  'status',
                  row.httpStatus,
                )
                .having((failure) => failure.error.code, 'code', row.code)
                .having(
                  (failure) => failure.disposition.code,
                  'disposition code',
                  row.code,
                ),
          ),
        );
        expect(api.calls, hasLength(1));
      }
    },
  );

  test('401 rejection은 session refresh나 search retry를 만들지 않는다', () async {
    final api = _RecordingApiClient([
      ApiResponse(
        statusCode: 401,
        jsonBody: _errorBody('ROUTE_SESSION_REQUIRED'),
      ),
      ApiResponse(statusCode: 200, jsonBody: _sessionSuccess()),
    ]);

    await expectLater(
      () => JourneyApiRepository(
        api,
      ).searchJourneys(_searchRequest(), sessionToken: 'expired-token'),
      throwsA(isA<JourneyRejectedFailure>()),
    );

    expect(api.calls, hasLength(1));
    expect(api.calls.single.path, '/api/v3/journeys/search');
  });

  test(
    'transport failure는 typed failure이며 alternate request를 만들지 않는다',
    () async {
      final api = _RecordingApiClient(
        const [],
        error: const ApiException(
          'network unavailable',
          path: '/api/v3/journeys/search',
        ),
      );

      await expectLater(
        () => JourneyApiRepository(
          api,
        ).searchJourneys(_searchRequest(), sessionToken: 'session-token'),
        throwsA(
          isA<JourneyTransportFailure>().having(
            (failure) => failure.cause,
            'cause',
            isA<ApiException>().having(
              (exception) => exception.path,
              'path',
              '/api/v3/journeys/search',
            ),
          ),
        ),
      );

      expect(api.calls, hasLength(1));
    },
  );

  test(
    'cross-operation/status/code와 malformed error body는 protocol failure다',
    () async {
      final invalidResponses = <ApiResponse>[
        ApiResponse(
          statusCode: 403,
          jsonBody: _errorBody('ROUTE_SESSION_ATTESTATION_REJECTED'),
        ),
        ApiResponse(statusCode: 503, jsonBody: _errorBody('UNKNOWN_CODE')),
        ApiResponse(
          statusCode: 503,
          jsonBody: {..._errorBody('ROUTE_SERVICE_UNAVAILABLE'), 'extra': true},
        ),
        const ApiResponse(statusCode: 503, jsonBody: null),
        const ApiResponse(statusCode: 503, jsonBody: <Object?>[]),
      ];

      for (final response in invalidResponses) {
        final api = _RecordingApiClient([response]);
        await expectLater(
          () => JourneyApiRepository(
            api,
          ).searchJourneys(_searchRequest(), sessionToken: 'session-token'),
          throwsA(isA<JourneyProtocolFailure>()),
        );
        expect(api.calls, hasLength(1));
      }
    },
  );

  test(
    'mismatched request/policy와 duplicate journey identity는 success가 아니다',
    () async {
      final mismatchedRequest = _searchSuccess()
        ..['requestId'] = '01K1Y000000000000000000001';
      final mismatchedPolicy = _searchSuccess();
      (mismatchedPolicy['requestPolicy']
              as Map<String, Object?>)['alternativeCount'] =
          3;
      final duplicateJourneys = _searchSuccess(
        journeyIds: const ['duplicate', 'duplicate'],
      );
      final tooManyAlternatives = _searchSuccess(
        journeyIds: const ['journey-1', 'journey-2', 'journey-3'],
      );

      for (final body in [
        mismatchedRequest,
        mismatchedPolicy,
        duplicateJourneys,
        tooManyAlternatives,
      ]) {
        final api = _RecordingApiClient([
          ApiResponse(statusCode: 200, jsonBody: body),
        ]);
        await expectLater(
          () => JourneyApiRepository(
            api,
          ).searchJourneys(_searchRequest(), sessionToken: 'session-token'),
          throwsA(isA<JourneyProtocolFailure>()),
        );
        expect(api.calls, hasLength(1));
      }
    },
  );

  test(
    'invalid contract/timezone/realtime/source/cardinality body는 success가 아니다',
    () async {
      final invalidContract = _searchSuccess()
        ..['contractVersion'] = 'JOURNEY_SEARCH_V2';
      final invalidTimezone = _searchSuccess()..['serviceTimezone'] = 'UTC';
      final invalidRealtime = _searchSuccess();
      (invalidRealtime['sourceIdentity']
              as Map<String, Object?>)['realtimeSnapshotId'] =
          'unexpected';
      final invalidSource = _searchSuccess();
      (invalidSource['sourceIdentity']
              as Map<String, Object?>)['routeBundleSha256'] =
          'not-a-sha';
      final empty = _searchSuccess()..['journeys'] = <Object?>[];

      for (final body in [
        invalidContract,
        invalidTimezone,
        invalidRealtime,
        invalidSource,
        empty,
      ]) {
        final api = _RecordingApiClient([
          ApiResponse(statusCode: 200, jsonBody: body),
        ]);
        await expectLater(
          () => JourneyApiRepository(
            api,
          ).searchJourneys(_searchRequest(), sessionToken: 'session-token'),
          throwsA(isA<JourneyProtocolFailure>()),
        );
      }
    },
  );

  test(
    'missing/non-object success와 invalid session lifetime/token은 protocol failure다',
    () async {
      for (final response in const [
        ApiResponse(statusCode: 200, jsonBody: null),
        ApiResponse(statusCode: 200, jsonBody: <Object?>[]),
      ]) {
        await expectLater(
          () => JourneyApiRepository(_RecordingApiClient([response]))
              .issueSession(
                JourneySessionRequest(
                  integrityToken: 'integrity-token',
                  clientNonce: 'A234567890123456789012',
                ),
              ),
          throwsA(isA<JourneyProtocolFailure>()),
        );
      }

      final invalidLifetime = _sessionSuccess()
        ..['expiresAt'] = '2026-08-11T08:59:59+09:00';
      await expectLater(
        () =>
            JourneyApiRepository(
              _RecordingApiClient([
                ApiResponse(statusCode: 200, jsonBody: invalidLifetime),
              ]),
            ).issueSession(
              JourneySessionRequest(
                integrityToken: 'integrity-token',
                clientNonce: 'A234567890123456789012',
              ),
            ),
        throwsA(isA<JourneyProtocolFailure>()),
      );

      final api = _RecordingApiClient([
        ApiResponse(statusCode: 200, jsonBody: _searchSuccess()),
      ]);
      await expectLater(
        () => JourneyApiRepository(
          api,
        ).searchJourneys(_searchRequest(), sessionToken: 'bad\r\ntoken'),
        throwsA(isA<JourneyProtocolFailure>()),
      );
      expect(api.calls, isEmpty);
    },
  );
}

final class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(this.responses, {this.error})
    : super(baseUri: Uri.parse('https://example.test'));

  final List<ApiResponse> responses;
  final ApiException? error;
  final List<_PostCall> calls = [];

  @override
  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    calls.add(_PostCall(path, body, headers));
    if (error case final error?) throw error;
    return responses.removeAt(0);
  }
}

final class _PostCall {
  const _PostCall(this.path, this.body, this.headers);

  final String path;
  final Map<String, Object?> body;
  final Map<String, String> headers;
}

JourneySearchRequest _searchRequest() => JourneySearchRequest(
  requestId: _requestId,
  originStationId: 'station-origin',
  destinationStationId: 'station-destination',
  departure: const JourneyDepartureNow(),
  timePolicy: TimePolicy.timetableRequired,
  mobilityProfile: MobilityProfile.stepFree,
  constraintMode: ConstraintMode.requireStepFree,
  maxTransfers: 2,
  alternativeCount: 2,
);

Map<String, Object?> _sessionSuccess() => {
  'token': 'session-token',
  'scope': 'journey:v3',
  'issuedAt': '2026-08-11T09:00:00+09:00',
  'expiresAt': '2026-08-11T09:05:00+09:00',
};

Map<String, Object?> _searchSuccess({
  List<String> journeyIds = const ['journey-1'],
}) => {
  'contractVersion': 'JOURNEY_SEARCH_V3',
  'requestId': _requestId,
  'queryId': 'query-7',
  'calculatedAt': '2026-08-11T09:00:00+09:00',
  'validUntil': '2026-08-11T09:05:00+09:00',
  'effectiveDepartureTime': '2026-08-11T09:00:00+09:00',
  'serviceDate': '2026-08-11',
  'serviceTimezone': 'Asia/Seoul',
  'sourceIdentity': <String, Object?>{
    'routeBundleId': 'bundle-7',
    'routeBundleSha256': _shaA,
    'timetableSnapshotId': 'timetable-7',
    'accessibilitySnapshotId': 'accessibility-7',
    'realtimeSnapshotId': null,
  },
  'requestPolicy': <String, Object?>{
    'timePolicy': 'TIMETABLE_REQUIRED',
    'mobilityProfile': 'STEP_FREE',
    'constraintMode': 'REQUIRE_STEP_FREE',
    'maxTransfers': 2,
    'alternativeCount': 2,
  },
  'journeys': journeyIds.map(_journey).toList(growable: false),
};

Map<String, Object?> _journey(String journeyId) => {
  'journeyId': journeyId,
  'status': 'FOUND',
  'planSource': 'SERVER_TIMETABLE_RAPTOR',
  'plannedDepartureTime': '2026-08-11T09:01:00+09:00',
  'plannedArrivalTime': '2026-08-11T09:10:00+09:00',
  'realtimeDepartureTime': null,
  'realtimeArrivalTime': null,
  'durationSeconds': 540,
  'transferCount': 1,
  'walkingDistanceMeters': 250,
  'timeSource': 'TIMETABLE',
  'accessibility': <String, Object?>{
    'result': 'VERIFIED',
    'stairFree': true,
    'reasonCodes': <Object?>['STEP_FREE_VERIFIED'],
  },
  'legs': <Object?>[
    <String, Object?>{
      'type': 'ENTRY',
      'fromStationId': 'station-origin',
      'durationSeconds': 60,
    },
    <String, Object?>{
      'type': 'EXIT',
      'fromStationId': 'station-destination',
      'durationSeconds': 60,
    },
  ],
};

Map<String, Object?> _errorBody(String code) => {
  'contractVersion': 'JOURNEY_ERROR_V1',
  'requestId': _requestId,
  'code': code,
  'retryable': false,
  'occurredAt': '2026-08-11T09:00:00+09:00',
};

const _errorRows = <_ErrorRow>[
  _ErrorRow(
    JourneyOperation.searchJourneys,
    400,
    JourneyErrorCode.invalidJourneyRequest,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    404,
    JourneyErrorCode.stationNotFound,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    422,
    JourneyErrorCode.routeNotFound,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    422,
    JourneyErrorCode.accessibilityConstraintUnsatisfied,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.routingBundleUnavailable,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.routingBundleStale,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.timetableUnavailable,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.timetableStale,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.realtimeRequiredUnavailable,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.routingIdentityMismatch,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    503,
    JourneyErrorCode.routeServiceUnavailable,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    504,
    JourneyErrorCode.journeySearchTimeout,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    401,
    JourneyErrorCode.routeSessionRequired,
  ),
  _ErrorRow(
    JourneyOperation.searchJourneys,
    429,
    JourneyErrorCode.routeRateLimited,
  ),
  _ErrorRow(
    JourneyOperation.issueJourneySession,
    400,
    JourneyErrorCode.invalidJourneySessionRequest,
  ),
  _ErrorRow(
    JourneyOperation.issueJourneySession,
    403,
    JourneyErrorCode.routeSessionAttestationRejected,
  ),
  _ErrorRow(
    JourneyOperation.issueJourneySession,
    503,
    JourneyErrorCode.routeSessionAttestationUnavailable,
  ),
];

final class _ErrorRow {
  const _ErrorRow(this.operation, this.httpStatus, this.code);

  final JourneyOperation operation;
  final int httpStatus;
  final JourneyErrorCode code;
}
