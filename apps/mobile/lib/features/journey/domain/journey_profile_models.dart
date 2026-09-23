import '../../../generated/journey_v3/journey_v3_contract.dart';

sealed class JourneyTemporalQuery {
  const JourneyTemporalQuery();

  Map<String, Object?> toJson();

  static JourneyTemporalQuery fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    return switch (kind) {
      'DEPART_BETWEEN' => JourneyDepartBetweenQuery.fromJson(json),
      'ARRIVE_BY' => JourneyArriveByQuery.fromJson(json),
      'LAST_CONNECTION' => JourneyLastConnectionQuery.fromJson(json),
      _ => throw FormatException('Unknown temporal query kind: $kind'),
    };
  }
}

class JourneyDepartBetweenQuery extends JourneyTemporalQuery {
  const JourneyDepartBetweenQuery({
    required this.earliestReadyAt,
    required this.latestReadyAt,
  });

  factory JourneyDepartBetweenQuery.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'kind',
      'earliestReadyAt',
      'latestReadyAt',
    });
    final earliest = JourneyV3Validation.rfc3339(
      json['earliestReadyAt'],
      'earliestReadyAt',
    );
    final latest = JourneyV3Validation.rfc3339(
      json['latestReadyAt'],
      'latestReadyAt',
    );
    if (!latest.isAfter(earliest)) {
      throw const FormatException(
        'latestReadyAt must be strictly after earliestReadyAt',
      );
    }
    return JourneyDepartBetweenQuery(
      earliestReadyAt: earliest,
      latestReadyAt: latest,
    );
  }

  final DateTime earliestReadyAt;
  final DateTime latestReadyAt;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'DEPART_BETWEEN',
    'earliestReadyAt': JourneyV3Validation.rfc3339Wire(earliestReadyAt),
    'latestReadyAt': JourneyV3Validation.rfc3339Wire(latestReadyAt),
  };
}

class JourneyArriveByQuery extends JourneyTemporalQuery {
  const JourneyArriveByQuery({
    required this.earliestReadyAt,
    required this.arrivalDeadline,
  });

  factory JourneyArriveByQuery.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'kind',
      'earliestReadyAt',
      'arrivalDeadline',
    });
    final earliest = JourneyV3Validation.rfc3339(
      json['earliestReadyAt'],
      'earliestReadyAt',
    );
    final deadline = JourneyV3Validation.rfc3339(
      json['arrivalDeadline'],
      'arrivalDeadline',
    );
    if (!deadline.isAfter(earliest)) {
      throw const FormatException(
        'arrivalDeadline must be strictly after earliestReadyAt',
      );
    }
    return JourneyArriveByQuery(
      earliestReadyAt: earliest,
      arrivalDeadline: deadline,
    );
  }

  final DateTime earliestReadyAt;
  final DateTime arrivalDeadline;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'ARRIVE_BY',
    'earliestReadyAt': JourneyV3Validation.rfc3339Wire(earliestReadyAt),
    'arrivalDeadline': JourneyV3Validation.rfc3339Wire(arrivalDeadline),
  };
}

class JourneyLastConnectionQuery extends JourneyTemporalQuery {
  const JourneyLastConnectionQuery({required this.serviceDate});

  factory JourneyLastConnectionQuery.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'kind', 'serviceDate'});
    final date = JourneyDate.parse(json['serviceDate']);
    return JourneyLastConnectionQuery(serviceDate: date.toString());
  }

  final String serviceDate;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'LAST_CONNECTION',
    'serviceDate': serviceDate,
  };
}

class JourneyProfileRequest {
  const JourneyProfileRequest({
    required this.requestId,
    required this.originStationId,
    required this.destinationStationId,
    required this.temporalQuery,
    required this.timePolicy,
    required this.walkingPace,
    required this.mobilityProfile,
    required this.constraintMode,
    required this.maxTransfers,
    required this.alternativeCount,
  });

  factory JourneyProfileRequest.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'requestId',
      'originStationId',
      'destinationStationId',
      'temporalQuery',
      'timePolicy',
      'walkingPace',
      'mobilityProfile',
      'constraintMode',
      'maxTransfers',
      'alternativeCount',
    });
    final mobilityProfile = MobilityProfileWire.fromWire(
      json['mobilityProfile'],
    );
    final constraintMode = ConstraintModeWire.fromWire(json['constraintMode']);
    if (mobilityProfile == MobilityProfile.noStairs &&
        constraintMode == ConstraintMode.none) {
      throw const FormatException('NO_STAIRS plus NONE is forbidden');
    }
    final rawTemporal = json['temporalQuery'];
    if (rawTemporal is! Map<String, Object?>) {
      throw const FormatException('temporalQuery must be object');
    }
    return JourneyProfileRequest(
      requestId: JourneyV3Validation.ulid(json['requestId'], 'requestId'),
      originStationId: JourneyV3Validation.nonBlank(
        json['originStationId'],
        'originStationId',
      ),
      destinationStationId: JourneyV3Validation.nonBlank(
        json['destinationStationId'],
        'destinationStationId',
      ),
      temporalQuery: JourneyTemporalQuery.fromJson(rawTemporal),
      timePolicy: TimePolicyWire.fromWire(json['timePolicy']),
      walkingPace: WalkingPaceWire.fromWire(json['walkingPace']),
      mobilityProfile: mobilityProfile,
      constraintMode: constraintMode,
      maxTransfers: JourneyV3Validation.integer(
        json['maxTransfers'],
        'maxTransfers',
        0,
        3,
      ),
      alternativeCount: JourneyV3Validation.integer(
        json['alternativeCount'],
        'alternativeCount',
        1,
        3,
      ),
    );
  }

  final String requestId;
  final String originStationId;
  final String destinationStationId;
  final JourneyTemporalQuery temporalQuery;
  final TimePolicy timePolicy;
  final WalkingPace walkingPace;
  final MobilityProfile mobilityProfile;
  final ConstraintMode constraintMode;
  final int maxTransfers;
  final int alternativeCount;

  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'originStationId': originStationId,
    'destinationStationId': destinationStationId,
    'temporalQuery': temporalQuery.toJson(),
    'timePolicy': timePolicy.wire,
    'walkingPace': walkingPace.wire,
    'mobilityProfile': mobilityProfile.wire,
    'constraintMode': constraintMode.wire,
    'maxTransfers': maxTransfers,
    'alternativeCount': alternativeCount,
  };
}

class JourneyProfileJourneyCandidate {
  const JourneyProfileJourneyCandidate({
    required this.journeyId,
    required this.readyAt,
    required this.journeyStartTime,
    required this.firstBoardingTime,
    required this.arrivalAtPlatform,
    required this.arrivalAtDestination,
    required this.objectiveTags,
    required this.journey,
  });

  factory JourneyProfileJourneyCandidate.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {
      'journeyId',
      'readyAt',
      'journeyStartTime',
      'firstBoardingTime',
      'arrivalAtPlatform',
      'arrivalAtDestination',
      'objectiveTags',
      'journey',
    });
    final rawJourney = json['journey'];
    if (rawJourney is! Map<String, Object?>) {
      throw const FormatException('journey must be object');
    }
    final rawTags = json['objectiveTags'];
    if (rawTags is! List) {
      throw const FormatException('objectiveTags must be array');
    }
    return JourneyProfileJourneyCandidate(
      journeyId: JourneyV3Validation.nonBlank(json['journeyId'], 'journeyId'),
      readyAt: JourneyV3Validation.rfc3339(json['readyAt'], 'readyAt'),
      journeyStartTime: JourneyV3Validation.rfc3339(
        json['journeyStartTime'],
        'journeyStartTime',
      ),
      firstBoardingTime: JourneyV3Validation.rfc3339(
        json['firstBoardingTime'],
        'firstBoardingTime',
      ),
      arrivalAtPlatform: JourneyV3Validation.rfc3339(
        json['arrivalAtPlatform'],
        'arrivalAtPlatform',
      ),
      arrivalAtDestination: JourneyV3Validation.rfc3339(
        json['arrivalAtDestination'],
        'arrivalAtDestination',
      ),
      objectiveTags: rawTags
          .map((t) => JourneyV3Validation.nonBlank(t, 'objectiveTag'))
          .toList(),
      journey: Journey.fromJson(rawJourney),
    );
  }

  final String journeyId;
  final DateTime readyAt;
  final DateTime journeyStartTime;
  final DateTime firstBoardingTime;
  final DateTime arrivalAtPlatform;
  final DateTime arrivalAtDestination;
  final List<String> objectiveTags;
  final Journey journey;

  Map<String, Object?> toJson() => {
    'journeyId': journeyId,
    'readyAt': JourneyV3Validation.rfc3339Wire(readyAt),
    'journeyStartTime': JourneyV3Validation.rfc3339Wire(journeyStartTime),
    'firstBoardingTime': JourneyV3Validation.rfc3339Wire(firstBoardingTime),
    'arrivalAtPlatform': JourneyV3Validation.rfc3339Wire(arrivalAtPlatform),
    'arrivalAtDestination': JourneyV3Validation.rfc3339Wire(
      arrivalAtDestination,
    ),
    'objectiveTags': objectiveTags,
    'journey': journey.toJson(),
  };
}

class JourneyProfileSuccess {
  const JourneyProfileSuccess({
    required this.contractVersion,
    required this.requestId,
    required this.queryId,
    required this.calculatedAt,
    required this.validUntil,
    required this.temporalQuery,
    required this.journeys,
    this.sourceIdentity,
  });

  factory JourneyProfileSuccess.fromJson(Map<String, Object?> json) {
    final version = JourneyV3Validation.string(
      json['contractVersion'],
      'contractVersion',
    );
    if (version != 'JOURNEY_PROFILE_V1') {
      throw FormatException('Unexpected contractVersion: $version');
    }
    final rawTemporal = json['temporalQuery'];
    if (rawTemporal is! Map<String, Object?>) {
      throw const FormatException('temporalQuery must be object');
    }
    final rawJourneys = json['journeys'];
    if (rawJourneys is! List) {
      throw const FormatException('journeys must be array');
    }

    JourneySourceIdentity? sourceId;
    if (json['sourceIdentity'] case final Map<String, Object?> rawSource) {
      sourceId = JourneySourceIdentity.fromJson(rawSource);
    }

    return JourneyProfileSuccess(
      contractVersion: version,
      requestId: JourneyV3Validation.ulid(json['requestId'], 'requestId'),
      queryId: JourneyV3Validation.nonBlank(json['queryId'], 'queryId'),
      calculatedAt: JourneyV3Validation.rfc3339(
        json['calculatedAt'],
        'calculatedAt',
      ),
      validUntil: JourneyV3Validation.rfc3339(json['validUntil'], 'validUntil'),
      temporalQuery: JourneyTemporalQuery.fromJson(rawTemporal),
      journeys: rawJourneys.map((c) {
        if (c is! Map<String, Object?>) {
          throw const FormatException('journey candidate must be object');
        }
        return JourneyProfileJourneyCandidate.fromJson(c);
      }).toList(),
      sourceIdentity: sourceId,
    );
  }

  final String contractVersion;
  final String requestId;
  final String queryId;
  final DateTime calculatedAt;
  final DateTime validUntil;
  final JourneyTemporalQuery temporalQuery;
  final List<JourneyProfileJourneyCandidate> journeys;
  final JourneySourceIdentity? sourceIdentity;

  List<Journey> get journeyList =>
      journeys.map((c) => c.journey).toList(growable: false);

  JourneySearchSuccess toSearchSuccess({
    required TimePolicy timePolicy,
    required WalkingPace walkingPace,
    required MobilityProfile mobilityProfile,
    required ConstraintMode constraintMode,
    required int maxTransfers,
    required int alternativeCount,
  }) {
    final effectiveDeparture = journeys.isNotEmpty
        ? journeys.first.journey.plannedDepartureTime
        : calculatedAt;
    final seoul = effectiveDeparture.toUtc().add(const Duration(hours: 9));
    final serviceDateStr =
        '${seoul.year.toString().padLeft(4, '0')}-'
        '${seoul.month.toString().padLeft(2, '0')}-'
        '${seoul.day.toString().padLeft(2, '0')}';

    return JourneySearchSuccess(
      contractVersion: JourneyContractVersion.journeySearchV3,
      requestId: requestId,
      queryId: queryId,
      calculatedAt: calculatedAt,
      validUntil: validUntil,
      effectiveDepartureTime: effectiveDeparture,
      serviceDate: JourneyDate.parse(serviceDateStr),
      serviceTimezone: 'Asia/Seoul',
      sourceIdentity:
          sourceIdentity ??
          JourneySourceIdentity(
            routeBundleId: 'profile-bundle',
            routeBundleSha256: '0' * 64,
            timetableSnapshotId: 'profile-timetable',
            accessibilitySnapshotId: 'profile-accessibility',
            realtimeSnapshotId: null,
          ),
      requestPolicy: JourneyRequestPolicy(
        timePolicy: timePolicy,
        walkingPace: walkingPace,
        mobilityProfile: mobilityProfile,
        constraintMode: constraintMode,
        maxTransfers: maxTransfers,
        alternativeCount: alternativeCount,
      ),
      journeys: journeyList,
    );
  }
}
