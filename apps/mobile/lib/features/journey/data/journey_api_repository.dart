import '../../../core/network/api_client.dart';
import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../domain/journey_repository.dart';

class JourneyApiRepository implements JourneyRepository {
  JourneyApiRepository(this._apiClient, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _sessionPath = '/api/v3/journeys/session';
  static const _searchPath = '/api/v3/journeys/search';
  static const _stationTimetableSearchPath =
      '/api/v3/station-timetables/search';

  final ApiClient _apiClient;
  final DateTime Function() _now;

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

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) async {
    if (sessionToken.trim().isEmpty) {
      throw JourneyProtocolFailure(
        JourneyOperation.searchStationTimetables,
        cause: const FormatException('Journey session token must be nonblank'),
      );
    }
    final response = await _post(
      JourneyOperation.searchStationTimetables,
      _stationTimetableSearchPath,
      request.toJson(),
      headers: {'Authorization': 'Bearer $sessionToken'},
    );
    final body = _successBody(
      JourneyOperation.searchStationTimetables,
      response,
    );
    try {
      final success = StationTimetableSearchSuccess.fromJson(body);
      _validateStationTimetableSuccess(success, request);
      return success;
    } on FormatException catch (error) {
      throw JourneyProtocolFailure(
        JourneyOperation.searchStationTimetables,
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
        policy.walkingPace != request.walkingPace ||
        policy.mobilityProfile != request.mobilityProfile ||
        policy.constraintMode != request.constraintMode ||
        policy.maxTransfers != request.maxTransfers ||
        policy.alternativeCount != request.alternativeCount) {
      throw const FormatException('Journey success request policy mismatch');
    }
    if (!success.validUntil.isAfter(success.calculatedAt)) {
      throw const FormatException('Journey success validity window mismatch');
    }
    if (success.serviceDate.toString() !=
        _seoulServiceDate(success.effectiveDepartureTime)) {
      throw const FormatException('Journey success service date mismatch');
    }
    if (success.journeys.length > policy.alternativeCount) {
      throw const FormatException('Journey success candidate count mismatch');
    }
    final journeyIds = <String>{};
    for (final journey in success.journeys) {
      if (journey.planSource != JourneyPlanSource.serverTimetableRaptor ||
          !journeyIds.add(journey.journeyId)) {
        throw const FormatException(
          'Journey success identity or source mismatch',
        );
      }
      if (policy.constraintMode == ConstraintMode.requireStepFree &&
          (journey.accessibility.result !=
                  JourneyAccessibilityResult.verified ||
              !journey.accessibility.stairFree)) {
        throw const FormatException(
          'Journey success accessibility constraint mismatch',
        );
      }
      _validateJourneySemantics(journey);
    }
  }

  void _validateJourneySemantics(Journey journey) {
    _requireOrdered(
      journey.plannedDepartureTime,
      journey.plannedArrivalTime,
      'Journey candidate planned times',
    );
    if (journey.realtimeDepartureTime case final realtimeDeparture?) {
      _requireOrdered(
        realtimeDeparture,
        journey.realtimeArrivalTime!,
        'Journey candidate realtime times',
      );
    }
    if (journey.accessibility.reasonCodes.any(
      (reasonCode) => reasonCode.trim().isEmpty,
    )) {
      throw const FormatException(
        'Journey accessibility reason code must be nonblank',
      );
    }
    for (final leg in journey.legs) {
      if (leg is! JourneyRideLeg) continue;
      _requireOrdered(
        leg.plannedDepartureTime,
        leg.plannedArrivalTime,
        'Journey ride planned times',
      );
      if (leg.realtimeDepartureTime case final realtimeDeparture?) {
        _requireOrdered(
          realtimeDeparture,
          leg.realtimeArrivalTime!,
          'Journey ride realtime times',
        );
      }
    }
  }

  void _validateStationTimetableSuccess(
    StationTimetableSearchSuccess success,
    StationTimetableSearchRequest request,
  ) {
    if (success.stationId != request.stationId ||
        success.lineId != request.lineId ||
        success.selector.toJson().toString() !=
            request.selector.toJson().toString() ||
        success.serviceTimezone != StationTimetableServiceTimezone.asiaSeoul ||
        !success.sourceIdentity.freshUntil.isAfter(_now())) {
      throw const FormatException(
        'Station timetable identity or freshness mismatch',
      );
    }
    for (final group in success.directionGroups) {
      if (group.directionName.trim().isEmpty) {
        throw const FormatException(
          'Station timetable direction must be nonblank',
        );
      }
      DateTime? previous;
      for (final departure in group.departures) {
        if (previous != null && departure.departureAt.isBefore(previous)) {
          throw const FormatException(
            'Station timetable departures must be ordered',
          );
        }
        previous = departure.departureAt;
        if (!_serviceDayInstantUtc(
          departure.serviceDate.toString(),
          departure.secondsFromServiceDayStart,
        ).isAtSameMomentAs(departure.departureAt.toUtc())) {
          throw const FormatException(
            'Station timetable departure time mismatch',
          );
        }
      }
    }
  }

  DateTime _serviceDayInstantUtc(String serviceDate, int seconds) {
    final parts = serviceDate.split('-').map(int.parse).toList(growable: false);
    if (parts.length != 3 || seconds < 0 || seconds > 107999) {
      throw const FormatException('Station timetable service day is invalid');
    }
    return DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
    ).subtract(const Duration(hours: 9)).add(Duration(seconds: seconds));
  }

  void _requireOrdered(DateTime departure, DateTime arrival, String label) {
    if (departure.isAfter(arrival)) {
      throw FormatException('$label must be ordered');
    }
  }

  String _seoulServiceDate(DateTime instant) {
    final seoul = instant.toUtc().add(const Duration(hours: 9));
    return '${seoul.year.toString().padLeft(4, '0')}-'
        '${seoul.month.toString().padLeft(2, '0')}-'
        '${seoul.day.toString().padLeft(2, '0')}';
  }
}
