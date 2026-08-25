import '../../../generated/journey_v3/journey_v3_contract.dart';

abstract interface class JourneyRepository {
  Future<JourneySessionResponse> issueSession(JourneySessionRequest request);

  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  });

  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  });
}

sealed class JourneyRepositoryFailure implements Exception {
  const JourneyRepositoryFailure(this.operation);

  final JourneyOperation operation;
}

final class JourneyTransportFailure extends JourneyRepositoryFailure {
  const JourneyTransportFailure(super.operation, this.cause);

  final Object cause;
}

final class JourneyProtocolFailure extends JourneyRepositoryFailure {
  const JourneyProtocolFailure(
    super.operation, {
    required this.cause,
    this.statusCode,
  });

  final Object cause;
  final int? statusCode;
}

final class JourneyRejectedFailure extends JourneyRepositoryFailure {
  const JourneyRejectedFailure(
    super.operation, {
    required this.statusCode,
    required this.error,
    required this.disposition,
  });

  final int statusCode;
  final JourneyV3Error error;
  final JourneyErrorDisposition disposition;
}
