import '../../../generated/journey_v3/journey_v3_enums.dart';
import '../../../generated/journey_v3/journey_v3_error.dart';
import '../../../generated/journey_v3/journey_v3_models.dart';

abstract interface class JourneyRepository {
  Future<JourneySessionResponse> issueSession(JourneySessionRequest request);

  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  });
}

sealed class JourneyRepositoryFailure implements Exception {
  const JourneyRepositoryFailure();
}

final class JourneyTransportFailure extends JourneyRepositoryFailure {
  const JourneyTransportFailure(this.cause, this.causeStackTrace);

  final Object cause;
  final StackTrace causeStackTrace;

  @override
  String toString() => 'JourneyTransportFailure';
}

final class JourneyProtocolFailure extends JourneyRepositoryFailure {
  const JourneyProtocolFailure(this.reason, {this.cause, this.causeStackTrace});

  final JourneyProtocolFailureReason reason;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  String toString() => 'JourneyProtocolFailure(${reason.name})';
}

final class JourneyRejectedFailure extends JourneyRepositoryFailure {
  const JourneyRejectedFailure({
    required this.operation,
    required this.httpStatus,
    required this.error,
    required this.disposition,
  });

  final JourneyOperation operation;
  final int httpStatus;
  final JourneyV3Error error;
  final JourneyErrorDisposition disposition;

  @override
  String toString() =>
      'JourneyRejectedFailure(${operation.wire}, $httpStatus, ${error.code.wire})';
}

enum JourneyProtocolFailureReason {
  responseBodyNotObject,
  generatedPayloadInvalid,
  responseRequestMismatch,
  responsePolicyMismatch,
  duplicateJourneyIdentity,
  responseCardinalityMismatch,
  invalidSessionLifetime,
  invalidSessionToken,
}
