import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../domain/journey_repository.dart';

abstract interface class JourneyV3IntegrityAttestor {
  Future<String> attest(String requestHash);
}

typedef JourneyExpiryTimerFactory =
    Timer Function(Duration duration, void Function() callback);

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
    JourneyExpiryTimerFactory? expiryTimerFactory,
  }) : _now = now ?? DateTime.now,
       _requestIdGenerator = requestIdGenerator ?? _secureUlid,
       _nonceGenerator = nonceGenerator ?? _secureNonce,
       _expiryTimerFactory = expiryTimerFactory ?? Timer.new,
       _sessionSpec = _JourneyV3SessionIntegritySpec.fromGeneratedArtifact();

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final DateTime Function() _now;
  final String Function() _requestIdGenerator;
  final String Function(int entropyBytes) _nonceGenerator;
  final JourneyExpiryTimerFactory _expiryTimerFactory;
  final _JourneyV3SessionIntegritySpec _sessionSpec;

  JourneySearchState _state = const JourneySearchState.idle();
  JourneySessionResponse? _session;
  Future<JourneySessionResponse>? _sessionInFlight;
  Object? _sessionInFlightToken;
  Future<void>? _inFlight;
  JourneySearchCommand? _inFlightCommand;
  JourneySearchCommand? _lastAcceptedCommand;
  int _generation = 0;
  int _sessionEpoch = 0;
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
    _sessionEpoch++;
    _inFlight = null;
    _inFlightCommand = null;
    _sessionInFlight = null;
    _sessionInFlightToken = null;
    _lastAcceptedCommand = null;
    _invalidateSession();
    _state = const JourneySearchState.idle();
    _safeNotify();
  }

  Future<void> _run(JourneySearchCommand command, int generation) async {
    try {
      final session = await _sessionForSearch();
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
    } catch (error) {
      if (_isCurrent(generation) && _isSessionAuthenticationFailure(error)) {
        _invalidateSession();
      }
      if (_isCurrent(generation)) {
        _state = JourneySearchState.failure(_safeFailure(error));
        _safeNotify();
      }
    } finally {
      if (_isCurrent(generation)) {
        _inFlight = null;
        _inFlightCommand = null;
      }
    }
  }

  Future<JourneySessionResponse> _sessionForSearch() {
    final cached = _session;
    if (cached != null && cached.expiresAt.isAfter(_now())) {
      return Future<JourneySessionResponse>.value(cached);
    }
    _invalidateSession();
    final inFlight = _sessionInFlight;
    if (inFlight != null) return inFlight;
    final token = Object();
    final issued = _issueSession(_sessionEpoch, token);
    _sessionInFlight = issued;
    _sessionInFlightToken = token;
    return issued;
  }

  Future<JourneySessionResponse> _issueSession(int epoch, Object token) async {
    try {
      final nonce = _nonceGenerator(_sessionSpec.nonceEntropyBytes);
      if (!_sessionSpec.noncePattern.hasMatch(nonce)) {
        throw const _InvalidSession();
      }
      final integrityToken = await attestor.attest(_requestHash(nonce));
      if (_disposed || epoch != _sessionEpoch) {
        throw const _SessionInvalidated();
      }
      final issued = await repository.issueSession(
        JourneySessionRequest(
          integrityToken: integrityToken,
          clientNonce: nonce,
        ),
      );
      final now = _now();
      if (_disposed || epoch != _sessionEpoch) {
        throw const _SessionInvalidated();
      }
      if (issued.scope.wire != _sessionSpec.scope ||
          !issued.expiresAt.isAfter(now) ||
          issued.expiresAt.isAfter(
            now.add(Duration(seconds: _sessionSpec.ttlSeconds)),
          )) {
        throw const _InvalidSession();
      }
      _session = issued;
      return issued;
    } catch (_) {
      if (!_disposed && epoch == _sessionEpoch) {
        _invalidateSession();
      }
      rethrow;
    } finally {
      if (identical(_sessionInFlightToken, token)) {
        _sessionInFlight = null;
        _sessionInFlightToken = null;
      }
    }
  }

  void _invalidateSession() {
    _session = null;
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

  JourneySearchFailure _safeFailure(Object error) {
    if (error is _InvalidSession) return JourneySearchFailure.sessionExpired;
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

  String _requestHash(String nonce) {
    final canonical = _sessionSpec.canonicalPayloadTemplate.replaceAll(
      '<clientNonce>',
      nonce,
    );
    final hash = base64Url
        .encode(sha256.convert(utf8.encode(canonical)).bytes)
        .replaceAll('=', '');
    if (!_sessionSpec.requestHashPattern.hasMatch(hash)) {
      throw const _InvalidSession();
    }
    return hash;
  }

  static String _secureNonce(int entropyBytes) {
    final random = Random.secure();
    final bytes = List<int>.generate(entropyBytes, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

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

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelResponseExpiry();
    _sessionEpoch++;
    _inFlight = null;
    _inFlightCommand = null;
    _sessionInFlight = null;
    _sessionInFlightToken = null;
    _lastAcceptedCommand = null;
    _invalidateSession();
    super.dispose();
  }
}

class _InvalidSession implements Exception {
  const _InvalidSession();
}

class _SessionInvalidated implements Exception {
  const _SessionInvalidated();
}

class _JourneyV3SessionIntegritySpec {
  const _JourneyV3SessionIntegritySpec({
    required this.nonceEntropyBytes,
    required this.noncePattern,
    required this.requestHashPattern,
    required this.canonicalPayloadTemplate,
    required this.scope,
    required this.ttlSeconds,
  });

  final int nonceEntropyBytes;
  final RegExp noncePattern;
  final RegExp requestHashPattern;
  final String canonicalPayloadTemplate;
  final String scope;
  final int ttlSeconds;

  factory _JourneyV3SessionIntegritySpec.fromGeneratedArtifact() {
    try {
      final root = jsonDecode(journeyV3SessionIntegritySpecJson);
      if (root is! Map<String, Object?>) throw const FormatException();
      final nonce = root['nonce'];
      final requestHash = root['requestHash'];
      final session = root['session'];
      if (nonce is! Map<String, Object?> ||
          requestHash is! Map<String, Object?> ||
          session is! Map<String, Object?> ||
          root['schemaVersion'] != 'JOURNEY_V3_SESSION_INTEGRITY_V1' ||
          root['operationId'] != 'issueJourneySession' ||
          nonce['source'] != 'CSPRNG' ||
          nonce['encoding'] != 'BASE64URL_NO_PADDING' ||
          nonce['entropyBytes'] != 16 ||
          requestHash['algorithm'] != 'SHA-256' ||
          requestHash['encoding'] != 'BASE64URL_NO_PADDING' ||
          requestHash['purpose'] != 'journey:v3:session' ||
          requestHash['version'] != 1 ||
          session['scope'] != 'journey:v3' ||
          session['ttlSeconds'] != 600) {
        throw const FormatException();
      }
      final noncePattern = nonce['pattern'];
      final hashPattern = requestHash['pattern'];
      final template = requestHash['canonicalPayloadUtf8Template'];
      if (noncePattern is! String ||
          hashPattern is! String ||
          template is! String ||
          template !=
              '{"clientNonce":"<clientNonce>","purpose":"journey:v3:session","version":1}') {
        throw const FormatException();
      }
      return _JourneyV3SessionIntegritySpec(
        nonceEntropyBytes: nonce['entropyBytes']! as int,
        noncePattern: RegExp(noncePattern),
        requestHashPattern: RegExp(hashPattern),
        canonicalPayloadTemplate: template,
        scope: session['scope']! as String,
        ttlSeconds: session['ttlSeconds']! as int,
      );
    } catch (_) {
      throw const FormatException('Invalid generated Journey V3 session spec');
    }
  }
}
