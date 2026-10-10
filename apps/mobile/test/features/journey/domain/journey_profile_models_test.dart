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
    fare: const JourneyFare(
      status: JourneyFareStatus.unavailable,
      sourceSnapshotIds: <String>[],
    ),
  );
}

/// 계약(`journey-v3.openapi.yaml`)의 `JourneyProfileSourceIdentity` 필드 전체.
const _profileSourceIdentityKeys = <String>{
  'routeBundleId',
  'routeBundleGeneration',
  'routeBundleSha256',
  'timetableSnapshotId',
  'accessibilitySnapshotId',
  'realtimeSnapshotId',
};

/// 계약의 세 성공 응답(Departure/ArriveBy/LastConnection) 공통 required 키.
const _profileCommonKeys = <String>{
  'contractVersion',
  'requestId',
  'queryId',
  'calculatedAt',
  'validUntil',
  'temporalQuery',
  'serviceDays',
  'sourceIdentity',
  'algorithmIdentity',
  'frontierPolicyIdentity',
  'resourcePolicyIdentity',
  'journeys',
  'summary',
};

/// DEPART_BETWEEN 응답만 추가로 가지는 키(계약 `DepartureProfileSuccess`).
const _departureOnlyKeys = <String>{'profileSegments'};

Map<String, Object?> _profileSourceIdentityJson() => {
  'routeBundleId': 'rb-1',
  'routeBundleGeneration': 'gen-7',
  'routeBundleSha256': 'a' * 64,
  'timetableSnapshotId': 'tt-1',
  'accessibilitySnapshotId': 'acc-1',
  'realtimeSnapshotId': null,
};

/// 계약 키를 빠짐없이 가진 프로필 성공 응답. 디코더가 해석하지 않는
/// 정책·요약 필드는 존재만 검사하므로 빈 객체로 둔다.
Map<String, Object?> _profileJson({
  required Map<String, Object?> candidate,
  Map<String, Object?>? temporalQuery,
}) {
  final temporal =
      temporalQuery ??
      {
        'kind': 'DEPART_BETWEEN',
        'earliestReadyAt': '2026-08-11T09:00:00.000Z',
        'latestReadyAt': '2026-08-11T10:00:00.000Z',
      };
  return {
    'contractVersion': 'JOURNEY_PROFILE_V1',
    'requestId': '01J00000000000000000000000',
    'queryId': 'q-1',
    'calculatedAt': '2026-08-11T08:50:00.000Z',
    'validUntil': '2026-08-11T09:50:00.000Z',
    'temporalQuery': temporal,
    'serviceDays': [
      {
        'serviceDate': '2026-08-11',
        'serviceTimezone': 'Asia/Seoul',
        'serviceDayCutoff': '03:00',
      },
    ],
    'sourceIdentity': _profileSourceIdentityJson(),
    'algorithmIdentity': <String, Object?>{},
    'frontierPolicyIdentity': <String, Object?>{},
    'resourcePolicyIdentity': <String, Object?>{},
    'journeys': [candidate],
    if (temporal['kind'] == 'DEPART_BETWEEN') 'profileSegments': <Object?>[],
    'summary': <String, Object?>{},
  };
}

JourneySearchSuccess _convert(Map<String, Object?> json) =>
    JourneyProfileSuccess.fromJson(json).toSearchSuccess(
      timePolicy: TimePolicy.timetableRequired,
      walkingPace: WalkingPace.standard,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 3,
      alternativeCount: 3,
    );

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

    test('검색 결과의 serviceDayCutoff는 프로필 응답 serviceDays에서 가져온다(#438 리뷰 F3)', () {
      Map<String, Object?> profile(Object? serviceDays) => {
        ..._profileJson(candidate: validCandidateMap)..remove('serviceDays'),
        'serviceDays': ?serviceDays,
      };
      Map<String, Object?> day(String date, String cutoff) => {
        'serviceDate': date,
        'serviceTimezone': 'Asia/Seoul',
        'serviceDayCutoff': cutoff,
      };
      final convert = _convert;

      expect(
        convert(
          profile([day('2026-08-11', '03:00'), day('2026-08-12', '03:00')]),
        ).serviceDayCutoff,
        '03:00',
      );
      for (final invalid in <Object?>[
        null,
        const <Object?>[],
        [day('2026-08-11', '03:00'), day('2026-08-12', '04:00')],
        [day('2026-08-11', '3시')],
        [
          {...day('2026-08-11', '03:00'), 'extra': true},
        ],
      ]) {
        expect(
          () => convert(profile(invalid)),
          throwsFormatException,
          reason: '$invalid',
        );
      }
    });

    test(
      'JourneyProfileSuccess round-trips and converts to search success',
      () {
        final successMap = _profileJson(candidate: validCandidateMap);

        final success = JourneyProfileSuccess.fromJson(successMap);
        expect(success.contractVersion, 'JOURNEY_PROFILE_V1');
        expect(success.requestId, '01J00000000000000000000000');
        expect(success.queryId, 'q-1');
        expect(success.journeys.length, 1);
        expect(success.journeyList.length, 1);
        expect(success.sourceIdentity.routeBundleId, 'rb-1');
        expect(success.sourceIdentity.routeBundleGeneration, 'gen-7');

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

        // 후보가 없어도 서버가 준 식별값을 그대로 쓴다
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
          serviceDayCutoff: '03:00',
          sourceIdentity: JourneyProfileSourceIdentity.fromJson(
            _profileSourceIdentityJson(),
          ),
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
        expect(emptySearch.sourceIdentity.routeBundleId, 'rb-1');

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

    test('검색 결과 sourceIdentity는 서버 응답 값 그대로이고 placeholder가 없다(#442)', () {
      final converted = _convert(_profileJson(candidate: validCandidateMap));
      final source = converted.sourceIdentity;
      expect(source.routeBundleId, 'rb-1');
      expect(source.routeBundleSha256, 'a' * 64);
      expect(source.timetableSnapshotId, 'tt-1');
      expect(source.accessibilitySnapshotId, 'acc-1');
      expect(source.realtimeSnapshotId, isNull);
      expect(source.routeBundleId, isNot('profile-bundle'));
      expect(source.routeBundleSha256, isNot('0' * 64));
      expect(source.timetableSnapshotId, isNot('profile-timetable'));
      expect(source.accessibilitySnapshotId, isNot('profile-accessibility'));
    });

    test('sourceIdentity가 없거나 계약 키와 다르면 거부한다(#442)', () {
      final base = _profileJson(candidate: validCandidateMap);
      expect(
        () => JourneyProfileSuccess.fromJson(
          Map.of(base)..remove('sourceIdentity'),
        ),
        throwsFormatException,
      );
      for (final key in _profileSourceIdentityKeys) {
        final missing = _profileSourceIdentityJson()..remove(key);
        expect(
          () => JourneyProfileSuccess.fromJson(
            Map.of(base)..['sourceIdentity'] = missing,
          ),
          throwsFormatException,
          reason: 'missing $key',
        );
      }
      final extra = _profileSourceIdentityJson()..['unknown'] = 'x';
      expect(
        () => JourneyProfileSuccess.fromJson(
          Map.of(base)..['sourceIdentity'] = extra,
        ),
        throwsFormatException,
      );
    });

    test('realtimeSnapshotId가 있으면 그대로 옮기고 빈 값은 거부한다(#442)', () {
      final withRealtime = _profileSourceIdentityJson()
        ..['realtimeSnapshotId'] = 'rt-1';
      final converted = JourneyProfileSourceIdentity.fromJson(
        withRealtime,
      ).toSearchSourceIdentity();
      expect(converted.realtimeSnapshotId, 'rt-1');
      expect(
        () => JourneyProfileSourceIdentity.fromJson(
          _profileSourceIdentityJson()..['realtimeSnapshotId'] = '  ',
        ),
        throwsFormatException,
      );
    });

    test('프로필 응답 최상위 키 집합은 계약과 정확히 같아야 한다(#442)', () {
      final temporalByKind = <String, Map<String, Object?>>{
        'DEPART_BETWEEN': {
          'kind': 'DEPART_BETWEEN',
          'earliestReadyAt': '2026-08-11T09:00:00.000Z',
          'latestReadyAt': '2026-08-11T10:00:00.000Z',
        },
        'ARRIVE_BY': {
          'kind': 'ARRIVE_BY',
          'earliestReadyAt': '2026-08-11T09:00:00.000Z',
          'arrivalDeadline': '2026-08-11T10:00:00.000Z',
        },
        'LAST_CONNECTION': {
          'kind': 'LAST_CONNECTION',
          'serviceDate': '2026-08-11',
        },
      };
      for (final entry in temporalByKind.entries) {
        final json = _profileJson(
          candidate: validCandidateMap,
          temporalQuery: entry.value,
        );
        final expected = {
          ..._profileCommonKeys,
          if (entry.key == 'DEPART_BETWEEN') ..._departureOnlyKeys,
        };
        expect(json.keys.toSet(), expected, reason: entry.key);
        expect(
          () => JourneyProfileSuccess.fromJson(json),
          returnsNormally,
          reason: entry.key,
        );
        for (final key in expected) {
          expect(
            () => JourneyProfileSuccess.fromJson(Map.of(json)..remove(key)),
            throwsFormatException,
            reason: '${entry.key} missing $key',
          );
        }
        expect(
          () => JourneyProfileSuccess.fromJson(Map.of(json)..['unknown'] = 1),
          throwsFormatException,
          reason: '${entry.key} extra key',
        );
      }
      // 계약상 DEPART_BETWEEN에만 profileSegments가 있다.
      final arrive = _profileJson(
        candidate: validCandidateMap,
        temporalQuery: temporalByKind['ARRIVE_BY'],
      )..['profileSegments'] = <Object?>[];
      expect(
        () => JourneyProfileSuccess.fromJson(arrive),
        throwsFormatException,
      );
    });
  });
}
