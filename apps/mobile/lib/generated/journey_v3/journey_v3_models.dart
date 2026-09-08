// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated strict Journey V3 request models.
import 'journey_v3_enums.dart';
import 'journey_v3_validation.dart';

class JourneySessionRequest {
  final String integrityToken;
  final String clientNonce;
  const JourneySessionRequest._({required this.integrityToken, required this.clientNonce});
  factory JourneySessionRequest({required String integrityToken, required String clientNonce}) {
    if (integrityToken.isEmpty || integrityToken.length > 16384) throw const FormatException('integrityToken length');
    return JourneySessionRequest._(integrityToken: integrityToken, clientNonce: JourneyV3Validation.matching(clientNonce, 'clientNonce', RegExp(r'^[A-Za-z0-9_-]{21}[AQgw](?![\s\S])')));
  }
  factory JourneySessionRequest.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'integrityToken', 'clientNonce'});
    final integrityToken = JourneyV3Validation.string(json['integrityToken'], 'integrityToken');
    if (integrityToken.isEmpty || integrityToken.length > 16384) throw const FormatException('integrityToken length');
    return JourneySessionRequest(integrityToken: integrityToken, clientNonce: JourneyV3Validation.matching(json['clientNonce'], 'clientNonce', RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]$')));
  }
  Map<String, Object?> toJson() => {'integrityToken': integrityToken, 'clientNonce': clientNonce};
}

class JourneySessionResponse {
  final String token;
  final JourneySessionScope scope;
  final DateTime issuedAt;
  final DateTime expiresAt;
  const JourneySessionResponse({required this.token, required this.scope, required this.issuedAt, required this.expiresAt});
  factory JourneySessionResponse.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'token', 'scope', 'issuedAt', 'expiresAt'});
    return JourneySessionResponse(
      token: JourneyV3Validation.nonBlank(json['token'], 'token'),
      scope: JourneySessionScopeWire.fromWire(json['scope']),
      issuedAt: JourneyV3Validation.rfc3339(json['issuedAt'], 'issuedAt'),
      expiresAt: JourneyV3Validation.rfc3339(json['expiresAt'], 'expiresAt'),
    );
  }
  Map<String, Object?> toJson() => {'token': token, 'scope': scope.wire, 'issuedAt': JourneyV3Validation.rfc3339Wire(issuedAt), 'expiresAt': JourneyV3Validation.rfc3339Wire(expiresAt)};
}

sealed class JourneyDeparture {
  const JourneyDeparture();
  Map<String, Object?> toJson();
  static JourneyDeparture fromJson(Map<String, Object?> json) {
    final mode = JourneyDepartureModeWire.fromWire(json['mode']);
    return switch (mode) {
      JourneyDepartureMode.now => JourneyDepartureNow.fromJson(json),
      JourneyDepartureMode.scheduled => JourneyDepartureScheduled.fromJson(json),
    };
  }
}

class JourneyDepartureNow extends JourneyDeparture {
  const JourneyDepartureNow();
  factory JourneyDepartureNow.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'mode'});
    if (JourneyDepartureModeWire.fromWire(json['mode']) != JourneyDepartureMode.now) throw const FormatException('departure mode');
    return const JourneyDepartureNow();
  }
  @override
  Map<String, Object?> toJson() => {'mode': JourneyDepartureMode.now.wire};
}

class JourneyDepartureScheduled extends JourneyDeparture {
  final DateTime requestedAt;
  const JourneyDepartureScheduled(this.requestedAt);
  factory JourneyDepartureScheduled.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'mode', 'requestedAt'});
    if (JourneyDepartureModeWire.fromWire(json['mode']) != JourneyDepartureMode.scheduled) throw const FormatException('departure mode');
    return JourneyDepartureScheduled(JourneyV3Validation.rfc3339(json['requestedAt'], 'requestedAt'));
  }
  @override
  Map<String, Object?> toJson() => {'mode': JourneyDepartureMode.scheduled.wire, 'requestedAt': JourneyV3Validation.rfc3339Wire(requestedAt)};
}

class JourneySearchRequest {
  final String requestId;
  final String originStationId;
  final String destinationStationId;
  final JourneyDeparture departure;
  final TimePolicy timePolicy;
  final WalkingPace walkingPace;
  final MobilityProfile mobilityProfile;
  final ConstraintMode constraintMode;
  final int maxTransfers;
  final int alternativeCount;
  const JourneySearchRequest._({
    required this.requestId,
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
  factory JourneySearchRequest({
    required String requestId,
    required String originStationId,
    required String destinationStationId,
    required JourneyDeparture departure,
    required TimePolicy timePolicy,
    required WalkingPace walkingPace,
    required MobilityProfile mobilityProfile,
    required ConstraintMode constraintMode,
    required int maxTransfers,
    required int alternativeCount,
  }) {
    if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');
    return JourneySearchRequest._(
      requestId: JourneyV3Validation.ulid(requestId, 'requestId'),
      originStationId: JourneyV3Validation.nonBlank(originStationId, 'originStationId'),
      destinationStationId: JourneyV3Validation.nonBlank(destinationStationId, 'destinationStationId'),
      departure: departure,
      timePolicy: timePolicy,
      walkingPace: walkingPace,
      mobilityProfile: mobilityProfile,
      constraintMode: constraintMode,
      maxTransfers: JourneyV3Validation.integer(maxTransfers, 'maxTransfers', 0, 3),
      alternativeCount: JourneyV3Validation.integer(alternativeCount, 'alternativeCount', 1, 3),
    );
  }
  factory JourneySearchRequest.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'requestId',
      'originStationId',
      'destinationStationId',
      'departure',
      'timePolicy',
      'walkingPace',
      'mobilityProfile',
      'constraintMode',
      'maxTransfers',
      'alternativeCount',
    });
    final mobilityProfile = MobilityProfileWire.fromWire(json['mobilityProfile']);
    final constraintMode = ConstraintModeWire.fromWire(json['constraintMode']);
    if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');
    final departureValue = json['departure'];
    if (departureValue is! Map<String, Object?>) throw const FormatException('departure must be object');
    return JourneySearchRequest(
      requestId: JourneyV3Validation.ulid(json['requestId'], 'requestId'),
      originStationId: JourneyV3Validation.nonBlank(json['originStationId'], 'originStationId'),
      destinationStationId: JourneyV3Validation.nonBlank(json['destinationStationId'], 'destinationStationId'),
      departure: JourneyDeparture.fromJson(departureValue),
      timePolicy: TimePolicyWire.fromWire(json['timePolicy']),
      walkingPace: WalkingPaceWire.fromWire(json['walkingPace']),
      mobilityProfile: mobilityProfile,
      constraintMode: constraintMode,
      maxTransfers: JourneyV3Validation.integer(json['maxTransfers'], 'maxTransfers', 0, 3),
      alternativeCount: JourneyV3Validation.integer(json['alternativeCount'], 'alternativeCount', 1, 3),
    );
  }
  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'originStationId': originStationId,
    'destinationStationId': destinationStationId,
    'departure': departure.toJson(),
    'timePolicy': timePolicy.wire,
    'walkingPace': walkingPace.wire,
    'mobilityProfile': mobilityProfile.wire,
    'constraintMode': constraintMode.wire,
    'maxTransfers': maxTransfers,
    'alternativeCount': alternativeCount,
  };
}

sealed class JourneyLeg {
  const JourneyLeg();
  Map<String, Object?> toJson();
  static JourneyLeg fromJson(Map<String, Object?> json) {
    final type = JourneyLegTypeWire.fromWire(json['type']);
    return switch (type) {
      JourneyLegType.entry => JourneyEntryLeg.fromJson(json),
      JourneyLegType.ride => JourneyRideLeg.fromJson(json),
      JourneyLegType.transfer => JourneyTransferLeg.fromJson(json),
      JourneyLegType.exit => JourneyExitLeg.fromJson(json),
    };
  }
}

class JourneyEntryLeg extends JourneyLeg {
  final String fromStationId;
  final int durationSeconds;
  const JourneyEntryLeg({required this.fromStationId, required this.durationSeconds});
  factory JourneyEntryLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'durationSeconds'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.entry) throw const FormatException('leg type');
    return JourneyEntryLeg(
      fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'),
      durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0),
    );
  }
  @override
  Map<String, Object?> toJson() => {'type': JourneyLegType.entry.wire, 'fromStationId': fromStationId, 'durationSeconds': durationSeconds};
}

class JourneyRideLeg extends JourneyLeg {
  final String lineId;
  final String tripId;
  final String directionStationId;
  final String fromStationId;
  final String toStationId;
  final DateTime plannedDepartureTime;
  final DateTime plannedArrivalTime;
  final DateTime? realtimeDepartureTime;
  final DateTime? realtimeArrivalTime;
  const JourneyRideLeg({
    required this.lineId,
    required this.tripId,
    required this.directionStationId,
    required this.fromStationId,
    required this.toStationId,
    required this.plannedDepartureTime,
    required this.plannedArrivalTime,
    required this.realtimeDepartureTime,
    required this.realtimeArrivalTime,
  });
  factory JourneyRideLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'type',
      'lineId',
      'tripId',
      'directionStationId',
      'fromStationId',
      'toStationId',
      'plannedDepartureTime',
      'plannedArrivalTime',
      'realtimeDepartureTime',
      'realtimeArrivalTime',
    });
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.ride) throw const FormatException('leg type');
    return JourneyRideLeg(
      lineId: JourneyV3Validation.nonBlank(json['lineId'], 'lineId'),
      tripId: JourneyV3Validation.nonBlank(json['tripId'], 'tripId'),
      directionStationId: JourneyV3Validation.nonBlank(json['directionStationId'], 'directionStationId'),
      fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'),
      toStationId: JourneyV3Validation.nonBlank(json['toStationId'], 'toStationId'),
      plannedDepartureTime: JourneyV3Validation.rfc3339(json['plannedDepartureTime'], 'plannedDepartureTime'),
      plannedArrivalTime: JourneyV3Validation.rfc3339(json['plannedArrivalTime'], 'plannedArrivalTime'),
      realtimeDepartureTime: JourneyV3Validation.nullable(json, 'realtimeDepartureTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeDepartureTime')),
      realtimeArrivalTime: JourneyV3Validation.nullable(json, 'realtimeArrivalTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeArrivalTime')),
    );
  }
  @override
  Map<String, Object?> toJson() => {
    'type': JourneyLegType.ride.wire,
    'lineId': lineId,
    'tripId': tripId,
    'directionStationId': directionStationId,
    'fromStationId': fromStationId,
    'toStationId': toStationId,
    'plannedDepartureTime': JourneyV3Validation.rfc3339Wire(plannedDepartureTime),
    'plannedArrivalTime': JourneyV3Validation.rfc3339Wire(plannedArrivalTime),
    'realtimeDepartureTime': realtimeDepartureTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeDepartureTime!),
    'realtimeArrivalTime': realtimeArrivalTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeArrivalTime!),
  };
}

class JourneyTransferLeg extends JourneyLeg {
  final String fromStationId;
  final String toStationId;
  final int durationSeconds;
  const JourneyTransferLeg({required this.fromStationId, required this.toStationId, required this.durationSeconds});
  factory JourneyTransferLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'toStationId', 'durationSeconds'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.transfer) throw const FormatException('leg type');
    return JourneyTransferLeg(
      fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'),
      toStationId: JourneyV3Validation.nonBlank(json['toStationId'], 'toStationId'),
      durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0),
    );
  }
  @override
  Map<String, Object?> toJson() => {'type': JourneyLegType.transfer.wire, 'fromStationId': fromStationId, 'toStationId': toStationId, 'durationSeconds': durationSeconds};
}

class JourneyExitLeg extends JourneyLeg {
  final String fromStationId;
  final int durationSeconds;
  const JourneyExitLeg({required this.fromStationId, required this.durationSeconds});
  factory JourneyExitLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'durationSeconds'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.exit) throw const FormatException('leg type');
    return JourneyExitLeg(
      fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'),
      durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0),
    );
  }
  @override
  Map<String, Object?> toJson() => {'type': JourneyLegType.exit.wire, 'fromStationId': fromStationId, 'durationSeconds': durationSeconds};
}

class JourneySourceIdentity {
  final String routeBundleId;
  final String routeBundleSha256;
  final String timetableSnapshotId;
  final String accessibilitySnapshotId;
  final String? realtimeSnapshotId;
  const JourneySourceIdentity({
    required this.routeBundleId,
    required this.routeBundleSha256,
    required this.timetableSnapshotId,
    required this.accessibilitySnapshotId,
    required this.realtimeSnapshotId,
  });
  factory JourneySourceIdentity.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'routeBundleId', 'routeBundleSha256', 'timetableSnapshotId', 'accessibilitySnapshotId', 'realtimeSnapshotId'});
    return JourneySourceIdentity(
      routeBundleId: JourneyV3Validation.nonBlank(json['routeBundleId'], 'routeBundleId'),
      routeBundleSha256: JourneyV3Validation.sha256(json['routeBundleSha256'], 'routeBundleSha256'),
      timetableSnapshotId: JourneyV3Validation.nonBlank(json['timetableSnapshotId'], 'timetableSnapshotId'),
      accessibilitySnapshotId: JourneyV3Validation.nonBlank(json['accessibilitySnapshotId'], 'accessibilitySnapshotId'),
      realtimeSnapshotId: JourneyV3Validation.nullable(json, 'realtimeSnapshotId', (v) => JourneyV3Validation.nonBlank(v, 'realtimeSnapshotId')),
    );
  }
  Map<String, Object?> toJson() => {
    'routeBundleId': routeBundleId,
    'routeBundleSha256': routeBundleSha256,
    'timetableSnapshotId': timetableSnapshotId,
    'accessibilitySnapshotId': accessibilitySnapshotId,
    'realtimeSnapshotId': realtimeSnapshotId,
  };
}

class JourneyRequestPolicy {
  final TimePolicy timePolicy;
  final WalkingPace walkingPace;
  final MobilityProfile mobilityProfile;
  final ConstraintMode constraintMode;
  final int maxTransfers;
  final int alternativeCount;
  const JourneyRequestPolicy({
    required this.timePolicy,
    required this.walkingPace,
    required this.mobilityProfile,
    required this.constraintMode,
    required this.maxTransfers,
    required this.alternativeCount,
  });
  factory JourneyRequestPolicy.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'timePolicy', 'walkingPace', 'mobilityProfile', 'constraintMode', 'maxTransfers', 'alternativeCount'});
    final mobilityProfile = MobilityProfileWire.fromWire(json['mobilityProfile']);
    final constraintMode = ConstraintModeWire.fromWire(json['constraintMode']);
    if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');
    return JourneyRequestPolicy(
      timePolicy: TimePolicyWire.fromWire(json['timePolicy']),
      walkingPace: WalkingPaceWire.fromWire(json['walkingPace']),
      mobilityProfile: mobilityProfile,
      constraintMode: constraintMode,
      maxTransfers: JourneyV3Validation.integer(json['maxTransfers'], 'maxTransfers', 0, 3),
      alternativeCount: JourneyV3Validation.integer(json['alternativeCount'], 'alternativeCount', 1, 3),
    );
  }
  Map<String, Object?> toJson() => {
    'timePolicy': timePolicy.wire,
    'walkingPace': walkingPace.wire,
    'mobilityProfile': mobilityProfile.wire,
    'constraintMode': constraintMode.wire,
    'maxTransfers': maxTransfers,
    'alternativeCount': alternativeCount,
  };
}

class JourneyAccessibility {
  final JourneyAccessibilityResult result;
  final bool stairFree;
  final List<String> reasonCodes;
  const JourneyAccessibility({required this.result, required this.stairFree, required this.reasonCodes});
  factory JourneyAccessibility.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'result', 'stairFree', 'reasonCodes'});
    return JourneyAccessibility(
      result: JourneyAccessibilityResultWire.fromWire(json['result']),
      stairFree: JourneyV3Validation.boolean(json['stairFree'], 'stairFree'),
      reasonCodes: JourneyV3Validation.list(json['reasonCodes'], 'reasonCodes', (v) => JourneyV3Validation.string(v, 'reasonCode'), unique: true),
    );
  }
  Map<String, Object?> toJson() => {'result': result.wire, 'stairFree': stairFree, 'reasonCodes': reasonCodes};
}

class Journey {
  final String journeyId;
  final JourneyStatus status;
  final JourneyPlanSource planSource;
  final DateTime plannedDepartureTime;
  final DateTime plannedArrivalTime;
  final DateTime? realtimeDepartureTime;
  final DateTime? realtimeArrivalTime;
  final int durationSeconds;
  final int transferCount;
  final int walkingDistanceMeters;
  final JourneyTimeSource timeSource;
  final JourneyAccessibility accessibility;
  final List<JourneyLeg> legs;
  const Journey({
    required this.journeyId,
    required this.status,
    required this.planSource,
    required this.plannedDepartureTime,
    required this.plannedArrivalTime,
    required this.realtimeDepartureTime,
    required this.realtimeArrivalTime,
    required this.durationSeconds,
    required this.transferCount,
    required this.walkingDistanceMeters,
    required this.timeSource,
    required this.accessibility,
    required this.legs,
  });
  factory Journey.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'journeyId',
      'status',
      'planSource',
      'plannedDepartureTime',
      'plannedArrivalTime',
      'realtimeDepartureTime',
      'realtimeArrivalTime',
      'durationSeconds',
      'transferCount',
      'walkingDistanceMeters',
      'timeSource',
      'accessibility',
      'legs',
    });
    final accessibility = json['accessibility'];
    if (accessibility is! Map<String, Object?>) throw const FormatException('accessibility must be object');
    return Journey(
      journeyId: JourneyV3Validation.nonBlank(json['journeyId'], 'journeyId'),
      status: JourneyStatusWire.fromWire(json['status']),
      planSource: JourneyPlanSourceWire.fromWire(json['planSource']),
      plannedDepartureTime: JourneyV3Validation.rfc3339(json['plannedDepartureTime'], 'plannedDepartureTime'),
      plannedArrivalTime: JourneyV3Validation.rfc3339(json['plannedArrivalTime'], 'plannedArrivalTime'),
      realtimeDepartureTime: JourneyV3Validation.nullable(json, 'realtimeDepartureTime', (v) => JourneyV3Validation.rfc3339(v, 'realtimeDepartureTime')),
      realtimeArrivalTime: JourneyV3Validation.nullable(json, 'realtimeArrivalTime', (v) => JourneyV3Validation.rfc3339(v, 'realtimeArrivalTime')),
      durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0),
      transferCount: JourneyV3Validation.integer(json['transferCount'], 'transferCount', 0, 3),
      walkingDistanceMeters: JourneyV3Validation.integer(json['walkingDistanceMeters'], 'walkingDistanceMeters', 0),
      timeSource: JourneyTimeSourceWire.fromWire(json['timeSource']),
      accessibility: JourneyAccessibility.fromJson(accessibility),
      legs: JourneyV3Validation.list(json['legs'], 'legs', (v) {
        if (v is! Map<String, Object?>) throw const FormatException('leg must be object');
        return JourneyLeg.fromJson(v);
      }, minimum: 1),
    );
  }
  Map<String, Object?> toJson() => {
    'journeyId': journeyId,
    'status': status.wire,
    'planSource': planSource.wire,
    'plannedDepartureTime': JourneyV3Validation.rfc3339Wire(plannedDepartureTime),
    'plannedArrivalTime': JourneyV3Validation.rfc3339Wire(plannedArrivalTime),
    'realtimeDepartureTime': realtimeDepartureTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeDepartureTime!),
    'realtimeArrivalTime': realtimeArrivalTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeArrivalTime!),
    'durationSeconds': durationSeconds,
    'transferCount': transferCount,
    'walkingDistanceMeters': walkingDistanceMeters,
    'timeSource': timeSource.wire,
    'accessibility': accessibility.toJson(),
    'legs': legs.map((v) => v.toJson()).toList(growable: false),
  };
}

class JourneySearchSuccess {
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
  final List<Journey> journeys;
  const JourneySearchSuccess({
    required this.contractVersion,
    required this.requestId,
    required this.queryId,
    required this.calculatedAt,
    required this.validUntil,
    required this.effectiveDepartureTime,
    required this.serviceDate,
    required this.serviceTimezone,
    required this.sourceIdentity,
    required this.requestPolicy,
    required this.journeys,
  });
  factory JourneySearchSuccess.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'contractVersion',
      'requestId',
      'queryId',
      'calculatedAt',
      'validUntil',
      'effectiveDepartureTime',
      'serviceDate',
      'serviceTimezone',
      'sourceIdentity',
      'requestPolicy',
      'journeys',
    });
    final sourceIdentity = json['sourceIdentity'];
    final requestPolicy = json['requestPolicy'];
    if (sourceIdentity is! Map<String, Object?> || requestPolicy is! Map<String, Object?>) throw const FormatException('nested response must be object');
    final policy = JourneyRequestPolicy.fromJson(requestPolicy);
    final parsedSourceIdentity = JourneySourceIdentity.fromJson(sourceIdentity);
    if (policy.timePolicy == TimePolicy.timetableRequired && parsedSourceIdentity.realtimeSnapshotId != null) throw const FormatException('TIMETABLE_REQUIRED source realtime contract');
    if (policy.timePolicy == TimePolicy.realtimeRequired && parsedSourceIdentity.realtimeSnapshotId == null) throw const FormatException('REALTIME_REQUIRED source realtime contract');
    final journeys = JourneyV3Validation.list(
      json['journeys'],
      'journeys',
      (v) {
        if (v is! Map<String, Object?>) throw const FormatException('journey must be object');
        return Journey.fromJson(v);
      },
      minimum: 1,
      maximum: 3,
    );
    for (final journey in journeys) {
      if (policy.timePolicy == TimePolicy.timetableRequired && (journey.realtimeDepartureTime != null || journey.realtimeArrivalTime != null || journey.timeSource != JourneyTimeSource.timetable)) {
        throw const FormatException('TIMETABLE_REQUIRED realtime contract');
      }
      if (policy.timePolicy == TimePolicy.realtimeRequired && (journey.realtimeDepartureTime == null || journey.realtimeArrivalTime == null || journey.timeSource != JourneyTimeSource.realtime)) {
        throw const FormatException('REALTIME_REQUIRED realtime contract');
      }
      for (final leg in journey.legs) {
        if (leg is JourneyRideLeg) {
          if (policy.timePolicy == TimePolicy.timetableRequired && (leg.realtimeDepartureTime != null || leg.realtimeArrivalTime != null)) {
            throw const FormatException('TIMETABLE_REQUIRED ride realtime contract');
          }
          if (policy.timePolicy == TimePolicy.realtimeRequired && (leg.realtimeDepartureTime == null || leg.realtimeArrivalTime == null)) {
            throw const FormatException('REALTIME_REQUIRED ride realtime contract');
          }
        }
      }
    }
    return JourneySearchSuccess(
      contractVersion: JourneyContractVersionWire.fromWire(json['contractVersion']),
      requestId: JourneyV3Validation.ulid(json['requestId'], 'requestId'),
      queryId: JourneyV3Validation.nonBlank(json['queryId'], 'queryId'),
      calculatedAt: JourneyV3Validation.rfc3339(json['calculatedAt'], 'calculatedAt'),
      validUntil: JourneyV3Validation.rfc3339(json['validUntil'], 'validUntil'),
      effectiveDepartureTime: JourneyV3Validation.rfc3339(json['effectiveDepartureTime'], 'effectiveDepartureTime'),
      serviceDate: JourneyDate.parse(json['serviceDate']),
      serviceTimezone: JourneyV3Validation.enumWire(json['serviceTimezone'], 'serviceTimezone', (v) {
        if (v != 'Asia/Seoul') throw const FormatException();
        return 'Asia/Seoul';
      }),
      sourceIdentity: parsedSourceIdentity,
      requestPolicy: policy,
      journeys: journeys,
    );
  }
  Map<String, Object?> toJson() => {
    'contractVersion': contractVersion.wire,
    'requestId': requestId,
    'queryId': queryId,
    'calculatedAt': JourneyV3Validation.rfc3339Wire(calculatedAt),
    'validUntil': JourneyV3Validation.rfc3339Wire(validUntil),
    'effectiveDepartureTime': JourneyV3Validation.rfc3339Wire(effectiveDepartureTime),
    'serviceDate': serviceDate.toString(),
    'serviceTimezone': serviceTimezone,
    'sourceIdentity': sourceIdentity.toJson(),
    'requestPolicy': requestPolicy.toJson(),
    'journeys': journeys.map((v) => v.toJson()).toList(growable: false),
  };
}

sealed class StationTimetableSelector {
  const StationTimetableSelector();
  Map<String, Object?> toJson();
  static StationTimetableSelector fromJson(Map<String, Object?> json) => switch (StationTimetableSelectorKindWire.fromWire(json['kind'])) {
    StationTimetableSelectorKind.serviceDate => StationTimetableServiceDateSelector.fromJson(json),
    StationTimetableSelectorKind.dayType => StationTimetableDayTypeSelector.fromJson(json),
    StationTimetableSelectorKind.nextDepartures => StationTimetableNextDeparturesSelector.fromJson(json),
  };
}

class StationTimetableServiceDateSelector extends StationTimetableSelector {
  final JourneyDate serviceDate;
  const StationTimetableServiceDateSelector(this.serviceDate);
  factory StationTimetableServiceDateSelector.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'kind', 'serviceDate'});
    if (StationTimetableSelectorKindWire.fromWire(json['kind']) != StationTimetableSelectorKind.serviceDate) throw const FormatException('selector kind');
    return StationTimetableServiceDateSelector(JourneyDate.parse(json['serviceDate']));
  }
  @override
  Map<String, Object?> toJson() => {'kind': StationTimetableSelectorKind.serviceDate.wire, 'serviceDate': serviceDate.toString()};
}

class StationTimetableDayTypeSelector extends StationTimetableSelector {
  final StationTimetableDayType dayType;
  final JourneyDate referenceDate;
  const StationTimetableDayTypeSelector({required this.dayType, required this.referenceDate});
  factory StationTimetableDayTypeSelector.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'kind', 'dayType', 'referenceDate'});
    if (StationTimetableSelectorKindWire.fromWire(json['kind']) != StationTimetableSelectorKind.dayType) throw const FormatException('selector kind');
    return StationTimetableDayTypeSelector(dayType: StationTimetableDayTypeWire.fromWire(json['dayType']), referenceDate: JourneyDate.parse(json['referenceDate']));
  }
  @override
  Map<String, Object?> toJson() => {'kind': StationTimetableSelectorKind.dayType.wire, 'dayType': dayType.wire, 'referenceDate': referenceDate.toString()};
}

class StationTimetableNextDeparturesSelector extends StationTimetableSelector {
  final DateTime asOf;
  final int horizonDays;
  const StationTimetableNextDeparturesSelector({required this.asOf, required this.horizonDays});
  factory StationTimetableNextDeparturesSelector.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'kind', 'asOf', 'horizonDays'});
    if (StationTimetableSelectorKindWire.fromWire(json['kind']) != StationTimetableSelectorKind.nextDepartures) throw const FormatException('selector kind');
    return StationTimetableNextDeparturesSelector(asOf: JourneyV3Validation.rfc3339(json['asOf'], 'asOf'), horizonDays: JourneyV3Validation.integer(json['horizonDays'], 'horizonDays', 1, 8));
  }
  @override
  Map<String, Object?> toJson() => {'kind': StationTimetableSelectorKind.nextDepartures.wire, 'asOf': JourneyV3Validation.rfc3339Wire(asOf), 'horizonDays': horizonDays};
}

class StationTimetableSearchRequest {
  final String stationId;
  final String lineId;
  final StationTimetableSelector selector;
  const StationTimetableSearchRequest({required this.stationId, required this.lineId, required this.selector});
  factory StationTimetableSearchRequest.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'stationId', 'lineId', 'selector'});
    final selector = json['selector'];
    if (selector is! Map<String, Object?>) throw const FormatException('selector must be object');
    return StationTimetableSearchRequest(
      stationId: JourneyV3Validation.nonBlank(json['stationId'], 'stationId'),
      lineId: JourneyV3Validation.nonBlank(json['lineId'], 'lineId'),
      selector: StationTimetableSelector.fromJson(selector),
    );
  }
  Map<String, Object?> toJson() => {'stationId': stationId, 'lineId': lineId, 'selector': selector.toJson()};
}

class StationTimetableDeparture {
  final JourneyDate serviceDate;
  final int secondsFromServiceDayStart;
  final DateTime departureAt;
  final StationTimetableServicePattern servicePattern;
  final StationTimetableServiceClass serviceClass;
  const StationTimetableDeparture({required this.serviceDate, required this.secondsFromServiceDayStart, required this.departureAt, required this.servicePattern, required this.serviceClass});
  factory StationTimetableDeparture.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'serviceDate', 'secondsFromServiceDayStart', 'departureAt', 'servicePattern', 'serviceClass'});
    return StationTimetableDeparture(
      serviceDate: JourneyDate.parse(json['serviceDate']),
      secondsFromServiceDayStart: JourneyV3Validation.integer(json['secondsFromServiceDayStart'], 'secondsFromServiceDayStart', 0, 107999),
      departureAt: JourneyV3Validation.rfc3339(json['departureAt'], 'departureAt'),
      servicePattern: StationTimetableServicePatternWire.fromWire(json['servicePattern']),
      serviceClass: StationTimetableServiceClassWire.fromWire(json['serviceClass']),
    );
  }
  Map<String, Object?> toJson() => {
    'serviceDate': serviceDate.toString(),
    'secondsFromServiceDayStart': secondsFromServiceDayStart,
    'departureAt': JourneyV3Validation.rfc3339Wire(departureAt),
    'servicePattern': servicePattern.wire,
    'serviceClass': serviceClass.wire,
  };
}

class StationTimetableDirectionGroup {
  final String directionName;
  final List<StationTimetableDeparture> departures;
  const StationTimetableDirectionGroup({required this.directionName, required this.departures});
  factory StationTimetableDirectionGroup.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'directionName', 'departures'});
    return StationTimetableDirectionGroup(
      directionName: JourneyV3Validation.nonBlank(json['directionName'], 'directionName'),
      departures: JourneyV3Validation.list(json['departures'], 'departures', (v) {
        if (v is! Map<String, Object?>) throw const FormatException('departure must be object');
        return StationTimetableDeparture.fromJson(v);
      }),
    );
  }
  Map<String, Object?> toJson() => {'directionName': directionName, 'departures': departures.map((v) => v.toJson()).toList(growable: false)};
}

class StationTimetableSourceIdentity {
  final String timetableArtifactId;
  final String timetableSnapshotSha256;
  final String canonicalStationVersion;
  final String canonicalStationSetSha256;
  final String sourceLineageSha256;
  final String evidenceHash;
  final DateTime freshUntil;
  const StationTimetableSourceIdentity({
    required this.timetableArtifactId,
    required this.timetableSnapshotSha256,
    required this.canonicalStationVersion,
    required this.canonicalStationSetSha256,
    required this.sourceLineageSha256,
    required this.evidenceHash,
    required this.freshUntil,
  });
  factory StationTimetableSourceIdentity.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'timetableArtifactId',
      'timetableSnapshotSha256',
      'canonicalStationVersion',
      'canonicalStationSetSha256',
      'sourceLineageSha256',
      'evidenceHash',
      'freshUntil',
    });
    return StationTimetableSourceIdentity(
      timetableArtifactId: JourneyV3Validation.nonBlank(json['timetableArtifactId'], 'timetableArtifactId'),
      timetableSnapshotSha256: JourneyV3Validation.sha256(json['timetableSnapshotSha256'], 'timetableSnapshotSha256'),
      canonicalStationVersion: JourneyV3Validation.nonBlank(json['canonicalStationVersion'], 'canonicalStationVersion'),
      canonicalStationSetSha256: JourneyV3Validation.sha256(json['canonicalStationSetSha256'], 'canonicalStationSetSha256'),
      sourceLineageSha256: JourneyV3Validation.sha256(json['sourceLineageSha256'], 'sourceLineageSha256'),
      evidenceHash: JourneyV3Validation.sha256(json['evidenceHash'], 'evidenceHash'),
      freshUntil: JourneyV3Validation.rfc3339(json['freshUntil'], 'freshUntil'),
    );
  }
  Map<String, Object?> toJson() => {
    'timetableArtifactId': timetableArtifactId,
    'timetableSnapshotSha256': timetableSnapshotSha256,
    'canonicalStationVersion': canonicalStationVersion,
    'canonicalStationSetSha256': canonicalStationSetSha256,
    'sourceLineageSha256': sourceLineageSha256,
    'evidenceHash': evidenceHash,
    'freshUntil': JourneyV3Validation.rfc3339Wire(freshUntil),
  };
}

class StationTimetableSearchSuccess {
  final StationTimetableSearchContractVersion contractVersion;
  final String stationId;
  final String lineId;
  final StationTimetableSelector selector;
  final StationTimetableDayType resolvedDayType;
  final StationTimetableServiceTimezone serviceTimezone;
  final List<StationTimetableDirectionGroup> directionGroups;
  final StationTimetableSourceIdentity sourceIdentity;
  const StationTimetableSearchSuccess({
    required this.contractVersion,
    required this.stationId,
    required this.lineId,
    required this.selector,
    required this.resolvedDayType,
    required this.serviceTimezone,
    required this.directionGroups,
    required this.sourceIdentity,
  });
  factory StationTimetableSearchSuccess.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'contractVersion', 'stationId', 'lineId', 'selector', 'resolvedDayType', 'serviceTimezone', 'directionGroups', 'sourceIdentity'});
    final selector = json['selector'];
    final sourceIdentity = json['sourceIdentity'];
    if (selector is! Map<String, Object?> || sourceIdentity is! Map<String, Object?>) throw const FormatException('nested timetable object');
    return StationTimetableSearchSuccess(
      contractVersion: StationTimetableSearchContractVersionWire.fromWire(json['contractVersion']),
      stationId: JourneyV3Validation.nonBlank(json['stationId'], 'stationId'),
      lineId: JourneyV3Validation.nonBlank(json['lineId'], 'lineId'),
      selector: StationTimetableSelector.fromJson(selector),
      resolvedDayType: StationTimetableDayTypeWire.fromWire(json['resolvedDayType']),
      serviceTimezone: StationTimetableServiceTimezoneWire.fromWire(json['serviceTimezone']),
      directionGroups: JourneyV3Validation.list(json['directionGroups'], 'directionGroups', (v) {
        if (v is! Map<String, Object?>) throw const FormatException('direction group must be object');
        return StationTimetableDirectionGroup.fromJson(v);
      }),
      sourceIdentity: StationTimetableSourceIdentity.fromJson(sourceIdentity),
    );
  }
  Map<String, Object?> toJson() => {
    'contractVersion': contractVersion.wire,
    'stationId': stationId,
    'lineId': lineId,
    'selector': selector.toJson(),
    'resolvedDayType': resolvedDayType.wire,
    'serviceTimezone': serviceTimezone.wire,
    'directionGroups': directionGroups.map((v) => v.toJson()).toList(growable: false),
    'sourceIdentity': sourceIdentity.toJson(),
  };
}
