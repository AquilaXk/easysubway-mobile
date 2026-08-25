import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../journey_session_provider.dart';
import '../domain/journey_repository.dart';

export '../journey_session_provider.dart'
    show JourneySessionProvider, JourneyV3IntegrityAttestor;

typedef JourneyExpiryTimerFactory =
    Timer Function(Duration duration, void Function() callback);

typedef JourneyNonFatalErrorReporter =
    FutureOr<void> Function(Object error, StackTrace stackTrace);

enum JourneySearchStatus { idle, searching, success, failure }

enum JourneySearchFailure {
  sessionUnavailable,
  sessionRejected,
  sessionExpired,
  requestRejected,
  unavailable,
  protocol,
}

@immutable
class JourneySelectedSnapshot {
  JourneySelectedSnapshot.fromResponse(
    JourneySearchSuccess response,
    Journey selected,
  ) : contractVersion = response.contractVersion,
      requestId = response.requestId,
      queryId = response.queryId,
      calculatedAt = response.calculatedAt,
      validUntil = response.validUntil,
      effectiveDepartureTime = response.effectiveDepartureTime,
      serviceDate = JourneyDate.parse(response.serviceDate.toString()),
      serviceTimezone = response.serviceTimezone,
      sourceIdentity = JourneySourceIdentity(
        routeBundleId: response.sourceIdentity.routeBundleId,
        routeBundleSha256: response.sourceIdentity.routeBundleSha256,
        timetableSnapshotId: response.sourceIdentity.timetableSnapshotId,
        accessibilitySnapshotId:
            response.sourceIdentity.accessibilitySnapshotId,
        realtimeSnapshotId: response.sourceIdentity.realtimeSnapshotId,
      ),
      requestPolicy = JourneyRequestPolicy(
        timePolicy: response.requestPolicy.timePolicy,
        walkingPace: response.requestPolicy.walkingPace,
        mobilityProfile: response.requestPolicy.mobilityProfile,
        constraintMode: response.requestPolicy.constraintMode,
        maxTransfers: response.requestPolicy.maxTransfers,
        alternativeCount: response.requestPolicy.alternativeCount,
      ),
      journey = Journey(
        journeyId: selected.journeyId,
        status: selected.status,
        planSource: selected.planSource,
        plannedDepartureTime: selected.plannedDepartureTime,
        plannedArrivalTime: selected.plannedArrivalTime,
        realtimeDepartureTime: selected.realtimeDepartureTime,
        realtimeArrivalTime: selected.realtimeArrivalTime,
        durationSeconds: selected.durationSeconds,
        transferCount: selected.transferCount,
        walkingDistanceMeters: selected.walkingDistanceMeters,
        timeSource: selected.timeSource,
        accessibility: JourneyAccessibility(
          result: selected.accessibility.result,
          stairFree: selected.accessibility.stairFree,
          reasonCodes: List<String>.unmodifiable(
            selected.accessibility.reasonCodes,
          ),
        ),
        legs: List<JourneyLeg>.unmodifiable(selected.legs),
      );

  final JourneyContractVersion contractVersion;
  final String requestId;
  final String queryId;
  final DateTime calculatedAt;
  final DateTime validUntil;
  final DateTime effectiveDepartureTime;
  final JourneyDate serviceDate;
  final String serviceTimezone;
  final JourneySourceIdentity sourceIdentity;
  final JourneyRequestPolicy requestPolicy;
  final Journey journey;
}

@immutable
class JourneySearchCommand {
  const JourneySearchCommand({
    required this.originStationId,
    required this.destinationStationId,
    required this.departure,
    required this.timePolicy,
    required this.walkingPace,
    required this.mobilityProfile,
    required this.constraintMode,
    required this.maxTransfers,
    required this.alternativeCount,
  });

  final String originStationId;
  final String destinationStationId;
  final JourneyDeparture departure;
  final TimePolicy timePolicy;
  final WalkingPace walkingPace;
  final MobilityProfile mobilityProfile;
  final ConstraintMode constraintMode;
  final int maxTransfers;
  final int alternativeCount;

  @override
  bool operator ==(Object other) =>
      other is JourneySearchCommand &&
      originStationId == other.originStationId &&
      destinationStationId == other.destinationStationId &&
      departure.toJson().toString() == other.departure.toJson().toString() &&
      timePolicy == other.timePolicy &&
      walkingPace == other.walkingPace &&
      mobilityProfile == other.mobilityProfile &&
      constraintMode == other.constraintMode &&
      maxTransfers == other.maxTransfers &&
      alternativeCount == other.alternativeCount;

  @override
  int get hashCode => Object.hash(
    originStationId,
    destinationStationId,
    departure.toJson().toString(),
    timePolicy,
    walkingPace,
    mobilityProfile,
    constraintMode,
    maxTransfers,
    alternativeCount,
  );
}

@immutable
class JourneySearchState {
  const JourneySearchState._({
    required this.status,
    this.response,
    this.failure,
    this.selectedSnapshot,
  });

  const JourneySearchState.idle() : this._(status: JourneySearchStatus.idle);

  const JourneySearchState.searching()
    : this._(status: JourneySearchStatus.searching);

  const JourneySearchState.success(
    JourneySearchSuccess response, {
    JourneySelectedSnapshot? selectedSnapshot,
  }) : this._(
         status: JourneySearchStatus.success,
         response: response,
         selectedSnapshot: selectedSnapshot,
       );

  const JourneySearchState.failure(JourneySearchFailure failure)
    : this._(status: JourneySearchStatus.failure, failure: failure);

  final JourneySearchStatus status;
  final JourneySearchSuccess? response;
  final JourneySearchFailure? failure;
  final JourneySelectedSnapshot? selectedSnapshot;

  String? get selectedJourneyId => selectedSnapshot?.journey.journeyId;
}

class JourneySearchController extends ChangeNotifier {
  JourneySearchController({
    required this.repository,
    required this.attestor,
    DateTime Function()? now,
    String Function()? requestIdGenerator,
    String Function(int entropyBytes)? nonceGenerator,
    JourneySessionProvider? sessionProvider,
    JourneyExpiryTimerFactory? expiryTimerFactory,
    JourneyNonFatalErrorReporter? reportNonFatalError,
  }) : _now = now ?? DateTime.now,
       _requestIdGenerator = requestIdGenerator ?? _secureUlid,
       _expiryTimerFactory = expiryTimerFactory ?? Timer.new,
       _reportNonFatalError = reportNonFatalError ?? _ignoreNonFatalError,
       _sessionProvider =
           sessionProvider ??
           JourneySessionProvider(
             repository: repository,
             attestor: attestor,
             now: now,
             nonceGenerator: nonceGenerator,
           ),
       _ownsSessionProvider = sessionProvider == null;

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final DateTime Function() _now;
  final String Function() _requestIdGenerator;
  final JourneyExpiryTimerFactory _expiryTimerFactory;
  final JourneyNonFatalErrorReporter _reportNonFatalError;
  final JourneySessionProvider _sessionProvider;
  final bool _ownsSessionProvider;

  JourneySearchState _state = const JourneySearchState.idle();
  Future<void>? _inFlight;
  JourneySearchCommand? _inFlightCommand;
  JourneySearchCommand? _lastAcceptedCommand;
  int _generation = 0;
  bool _disposed = false;
  Timer? _responseExpiryTimer;

  JourneySearchState get state => _state;

  Future<void> search(JourneySearchCommand command) {
    if (_disposed) return Future<void>.value();
    final current = _inFlight;
    if (current != null && _inFlightCommand == command) {
      return current;
    }
    final generation = ++_generation;
    _cancelResponseExpiry();
    _inFlightCommand = command;
    _lastAcceptedCommand = command;
    final task = _run(command, generation);
    _inFlight = task;
    _state = const JourneySearchState.searching();
    _safeNotify();
    return task;
  }

  Future<void> retry() {
    final command = _lastAcceptedCommand;
    if (_disposed || _inFlight != null || command == null) {
      return Future<void>.value();
    }
    return search(command);
  }

  bool revalidateFreshness() {
    final response = _state.response;
    if (_disposed ||
        _state.status != JourneySearchStatus.success ||
        response == null) {
      return false;
    }
    return _revalidateResponseFreshness(response, _generation);
  }

  bool selectJourney(String journeyId) {
    if (!revalidateFreshness()) return false;
    final response = _state.response;
    if (_inFlight != null ||
        response == null ||
        response.journeys
                .where((journey) => journey.journeyId == journeyId)
                .length !=
            1) {
      return false;
    }
    if (_state.selectedJourneyId == journeyId) return true;
    _state = JourneySearchState.success(
      response,
      selectedSnapshot: JourneySelectedSnapshot.fromResponse(
        response,
        response.journeys.singleWhere(
          (journey) => journey.journeyId == journeyId,
        ),
      ),
    );
    _safeNotify();
    return true;
  }

  void reset() {
    _generation++;
    _cancelResponseExpiry();
    _inFlight = null;
    _inFlightCommand = null;
    _lastAcceptedCommand = null;
    _invalidateOwnedSession();
    _state = const JourneySearchState.idle();
    _safeNotify();
  }

  Future<void> _run(JourneySearchCommand command, int generation) async {
    try {
      final session = await _sessionProvider.session();
      if (!_isCurrent(generation)) return;
      final request = JourneySearchRequest(
        requestId: _requestIdGenerator(),
        originStationId: command.originStationId,
        destinationStationId: command.destinationStationId,
        departure: command.departure,
        timePolicy: command.timePolicy,
        walkingPace: command.walkingPace,
        mobilityProfile: command.mobilityProfile,
        constraintMode: command.constraintMode,
        maxTransfers: command.maxTransfers,
        alternativeCount: command.alternativeCount,
      );
      final response = await repository.searchJourneys(
        request,
        sessionToken: session.token,
      );
      if (_isCurrent(generation)) {
        final observedAt = _now();
        if (!response.validUntil.isAfter(observedAt)) {
          throw const JourneyProtocolFailure(
            JourneyOperation.searchJourneys,
            cause: FormatException('Journey response is expired'),
          );
        }
        _state = JourneySearchState.success(response);
        _scheduleResponseExpiry(response, generation, observedAt);
        _safeNotify();
      }
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      if (_isSessionAuthenticationFailure(error)) {
        _sessionProvider.invalidate();
      }
      _state = JourneySearchState.failure(_safeFailure(error));
      _safeNotify();
      _reportNonFatalErrorFireAndContain(error, stackTrace);
    } finally {
      if (_isCurrent(generation)) {
        _inFlight = null;
        _inFlightCommand = null;
      }
    }
  }

  void _scheduleResponseExpiry(
    JourneySearchSuccess response,
    int generation,
    DateTime observedAt,
  ) {
    _cancelResponseExpiry();
    _responseExpiryTimer = _expiryTimerFactory(
      response.validUntil.difference(observedAt),
      () {
        if (!_isCurrent(generation) || !identical(_state.response, response)) {
          return;
        }
        _responseExpiryTimer = null;
        _revalidateResponseFreshness(response, generation);
      },
    );
  }

  bool _revalidateResponseFreshness(
    JourneySearchSuccess response,
    int generation,
  ) {
    if (!_isCurrent(generation) || !identical(_state.response, response)) {
      return false;
    }
    final observedAt = _now();
    if (response.validUntil.isAfter(observedAt)) {
      _scheduleResponseExpiry(response, generation, observedAt);
      return true;
    }
    _cancelResponseExpiry();
    _state = const JourneySearchState.failure(JourneySearchFailure.protocol);
    _safeNotify();
    return false;
  }

  void _cancelResponseExpiry() {
    _responseExpiryTimer?.cancel();
    _responseExpiryTimer = null;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isSessionAuthenticationFailure(Object error) =>
      error is JourneyRejectedFailure && error.statusCode == 401;

  void _reportNonFatalErrorFireAndContain(Object error, StackTrace stackTrace) {
    try {
      final reporting = _reportNonFatalError(error, stackTrace);
      if (reporting is Future<void>) {
        unawaited(_swallowReporterFailure(reporting));
      }
    } catch (_) {
      // Reporting must not change the typed Journey failure.
    }
  }

  Future<void> _swallowReporterFailure(Future<void> reporting) async {
    try {
      await reporting;
    } catch (_) {
      // Reporting must not change the typed Journey failure.
    }
  }

  JourneySearchFailure _safeFailure(Object error) {
    if (error is JourneySessionInvalid) {
      return JourneySearchFailure.sessionExpired;
    }
    if (error is JourneyRejectedFailure) {
      return error.operation == JourneyOperation.issueJourneySession
          ? JourneySearchFailure.sessionRejected
          : JourneySearchFailure.requestRejected;
    }
    if (error is JourneyProtocolFailure) return JourneySearchFailure.protocol;
    if (error is JourneyTransportFailure) {
      return error.operation == JourneyOperation.issueJourneySession
          ? JourneySearchFailure.sessionUnavailable
          : JourneySearchFailure.unavailable;
    }
    return JourneySearchFailure.sessionUnavailable;
  }

  static void _ignoreNonFatalError(Object error, StackTrace stackTrace) {}

  static String _secureUlid() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final random = Random.secure();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final chars = StringBuffer();
    var value = timestamp;
    final time = List<String>.filled(10, '0');
    for (var index = 9; index >= 0; index--) {
      time[index] = alphabet[value & 31];
      value >>= 5;
    }
    chars.writeAll(time);
    for (var index = 0; index < 16; index++) {
      chars.write(alphabet[random.nextInt(32)]);
    }
    return chars.toString();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _invalidateOwnedSession() {
    if (_ownsSessionProvider) {
      _sessionProvider.invalidate();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelResponseExpiry();
    _inFlight = null;
    _inFlightCommand = null;
    _lastAcceptedCommand = null;
    _invalidateOwnedSession();
    super.dispose();
  }
}
