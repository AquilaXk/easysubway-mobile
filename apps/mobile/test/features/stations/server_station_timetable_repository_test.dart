import 'package:easysubway_mobile/features/journey/journey_session_provider.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart'
    as contract;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11);

  test(
    'NEXT_DEPARTURES rollover accepts exact next service-day instants',
    () async {
      final journey = _FakeJourneyRepository(
        timetable: _success(
          selector: contract.StationTimetableNextDeparturesSelector(
            asOf: now,
            horizonDays: 1,
          ),
          departures: [
            _departure('2026-08-11', 86340, '2026-08-11T14:59:00Z'),
            _departure('2026-08-12', 60, '2026-08-11T15:01:00Z'),
          ],
          now: now,
        ),
        now: now,
      );
      final repository = _repository(journey, now: now);

      final timetable = await repository.loadNextStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        asOf: now,
      );

      expect(journey.searchCalls, 1);
      expect(timetable.directions.single.departures, hasLength(2));
    },
  );

  test(
    '401 invalidates the shared session and never retries that timetable call',
    () async {
      final journey = _FakeJourneyRepository(
        failure: _sessionRejected(now),
        timetable: _success(
          selector: contract.StationTimetableNextDeparturesSelector(
            asOf: now,
            horizonDays: 1,
          ),
          departures: [_departure('2026-08-11', 90000, '2026-08-11T16:00:00Z')],
          now: now,
        ),
        now: now,
      );
      final repository = _repository(journey, now: now);

      await expectLater(
        repository.loadNextStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          asOf: now,
        ),
        throwsA(isA<StationTimetableUnavailable>()),
      );
      expect(journey.issueCalls, 1);
      expect(journey.searchCalls, 1);
    },
  );

  test(
    'empty departure directions map to an explicit empty timetable',
    () async {
      final journey = _FakeJourneyRepository(
        timetable: _success(
          selector: contract.StationTimetableNextDeparturesSelector(
            asOf: now,
            horizonDays: 1,
          ),
          departures: const [],
          now: now,
        ),
        now: now,
      );

      final timetable = await _repository(journey, now: now)
          .loadNextStationTimetable(
            stationId: 'station-sadang',
            lineId: 'seoul-4',
            asOf: now,
          );

      expect(timetable.isAvailable, isFalse);
      expect(timetable.directions, isEmpty);
    },
  );

  test('empty direction groups map to an explicit empty timetable', () async {
    final journey = _FakeJourneyRepository(
      timetable: _success(
        selector: contract.StationTimetableNextDeparturesSelector(
          asOf: now,
          horizonDays: 1,
        ),
        departures: const [],
        directionGroups: const [],
        now: now,
      ),
      now: now,
    );

    final timetable = await _repository(journey, now: now)
        .loadNextStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          asOf: now,
        );

    expect(timetable.isAvailable, isFalse);
    expect(timetable.directions, isEmpty);
  });

  test(
    'session or attestor failure is a typed timetable unavailable result',
    () async {
      final sessionFailure = _FakeJourneyRepository(
        issueFailure: JourneyTransportFailure(
          contract.JourneyOperation.issueJourneySession,
          StateError('session unavailable'),
        ),
        now: now,
      );
      final attestorFailure = _FakeJourneyRepository(now: now);

      await expectLater(
        _repository(sessionFailure, now: now).loadNextStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          asOf: now,
        ),
        throwsA(isA<StationTimetableUnavailable>()),
      );
      await expectLater(
        _repository(
          attestorFailure,
          now: now,
          attestor: _ThrowingAttestor(),
        ).loadNextStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          asOf: now,
        ),
        throwsA(isA<StationTimetableUnavailable>()),
      );
      expect(sessionFailure.issueCalls, 1);
      expect(attestorFailure.issueCalls, 0);
    },
  );

  test(
    'server FormatException은 그 사유를 가진 typed timetable unavailable로 닫는다',
    () async {
      final journey = _FakeJourneyRepository(
        failure: const FormatException('malformed server timetable'),
        now: now,
      );

      await expectLater(
        _repository(journey, now: now).loadStationTimetableForDate(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          date: now,
        ),
        throwsA(
          isA<StationTimetableUnavailable>().having(
            (failure) => failure.reason,
            'reason',
            'malformed server timetable',
          ),
        ),
      );
    },
  );

  test('day type와 service date selector는 KST date로 server에 전달한다', () async {
    final journey = _FakeJourneyRepository(
      timetable: _success(
        selector: contract.StationTimetableDayTypeSelector(
          dayType: contract.StationTimetableDayType.saturday,
          referenceDate: contract.JourneyDate.parse('2026-08-11'),
        ),
        departures: const [],
        now: now,
      ),
      now: now,
    );
    await _repository(journey, now: now).loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.saturday,
      referenceDate: DateTime.utc(2026, 8, 10, 15),
    );
    final serviceDateJourney = _FakeJourneyRepository(
      timetable: _success(
        selector: contract.StationTimetableServiceDateSelector(
          contract.JourneyDate.parse('2026-08-11'),
        ),
        departures: const [],
        now: now,
      ),
      now: now,
    );
    await _repository(serviceDateJourney, now: now).loadStationTimetableForDate(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      date: DateTime.utc(2026, 8, 10, 15),
    );

    expect(journey.searchCalls, 1);
    expect(serviceDateJourney.searchCalls, 1);
  });

  test('sunday-holiday day type은 server selector와 응답에 대칭으로 보존한다', () async {
    final selector = contract.StationTimetableDayTypeSelector(
      dayType: contract.StationTimetableDayType.sundayHoliday,
      referenceDate: contract.JourneyDate.parse('2026-08-16'),
    );
    final journey = _FakeJourneyRepository(
      timetable: _success(
        selector: selector,
        departures: const [],
        now: now,
        resolvedDayType: contract.StationTimetableDayType.sundayHoliday,
      ),
      now: now,
    );

    final timetable = await _repository(journey, now: now).loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.sundayHoliday,
      referenceDate: DateTime.utc(2026, 8, 15, 15),
    );

    expect(timetable.dayType, StationTimetableDayType.sundayHoliday);
    expect(journey.searchCalls, 1);
  });

  test('허용 범위를 벗어난 service-day seconds는 typed unavailable로 닫는다', () async {
    final journey = _FakeJourneyRepository(
      timetable: _success(
        selector: contract.StationTimetableNextDeparturesSelector(
          asOf: now,
          horizonDays: 1,
        ),
        departures: [_departure('2026-08-11', 108000, '2026-08-12T21:00:00Z')],
        now: now,
      ),
      now: now,
    );

    await expectLater(
      _repository(journey, now: now).loadNextStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        asOf: now,
      ),
      throwsA(isA<StationTimetableUnavailable>()),
    );
  });

  test(
    'invalid next-departures horizon은 server 요청 전에 typed unavailable이다',
    () async {
      final journey = _FakeJourneyRepository(now: now);
      expect(
        () => _repository(journey, now: now).loadNextStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          asOf: now,
          horizonDays: 0,
        ),
        throwsA(isA<StationTimetableUnavailable>()),
      );
      expect(journey.searchCalls, 0);
    },
  );
}

ServerStationTimetableRepository _repository(
  _FakeJourneyRepository journey, {
  required DateTime now,
  JourneyV3IntegrityAttestor? attestor,
}) => ServerStationTimetableRepository(
  journeyRepository: journey,
  sessionProvider: JourneySessionProvider(
    repository: journey,
    attestor: attestor ?? const _Attestor(),
    now: () => now,
    nonceGenerator: (_) => 'AAAAAAAAAAAAAAAAAAAAAA',
  ),
  now: () => now,
);

contract.StationTimetableDeparture _departure(
  String serviceDate,
  int seconds,
  String departureAt,
) => contract.StationTimetableDeparture(
  serviceDate: contract.JourneyDate.parse(serviceDate),
  secondsFromServiceDayStart: seconds,
  departureAt: DateTime.parse(departureAt),
  servicePattern: contract.StationTimetableServicePattern.local,
  serviceClass: contract.StationTimetableServiceClass.subway,
);

contract.StationTimetableSearchSuccess _success({
  required contract.StationTimetableSelector selector,
  required List<contract.StationTimetableDeparture> departures,
  required DateTime now,
  List<contract.StationTimetableDirectionGroup>? directionGroups,
  contract.StationTimetableDayType resolvedDayType =
      contract.StationTimetableDayType.weekday,
}) => contract.StationTimetableSearchSuccess(
  contractVersion:
      contract.StationTimetableSearchContractVersion.stationTimetableSearchV3,
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  selector: selector,
  resolvedDayType: resolvedDayType,
  serviceTimezone: contract.StationTimetableServiceTimezone.asiaSeoul,
  directionGroups:
      directionGroups ??
      [
        contract.StationTimetableDirectionGroup(
          directionName: '당고개 방면',
          departures: departures,
        ),
      ],
  sourceIdentity: contract.StationTimetableSourceIdentity(
    timetableArtifactId: 'timetable-v3',
    timetableSnapshotSha256: 'a' * 64,
    canonicalStationVersion: 'station-v1',
    canonicalStationSetSha256: 'b' * 64,
    sourceLineageSha256: 'c' * 64,
    evidenceHash: 'd' * 64,
    freshUntil: now.add(const Duration(minutes: 10)),
  ),
);

JourneyRejectedFailure _sessionRejected(DateTime now) {
  const operation = contract.JourneyOperation.searchStationTimetables;
  const statusCode = 401;
  const code = contract.JourneyErrorCode.routeSessionRequired;
  return JourneyRejectedFailure(
    operation,
    statusCode: statusCode,
    error: contract.JourneyV3Error(
      contractVersion: contract.JourneyErrorContractVersion.journeyErrorV1,
      requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
      code: code,
      retryable: false,
      occurredAt: now,
    ),
    disposition: contract.JourneyErrorDispositions.lookup(
      operation,
      statusCode,
      code,
    ),
  );
}

class _FakeJourneyRepository implements JourneyRepository {
  _FakeJourneyRepository({
    this.timetable,
    this.failure,
    this.issueFailure,
    required this.now,
  });

  final contract.StationTimetableSearchSuccess? timetable;
  final Object? failure;
  final Object? issueFailure;
  final DateTime now;
  int issueCalls = 0;
  int searchCalls = 0;

  @override
  Future<contract.JourneySessionResponse> issueSession(
    contract.JourneySessionRequest request,
  ) async {
    issueCalls++;
    if (issueFailure != null) throw issueFailure!;
    return contract.JourneySessionResponse(
      token: 'session-token',
      scope: contract.JourneySessionScope.journeyV3,
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<contract.JourneySearchSuccess> searchJourneys(
    contract.JourneySearchRequest request, {
    required String sessionToken,
  }) => throw UnimplementedError();

  @override
  Future<contract.StationTimetableSearchSuccess> searchStationTimetables(
    contract.StationTimetableSearchRequest request, {
    required String sessionToken,
  }) async {
    searchCalls++;
    if (failure != null) throw failure!;
    return timetable!;
  }
}

class _Attestor implements JourneyV3IntegrityAttestor {
  const _Attestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class _ThrowingAttestor implements JourneyV3IntegrityAttestor {
  @override
  Future<String> attest(String requestHash) => throw StateError('attestor');
}
