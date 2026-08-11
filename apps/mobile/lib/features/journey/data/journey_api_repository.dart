import '../../../core/network/api_client.dart';
import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../domain/journey_repository.dart';

class JourneyApiRepository implements JourneyRepository {
  JourneyApiRepository(this._apiClient);

  static const _sessionPath = '/api/v3/journeys/session';
  static const _searchPath = '/api/v3/journeys/search';

  final ApiClient _apiClient;

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    final response = await _post(
      JourneyOperation.issueJourneySession,
      _sessionPath,
      request.toJson(),
    );
    final body = _successBody(JourneyOperation.issueJourneySession, response);
    try {
      return JourneySessionResponse.fromJson(body);
    } on FormatException catch (error) {
      throw JourneyProtocolFailure(
        JourneyOperation.issueJourneySession,
        cause: error,
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    if (sessionToken.trim().isEmpty) {
      throw JourneyProtocolFailure(
        JourneyOperation.searchJourneys,
        cause: const FormatException('Journey session token must be nonblank'),
      );
    }
    final response = await _post(
      JourneyOperation.searchJourneys,
      _searchPath,
      request.toJson(),
      headers: {'Authorization': 'Bearer $sessionToken'},
      expectedRequestId: request.requestId,
    );
    final body = _successBody(JourneyOperation.searchJourneys, response);
    try {
      final success = JourneySearchSuccess.fromJson(body);
      _validateSearchSuccess(success, request);
      return success;
    } on FormatException catch (error) {
      throw JourneyProtocolFailure(
        JourneyOperation.searchJourneys,
        cause: error,
        statusCode: response.statusCode,
      );
    }
  }

  Future<ApiResponse> _post(
    JourneyOperation operation,
    String path,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    String? expectedRequestId,
  }) async {
    final ApiResponse response;
    try {
      response = await _apiClient.postJson(path, body: body, headers: headers);
    } on ApiException catch (error) {
      if (error.statusCode != null) {
        throw JourneyProtocolFailure(
          operation,
          cause: error,
          statusCode: error.statusCode,
        );
      }
      throw JourneyTransportFailure(operation, error);
    } catch (error) {
      throw JourneyTransportFailure(operation, error);
    }

    if (response.statusCode == 200) return response;

    final bodyObject = response.jsonBody;
    if (bodyObject is! Map<String, Object?>) {
      throw JourneyProtocolFailure(
        operation,
        cause: const FormatException('Journey error body must be an object'),
        statusCode: response.statusCode,
      );
    }
    try {
      final error = JourneyV3Error.fromResponse(
        operation,
        response.statusCode,
        bodyObject,
      );
      if (expectedRequestId != null && error.requestId != expectedRequestId) {
        throw const FormatException('Journey error requestId mismatch');
      }
      final disposition = JourneyErrorDispositions.lookup(
        operation,
        response.statusCode,
        error.code,
      );
      throw JourneyRejectedFailure(
        operation,
        statusCode: response.statusCode,
        error: error,
        disposition: disposition,
      );
    } on JourneyRejectedFailure {
      rethrow;
    } on FormatException catch (error) {
      throw JourneyProtocolFailure(
        operation,
        cause: error,
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, Object?> _successBody(
    JourneyOperation operation,
    ApiResponse response,
  ) {
    if (response.jsonBody case final Map<String, Object?> body) return body;
    throw JourneyProtocolFailure(
      operation,
      cause: const FormatException('Journey success body must be an object'),
      statusCode: response.statusCode,
    );
  }

  void _validateSearchSuccess(
    JourneySearchSuccess success,
    JourneySearchRequest request,
  ) {
    if (success.requestId != request.requestId) {
      throw const FormatException('Journey success requestId mismatch');
    }
    final policy = success.requestPolicy;
    if (policy.timePolicy != request.timePolicy ||
        policy.mobilityProfile != request.mobilityProfile ||
        policy.constraintMode != request.constraintMode ||
        policy.maxTransfers != request.maxTransfers ||
        policy.alternativeCount != request.alternativeCount) {
      throw const FormatException('Journey success request policy mismatch');
    }
    final journeyIds = <String>{};
    for (final journey in success.journeys) {
      if (journey.planSource != JourneyPlanSource.serverTimetableRaptor ||
          !journeyIds.add(journey.journeyId)) {
        throw const FormatException(
          'Journey success identity or source mismatch',
        );
      }
    }
  }
}
