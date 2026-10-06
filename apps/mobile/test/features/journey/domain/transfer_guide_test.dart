import 'package:easysubway_mobile/features/journey/domain/transfer_guide.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime.utc(2026, 10, 6, 0);

JourneyRideStop _stop(String id) => JourneyRideStop(
  stationId: id,
  plannedArrivalTime: _at,
  plannedDepartureTime: _at,
  realtimeArrivalTime: null,
  realtimeDepartureTime: null,
);

JourneyRideLeg _ride(String lineId, List<String> stops) => JourneyRideLeg(
  lineId: lineId,
  tripId: 'trip-$lineId',
  directionStationId: stops.last,
  fromStationId: stops.first,
  toStationId: stops.last,
  plannedDepartureTime: _at,
  plannedArrivalTime: _at,
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  servicePattern: JourneyServicePattern.local,
  stops: [for (final id in stops) _stop(id)],
);

Journey _journey(List<JourneyLeg> legs) => Journey(
  journeyId: 'journey-1',
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: _at,
  plannedArrivalTime: _at,
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  durationSeconds: 600,
  transferCount: 1,
  walkingDistanceMeters: 100,
  timeSource: JourneyTimeSource.timetable,
  accessibility: const JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: false,
    reasonCodes: <String>[],
  ),
  legs: legs,
  fare: const JourneyFare(
    status: JourneyFareStatus.unavailable,
    sourceSnapshotIds: <String>[],
  ),
);

const _transfer = JourneyTransferLeg(
  fromStationId: 's-gotermi',
  toStationId: 's-gotermi',
  durationSeconds: 240,
);

void main() {
  test('환승 leg의 키는 환승 leg·직전 탑승·다음 탑승에서 규칙대로 만든다', () {
    final journey = _journey([
      const JourneyEntryLeg(fromStationId: 's-dongjak', durationSeconds: 60),
      _ride('l-9', ['s-dongjak', 's-sinbanpo', 's-gotermi']),
      _transfer,
      _ride('l-3', ['s-gotermi', 's-jamwon', 's-apgujeong']),
      const JourneyExitLeg(fromStationId: 's-apgujeong', durationSeconds: 60),
    ]);

    final key = transferGuideKeyAt(journey, 2);

    expect(
      key,
      const TransferGuideKey(
        stationId: 's-gotermi',
        fromLineId: 'l-9',
        fromPrevStationId: 's-sinbanpo',
        toLineId: 'l-3',
        toNextStationId: 's-jamwon',
      ),
    );
  });

  test('직전 탑승은 끝에서 두 번째 정차역, 다음 탑승은 둘째 정차역을 쓴다', () {
    final journey = _journey([
      _ride('l-2', ['a', 'b', 'c', 'd', 'e']),
      const JourneyTransferLeg(
        fromStationId: 'e',
        toStationId: 'e',
        durationSeconds: 60,
      ),
      _ride('l-4', ['e', 'f', 'g', 'h']),
    ]);

    final key = transferGuideKeyAt(journey, 1)!;

    expect(key.fromPrevStationId, 'd');
    expect(key.toNextStationId, 'f');
    expect(key.stationId, 'e');
  });

  test('환승 leg가 아니거나 앞뒤가 탑승이 아니면 키를 만들지 않는다', () {
    final journey = _journey([
      const JourneyEntryLeg(fromStationId: 'a', durationSeconds: 60),
      _ride('l-2', ['a', 'b']),
      const JourneyTransferLeg(
        fromStationId: 'b',
        toStationId: 'b',
        durationSeconds: 60,
      ),
      const JourneyExitLeg(fromStationId: 'b', durationSeconds: 60),
    ]);

    expect(transferGuideKeyAt(journey, 0), isNull);
    expect(transferGuideKeyAt(journey, 1), isNull);
    expect(transferGuideKeyAt(journey, 2), isNull);
    expect(transferGuideKeyAt(journey, 3), isNull);
    expect(transferGuideKeyAt(journey, 9), isNull);
  });

  test('정차역이 둘 미만인 탑승은 키를 만들지 않는다', () {
    final journey = _journey([
      _ride('l-2', ['a']),
      const JourneyTransferLeg(
        fromStationId: 'a',
        toStationId: 'a',
        durationSeconds: 60,
      ),
      _ride('l-4', ['a', 'f']),
    ]);

    expect(transferGuideKeyAt(journey, 1), isNull);
  });
}
