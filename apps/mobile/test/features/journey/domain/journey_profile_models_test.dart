import 'package:easysubway_mobile/features/journey/domain/journey_profile_models.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

Journey _createSampleJourney(String id) {
  final now = DateTime.parse('2026-08-11T09:05:00.000Z');
  return Journey(
    journeyId: id,
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now,
    plannedArrivalTime: now.add(const Duration(minutes: 20)),
    realtimeDepartureTime: null,
    realtimeArrivalTime: null,
    durationSeconds: 1200,
    transferCount: 0,
    walkingDistanceMeters: 200,
    timeSource: JourneyTimeSource.timetable,
    accessibility: const JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: true,
      reasonCodes: <String>[],
    ),
    legs: const <JourneyLeg>[
      JourneyEntryLeg(fromStationId: 'station-origin', durationSeconds: 60),
    ],
  );
}

void main() {
  group('JourneyTemporalQuery', () {
    test('JourneyDepartBetweenQuery round-trips and validates', () {
      final json = {
        'kind': 'DEPART_BETWEEN',
        'earliestReadyAt': '2026-08-11T09:00:00.000Z',
        'latestReadyAt': '2026-08-11T10:00:00.000Z',
      };
      final query = JourneyDepartBetweenQuery.fromJson(json);
      expect(query.earliestReadyAt, DateTime.parse('2026-08-11T09:00:00Z'));
      expect(query.latestReadyAt, DateTime.parse('2026-08-11T10:00:00Z'));
      expect(query.toJson(), json);

      final polymorph = JourneyTemporalQuery.fromJson(json);
      expect(polymorph, isA<JourneyDepartBetweenQuery>());

      expect(
        () => JourneyDepartBetweenQuery.fromJson({
          'kind': 'DEPART_BETWEEN',
          'earliestReadyAt': '2026-08-11T10:00:00Z',
          'latestReadyAt': '2026-08-11T09:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('JourneyArriveByQuery round-trips and validates', () {
      final json = {
        'kind': 'ARRIVE_BY',
        'earliestReadyAt': '2026-08-11T09:00:00.000Z',
        'arrivalDeadline': '2026-08-11T10:00:00.000Z',
      };
      final query = JourneyArriveByQuery.fromJson(json);
      expect(query.earliestReadyAt, DateTime.parse('2026-08-11T09:00:00Z'));
      expect(query.arrivalDeadline, DateTime.parse('2026-08-11T10:00:00Z'));
      expect(query.toJson(), json);

      final polymorph = JourneyTemporalQuery.fromJson(json);
      expect(polymorph, isA<JourneyArriveByQuery>());

      expect(
        () => JourneyArriveByQuery.fromJson({
          'kind': 'ARRIVE_BY',
          'earliestReadyAt': '2026-08-11T10:00:00Z',
          'arrivalDeadline': '2026-08-11T09:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('JourneyLastConnectionQuery round-trips and validates', () {
      final json = {'kind': 'LAST_CONNECTION', 'serviceDate': '2026-08-11'};
      final query = JourneyLastConnectionQuery.fromJson(json);
      expect(query.serviceDate, '2026-08-11');
      expect(query.toJson(), json);

      final polymorph = JourneyTemporalQuery.fromJson(json);
      expect(polymorph, isA<JourneyLastConnectionQuery>());

      expect(
        () => JourneyTemporalQuery.fromJson({'kind': 'UNKNOWN_KIND'}),
        throwsFormatException,
      );
    });
  });

  group('JourneyProfileRequest', () {
    test('round-trips valid request and rejects invalid configurations', () {
      final json = {
        'requestId': '01J00000000000000000000000',
        'originStationId': 'station-a',
        'destinationStationId': 'station-b',
        'temporalQuery': {
          'kind': 'DEPART_BETWEEN',
          'earliestReadyAt': '2026-08-11T09:00:00.000Z',
          'latestReadyAt': '2026-08-11T10:00:00.000Z',
        },
        'timePolicy': 'TIMETABLE_REQUIRED',
        'walkingPace': 'STANDARD',
        'mobilityProfile': 'STANDARD',
        'constraintMode': 'NONE',
        'maxTransfers': 2,
        'alternativeCount': 2,
      };

      final request = JourneyProfileRequest.fromJson(json);
      expect(request.requestId, '01J00000000000000000000000');
      expect(request.originStationId, 'station-a');
      expect(request.destinationStationId, 'station-b');
      expect(request.maxTransfers, 2);
      expect(request.alternativeCount, 2);
      expect(request.toJson(), json);

      // NO_STAIRS + NONE is forbidden
      final forbiddenJson = Map<String, Object?>.from(json)
        ..['mobilityProfile'] = 'NO_STAIRS';
      expect(
        () => JourneyProfileRequest.fromJson(forbiddenJson),
        throwsFormatException,
      );

      // Non-map temporalQuery
      final invalidTemporalJson = Map<String, Object?>.from(json)
        ..['temporalQuery'] = 'not-a-map';
      expect(
        () => JourneyProfileRequest.fromJson(invalidTemporalJson),
        throwsFormatException,
      );
    });
  });

  group('JourneyProfileSuccess and Candidates', () {
    final sampleJourney = _createSampleJourney('j-1');

    final validCandidateMap = {
      'journeyId': 'j-1',
      'readyAt': '2026-08-11T09:00:00.000Z',
      'journeyStartTime': '2026-08-11T09:02:00.000Z',
      'firstBoardingTime': '2026-08-11T09:05:00.000Z',
      'arrivalAtPlatform': '2026-08-11T09:20:00.000Z',
      'arrivalAtDestination': '2026-08-11T09:25:00.000Z',
      'objectiveTags': ['FASTEST'],
      'journey': sampleJourney.toJson(),
    };

    test('JourneyProfileJourneyCandidate round-trips and validates', () {
      final candidate = JourneyProfileJourneyCandidate.fromJson(
        validCandidateMap,
      );
      expect(candidate.journeyId, 'j-1');
      expect(candidate.objectiveTags, ['FASTEST']);
      expect(candidate.toJson(), validCandidateMap);

      expect(
        () => JourneyProfileJourneyCandidate.fromJson(
          Map<String, Object?>.from(validCandidateMap)..['journey'] = 'invalid',
        ),
        throwsFormatException,
      );

      expect(
        () => JourneyProfileJourneyCandidate.fromJson(
          Map<String, Object?>.from(validCandidateMap)
            ..['objectiveTags'] = 'invalid',
        ),
        throwsFormatException,
      );
    });

    test(
      'JourneyProfileSuccess round-trips and converts to search success',
      () {
        final successMap = {
          'contractVersion': 'JOURNEY_PROFILE_V1',
          'requestId': '01J00000000000000000000000',
          'queryId': 'q-1',
          'calculatedAt': '2026-08-11T08:50:00.000Z',
          'validUntil': '2026-08-11T09:50:00.000Z',
          'temporalQuery': {
            'kind': 'DEPART_BETWEEN',
            'earliestReadyAt': '2026-08-11T09:00:00.000Z',
            'latestReadyAt': '2026-08-11T10:00:00.000Z',
          },
          'journeys': [validCandidateMap],
          'sourceIdentity': {
            'routeBundleId': 'rb-1',
            'routeBundleSha256': 'a' * 64,
            'timetableSnapshotId': 'tt-1',
            'accessibilitySnapshotId': 'acc-1',
            'realtimeSnapshotId': null,
          },
        };

        final success = JourneyProfileSuccess.fromJson(successMap);
        expect(success.contractVersion, 'JOURNEY_PROFILE_V1');
        expect(success.requestId, '01J00000000000000000000000');
        expect(success.queryId, 'q-1');
        expect(success.journeys.length, 1);
        expect(success.journeyList.length, 1);
        expect(success.sourceIdentity?.routeBundleId, 'rb-1');

        final searchSuccess = success.toSearchSuccess(
          timePolicy: TimePolicy.timetableRequired,
          walkingPace: WalkingPace.standard,
          mobilityProfile: MobilityProfile.standard,
          constraintMode: ConstraintMode.none,
          maxTransfers: 3,
          alternativeCount: 3,
        );
        expect(searchSuccess.journeys.length, 1);
        expect(
          searchSuccess.effectiveDepartureTime,
          DateTime.parse('2026-08-11T09:05:00Z'),
        );
        expect(searchSuccess.serviceDate.toString(), '2026-08-11');

        // Empty journeys conversion fallback
        final emptySuccess = JourneyProfileSuccess(
          contractVersion: 'JOURNEY_PROFILE_V1',
          requestId: '01J00000000000000000000000',
          queryId: 'q-1',
          calculatedAt: DateTime.parse('2026-08-11T08:50:00Z'),
          validUntil: DateTime.parse('2026-08-11T09:50:00Z'),
          temporalQuery: JourneyDepartBetweenQuery(
            earliestReadyAt: DateTime.parse('2026-08-11T09:00:00Z'),
            latestReadyAt: DateTime.parse('2026-08-11T10:00:00Z'),
          ),
          journeys: const [],
          sourceIdentity: null,
        );
        final emptySearch = emptySuccess.toSearchSuccess(
          timePolicy: TimePolicy.timetableRequired,
          walkingPace: WalkingPace.standard,
          mobilityProfile: MobilityProfile.standard,
          constraintMode: ConstraintMode.none,
          maxTransfers: 3,
          alternativeCount: 3,
        );
        expect(emptySearch.journeys.isEmpty, isTrue);
        expect(
          emptySearch.effectiveDepartureTime,
          DateTime.parse('2026-08-11T08:50:00Z'),
        );
        expect(emptySearch.sourceIdentity.routeBundleId, 'profile-bundle');

        // Error branches in fromJson
        expect(
          () => JourneyProfileSuccess.fromJson(
            Map<String, Object?>.from(successMap)
              ..['contractVersion'] = 'WRONG_V2',
          ),
          throwsFormatException,
        );
        expect(
          () => JourneyProfileSuccess.fromJson(
            Map<String, Object?>.from(successMap)..['temporalQuery'] = 'bad',
          ),
          throwsFormatException,
        );
        expect(
          () => JourneyProfileSuccess.fromJson(
            Map<String, Object?>.from(successMap)..['journeys'] = 'bad',
          ),
          throwsFormatException,
        );
        expect(
          () => JourneyProfileSuccess.fromJson(
            Map<String, Object?>.from(successMap)..['journeys'] = ['bad'],
          ),
          throwsFormatException,
        );
      },
    );
  });
}
