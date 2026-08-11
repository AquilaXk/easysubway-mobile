import 'package:easysubway_mobile/features/journey/application/journey_get_off_alarm_binding.dart';
import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timetable 선택은 full identity와 ordered planned arrivals를 결속한다', () {
    final snapshot = _snapshot();

    final binding = JourneyGetOffAlarmBinding.fromSnapshot(
      snapshot,
      now: DateTime.utc(2026, 8, 12, 0, 1),
    );

    expect(binding.identity.contractVersion, snapshot.contractVersion);
    expect(binding.identity.requestId, snapshot.requestId);
    expect(binding.identity.queryId, snapshot.queryId);
    expect(binding.identity.calculatedAt, snapshot.calculatedAt);
    expect(binding.identity.validUntil, snapshot.validUntil);
    expect(
      binding.identity.effectiveDepartureTime,
      snapshot.effectiveDepartureTime,
    );
    expect(binding.identity.serviceDate.toString(), '2026-08-12');
    expect(binding.identity.serviceTimezone, 'Asia/Seoul');
    expect(binding.identity.sourceIdentity.routeBundleId, 'route');
    expect(
      binding.identity.requestPolicy.timePolicy,
      TimePolicy.timetableRequired,
    );
    expect(binding.identity.journeyId, 'journey-1');
    expect(
      binding.stops
          .map((stop) => (stop.stationId, stop.arrivalAt, stop.kind))
          .toList(),
      <(String, DateTime, JourneyAlarmStopKind)>[
        (
          'transfer',
          DateTime.utc(2026, 8, 12, 0, 3),
          JourneyAlarmStopKind.transfer,
        ),
        (
          'destination',
          DateTime.utc(2026, 8, 12, 0, 5),
          JourneyAlarmStopKind.destination,
        ),
      ],
    );
    expect(
      () => binding.stops.add(
        JourneyAlarmStopInput(
          stationId: 'other',
          arrivalAt: DateTime.utc(2026, 8, 12, 0, 6),
          kind: JourneyAlarmStopKind.destination,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('realtime 선택은 every ride realtime arrival만 사용한다', () {
    final snapshot = _snapshot(realtime: true);

    final binding = JourneyGetOffAlarmBinding.fromSnapshot(
      snapshot,
      now: DateTime.utc(2026, 8, 12, 0, 1),
    );

    expect(binding.stops.map((stop) => stop.arrivalAt), <DateTime>[
      DateTime.utc(2026, 8, 12, 0, 4),
      DateTime.utc(2026, 8, 12, 0, 6),
    ]);
    expect(binding.identity.sourceIdentity.realtimeSnapshotId, 'realtime');
    expect(
      binding.identity.requestPolicy.timePolicy,
      TimePolicy.realtimeRequired,
    );
  });

  test('expired, mixed, no-ride와 partial realtime 선택은 explicit failure다', () {
    expect(
      () => JourneyGetOffAlarmBinding.fromSnapshot(
        _snapshot(),
        now: DateTime.utc(2026, 8, 12, 0, 5),
      ),
      _failure(JourneyAlarmBindingFailure.expired),
    );
    expect(
      () => JourneyGetOffAlarmBinding.fromSnapshot(
        _snapshot(mixedIdentity: true),
        now: DateTime.utc(2026, 8, 12, 0, 1),
      ),
      _failure(JourneyAlarmBindingFailure.identityMismatch),
    );
    expect(
      () => JourneyGetOffAlarmBinding.fromSnapshot(
        _snapshot(noRide: true),
        now: DateTime.utc(2026, 8, 12, 0, 1),
      ),
      _failure(JourneyAlarmBindingFailure.noRide),
    );
    expect(
      () => JourneyGetOffAlarmBinding.fromSnapshot(
        _snapshot(realtime: true, partialRealtime: true),
        now: DateTime.utc(2026, 8, 12, 0, 1),
      ),
      _failure(JourneyAlarmBindingFailure.incompleteRealtime),
    );
  });
}

Matcher _failure(JourneyAlarmBindingFailure failure) => throwsA(
  isA<JourneyAlarmBindingException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

JourneySelectedSnapshot _snapshot({
  bool realtime = false,
  bool noRide = false,
  bool partialRealtime = false,
  bool mixedIdentity = false,
}) {
  final response = JourneySearchSuccess(
    contractVersion: JourneyContractVersion.journeySearchV3,
    requestId: '01J9VV0K000000000000000000',
    queryId: 'query',
    calculatedAt: DateTime.utc(2026, 8, 12),
    validUntil: DateTime.utc(2026, 8, 12, 0, 5),
    effectiveDepartureTime: DateTime.utc(2026, 8, 12),
    serviceDate: JourneyDate.parse('2026-08-12'),
    serviceTimezone: 'Asia/Seoul',
    sourceIdentity: JourneySourceIdentity(
      routeBundleId: 'route',
      routeBundleSha256: 'a' * 64,
      timetableSnapshotId: 'timetable',
      accessibilitySnapshotId: 'accessibility',
      realtimeSnapshotId: realtime || mixedIdentity ? 'realtime' : null,
    ),
    requestPolicy: JourneyRequestPolicy(
      timePolicy: realtime
          ? TimePolicy.realtimeRequired
          : TimePolicy.timetableRequired,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 1,
      alternativeCount: 1,
    ),
    journeys: <Journey>[
      Journey(
        journeyId: 'journey-1',
        status: JourneyStatus.found,
        planSource: JourneyPlanSource.serverTimetableRaptor,
        plannedDepartureTime: DateTime.utc(2026, 8, 12, 0, 1),
        plannedArrivalTime: DateTime.utc(2026, 8, 12, 0, 5),
        realtimeDepartureTime: realtime
            ? DateTime.utc(2026, 8, 12, 0, 2)
            : null,
        realtimeArrivalTime: realtime ? DateTime.utc(2026, 8, 12, 0, 6) : null,
        durationSeconds: 300,
        transferCount: noRide ? 0 : 1,
        walkingDistanceMeters: 0,
        timeSource: realtime
            ? JourneyTimeSource.realtime
            : JourneyTimeSource.timetable,
        accessibility: const JourneyAccessibility(
          result: JourneyAccessibilityResult.verified,
          stairFree: true,
          reasonCodes: <String>[],
        ),
        legs: noRide
            ? const <JourneyLeg>[
                JourneyEntryLeg(fromStationId: 'origin', durationSeconds: 60),
                JourneyExitLeg(
                  fromStationId: 'destination',
                  durationSeconds: 60,
                ),
              ]
            : <JourneyLeg>[
                JourneyRideLeg(
                  lineId: 'line-1',
                  tripId: 'trip-1',
                  directionStationId: 'destination',
                  fromStationId: 'origin',
                  toStationId: 'transfer',
                  plannedDepartureTime: DateTime.utc(2026, 8, 12, 0, 1),
                  plannedArrivalTime: DateTime.utc(2026, 8, 12, 0, 3),
                  realtimeDepartureTime: realtime
                      ? DateTime.utc(2026, 8, 12, 0, 2)
                      : null,
                  realtimeArrivalTime: realtime
                      ? DateTime.utc(2026, 8, 12, 0, 4)
                      : null,
                ),
                JourneyRideLeg(
                  lineId: 'line-2',
                  tripId: 'trip-2',
                  directionStationId: 'destination',
                  fromStationId: 'transfer',
                  toStationId: 'destination',
                  plannedDepartureTime: DateTime.utc(2026, 8, 12, 0, 4),
                  plannedArrivalTime: DateTime.utc(2026, 8, 12, 0, 5),
                  realtimeDepartureTime: realtime
                      ? DateTime.utc(2026, 8, 12, 0, 5)
                      : null,
                  realtimeArrivalTime: realtime && !partialRealtime
                      ? DateTime.utc(2026, 8, 12, 0, 6)
                      : null,
                ),
              ],
      ),
    ],
  );
  return JourneySelectedSnapshot.fromResponse(
    response,
    response.journeys.single,
  );
}
