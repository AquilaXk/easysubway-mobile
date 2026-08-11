import '../../../core/network/api_client.dart';
import '../../../generated/journey_v3/journey_v3_enums.dart';
import '../../../generated/journey_v3/journey_v3_error.dart';
import '../../../generated/journey_v3/journey_v3_models.dart';
import '../domain/journey_repository.dart';

final class JourneyApiRepository implements JourneyRepository {
  JourneyApiRepository(this._apiClient);

  static const _sessionPath = '/api/v3/journeys/session';
  static const _searchPath = '/api/v3/journeys/search';

  final ApiClient _apiClient;

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    final response = await _post(_sessionPath, body: request.toJson());
    if (response.statusCode != 200) {
      throw _rejection(JourneyOperation.issueJourneySession, response);
    }

    final session = _decode(response, JourneySessionResponse.fromJson);
    if (!session.expiresAt.isAfter(session.issuedAt)) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.invalidSessionLifetime,
      );
    }
    return session;
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    if (sessionToken.isEmpty ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(sessionToken)) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.invalidSessionToken,
      );
    }
    final response = await _post(
      _searchPath,
      body: request.toJson(),
      headers: {'Authorization': 'Bearer $sessionToken'},
    );
    if (response.statusCode != 200) {
      final rejection = _rejection(JourneyOperation.searchJourneys, response);
      if (rejection.error.requestId != request.requestId) {
        throw const JourneyProtocolFailure(
          JourneyProtocolFailureReason.responseRequestMismatch,
        );
      }
      throw rejection;
    }

    final result = _decode(response, JourneySearchSuccess.fromJson);
    _validateSearchResult(request, result);
    return result;
  }

  Future<ApiResponse> _post(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    try {
      return await _apiClient.postJson(path, body: body, headers: headers);
    } on ApiException catch (error, stackTrace) {
      throw JourneyTransportFailure(error, stackTrace);
    }
  }

  T _decode<T>(ApiResponse response, T Function(Map<String, Object?>) decoder) {
    final body = _objectBody(response);
    try {
      return decoder(body);
    } on FormatException catch (error, stackTrace) {
      throw JourneyProtocolFailure(
        JourneyProtocolFailureReason.generatedPayloadInvalid,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  JourneyRejectedFailure _rejection(
    JourneyOperation operation,
    ApiResponse response,
  ) {
    final body = _objectBody(response);
    try {
      final error = JourneyV3Error.fromResponse(
        operation,
        response.statusCode,
        body,
      );
      final disposition = JourneyErrorDispositions.lookup(
        operation,
        response.statusCode,
        error.code,
      );
      return JourneyRejectedFailure(
        operation: operation,
        httpStatus: response.statusCode,
        error: error,
        disposition: disposition,
      );
    } on FormatException catch (error, stackTrace) {
      throw JourneyProtocolFailure(
        JourneyProtocolFailureReason.generatedPayloadInvalid,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Map<String, Object?> _objectBody(ApiResponse response) {
    final body = response.jsonBody;
    if (body is! Map<String, Object?>) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.responseBodyNotObject,
      );
    }
    return body;
  }

  void _validateSearchResult(
    JourneySearchRequest request,
    JourneySearchSuccess result,
  ) {
    if (result.requestId != request.requestId) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.responseRequestMismatch,
      );
    }
    final policy = result.requestPolicy;
    if (policy.timePolicy != request.timePolicy ||
        policy.mobilityProfile != request.mobilityProfile ||
        policy.constraintMode != request.constraintMode ||
        policy.maxTransfers != request.maxTransfers ||
        policy.alternativeCount != request.alternativeCount) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.responsePolicyMismatch,
      );
    }
    if (result.journeys.length > request.alternativeCount ||
        result.journeys.any(
          (journey) => journey.transferCount > request.maxTransfers,
        )) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.responseCardinalityMismatch,
      );
    }
    final journeyIds = result.journeys
        .map((journey) => journey.journeyId)
        .toSet();
    if (journeyIds.length != result.journeys.length) {
      throw const JourneyProtocolFailure(
        JourneyProtocolFailureReason.duplicateJourneyIdentity,
      );
    }
  }
}
