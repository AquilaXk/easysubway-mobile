import 'package:flutter/foundation.dart';

import '../../../generated/journey_v3/journey_v3_contract.dart';
import 'journey_search_controller.dart';

enum JourneyAlarmBindingFailure {
  expired,
  identityMismatch,
  noRide,
  incompleteRealtime,
}

final class JourneyAlarmBindingException implements Exception {
  const JourneyAlarmBindingException(this.failure);

  final JourneyAlarmBindingFailure failure;
}

enum JourneyAlarmStopKind { transfer, destination }

@immutable
class JourneyAlarmStopInput {
  const JourneyAlarmStopInput({
    required this.stationId,
    required this.arrivalAt,
    required this.kind,
  });

  final String stationId;
  final DateTime arrivalAt;
  final JourneyAlarmStopKind kind;
}

@immutable
class JourneySelectedIdentity {
  JourneySelectedIdentity.fromSnapshot(JourneySelectedSnapshot snapshot)
    : contractVersion = snapshot.contractVersion,
      requestId = snapshot.requestId,
      queryId = snapshot.queryId,
      calculatedAt = snapshot.calculatedAt,
      validUntil = snapshot.validUntil,
      effectiveDepartureTime = snapshot.effectiveDepartureTime,
      serviceDate = JourneyDate.parse(snapshot.serviceDate.toString()),
      serviceTimezone = snapshot.serviceTimezone,
      sourceIdentity = JourneySourceIdentity(
        routeBundleId: snapshot.sourceIdentity.routeBundleId,
        routeBundleSha256: snapshot.sourceIdentity.routeBundleSha256,
        timetableSnapshotId: snapshot.sourceIdentity.timetableSnapshotId,
        accessibilitySnapshotId:
            snapshot.sourceIdentity.accessibilitySnapshotId,
        realtimeSnapshotId: snapshot.sourceIdentity.realtimeSnapshotId,
      ),
      requestPolicy = JourneyRequestPolicy(
        timePolicy: snapshot.requestPolicy.timePolicy,
        mobilityProfile: snapshot.requestPolicy.mobilityProfile,
        constraintMode: snapshot.requestPolicy.constraintMode,
        maxTransfers: snapshot.requestPolicy.maxTransfers,
        alternativeCount: snapshot.requestPolicy.alternativeCount,
      ),
      journeyId = snapshot.journey.journeyId;

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
  final String journeyId;
}

@immutable
class JourneyGetOffAlarmBinding {
  const JourneyGetOffAlarmBinding._({
    required this.identity,
    required this.stops,
  });

  factory JourneyGetOffAlarmBinding.fromSnapshot(
    JourneySelectedSnapshot snapshot, {
    required DateTime now,
  }) {
    if (!now.isBefore(snapshot.validUntil)) {
      throw const JourneyAlarmBindingException(
        JourneyAlarmBindingFailure.expired,
      );
    }
    if (snapshot.contractVersion != JourneyContractVersion.journeySearchV3 ||
        snapshot.serviceTimezone != 'Asia/Seoul' ||
        snapshot.validUntil.isBefore(snapshot.calculatedAt) ||
        snapshot.journey.status != JourneyStatus.found ||
        snapshot.journey.planSource !=
            JourneyPlanSource.serverTimetableRaptor) {
      throw const JourneyAlarmBindingException(
        JourneyAlarmBindingFailure.identityMismatch,
      );
    }

    final rides = snapshot.journey.legs.whereType<JourneyRideLeg>().toList(
      growable: false,
    );
    if (rides.isEmpty) {
      throw const JourneyAlarmBindingException(
        JourneyAlarmBindingFailure.noRide,
      );
    }

    final realtime = switch (snapshot.requestPolicy.timePolicy) {
      TimePolicy.timetableRequired => false,
      TimePolicy.realtimeRequired => true,
    };
    if (!_hasMatchingRealtimeIdentity(snapshot, realtime)) {
      throw const JourneyAlarmBindingException(
        JourneyAlarmBindingFailure.identityMismatch,
      );
    }

    final stops = <JourneyAlarmStopInput>[];
    for (var index = 0; index < rides.length; index++) {
      final ride = rides[index];
      final arrival = realtime
          ? ride.realtimeArrivalTime
          : ride.plannedArrivalTime;
      if (arrival == null) {
        throw const JourneyAlarmBindingException(
          JourneyAlarmBindingFailure.incompleteRealtime,
        );
      }
      stops.add(
        JourneyAlarmStopInput(
          stationId: ride.toStationId,
          arrivalAt: arrival,
          kind: index == rides.length - 1
              ? JourneyAlarmStopKind.destination
              : JourneyAlarmStopKind.transfer,
        ),
      );
    }

    return JourneyGetOffAlarmBinding._(
      identity: JourneySelectedIdentity.fromSnapshot(snapshot),
      stops: List<JourneyAlarmStopInput>.unmodifiable(stops),
    );
  }

  final JourneySelectedIdentity identity;
  final List<JourneyAlarmStopInput> stops;

  static bool _hasMatchingRealtimeIdentity(
    JourneySelectedSnapshot snapshot,
    bool realtime,
  ) {
    final realtimeSnapshotId = snapshot.sourceIdentity.realtimeSnapshotId;
    if (realtime) {
      return realtimeSnapshotId != null &&
          snapshot.journey.timeSource == JourneyTimeSource.realtime &&
          snapshot.journey.realtimeDepartureTime != null &&
          snapshot.journey.realtimeArrivalTime != null;
    }
    return realtimeSnapshotId == null &&
        snapshot.journey.timeSource == JourneyTimeSource.timetable &&
        snapshot.journey.realtimeDepartureTime == null &&
        snapshot.journey.realtimeArrivalTime == null &&
        snapshot.journey.legs.whereType<JourneyRideLeg>().every(
          (ride) =>
              ride.realtimeDepartureTime == null &&
              ride.realtimeArrivalTime == null,
        );
  }
}
