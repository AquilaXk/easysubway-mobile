import 'package:easysubway_mobile/features/journey/journey_session_provider.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_profile_models.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
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
        throwsA(
          isA<ServerConnectionException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
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
    'session or attestor failure is a typed server connection exception',
    () async {
      final sessionFailure = _FakeJourneyRepository(
        issueFailure: _rejected(
          statusCode: 403,
          code: contract.JourneyErrorCode.routeSessionAttestationRejected,
          operation: contract.JourneyOperation.issueJourneySession,
          now: now,
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
        throwsA(
          isA<ServerConnectionException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
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
        throwsA(
          isA<ServerConnectionException>().having(
            (e) => e.message,
            'message',
            contains('Journey session issuance failed'),
          ),
        ),
      );
      expect(sessionFailure.issueCalls, 1);
      expect(attestorFailure.issueCalls, 0);
    },
  );

  test(
    'server FormatException은 데이터 무결성 위반 ServerConnectionException으로 닫는다',
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
          isA<ServerConnectionException>().having(
            (failure) => failure.message,
            'message',
            contains(
              'Station timetable data integrity violation: malformed server timetable',
            ),
          ),
        ),
      );
    },
  );

  // #437 리뷰 F1: 요일 탭은 요일 종류(DAY_TYPE)를 보내지 않는다. 토요일 시간표가
  // 없는 기관에 DAY_TYPE=SATURDAY를 보내면 400이다. 탭 요일에 해당하는 가장 가까운
  // 날짜를 SERVICE_DATE로 보내고, 서버가 판정한 resolvedDayType을 그대로 쓴다.
  group('요일 탭은 날짜로 조회하고 서버가 판정한 요일 종류를 쓴다', () {
    Future<(StationTimetable, _FakeJourneyRepository)> load(
      StationTimetableDayType dayType,
      DateTime referenceDate,
      String expectedServiceDate,
      contract.StationTimetableDayType resolved,
    ) async {
      final journey = _FakeJourneyRepository(
        timetable: _success(
          selector: contract.StationTimetableServiceDateSelector(
            contract.JourneyDate.parse(expectedServiceDate),
          ),
          departures: const [],
          now: now,
          resolvedDayType: resolved,
        ),
        now: now,
      );
      final timetable = await _repository(journey, now: now)
          .loadStationTimetable(
            stationId: 'station-sadang',
            lineId: 'seoul-4',
            dayType: dayType,
            referenceDate: referenceDate,
          );
      return (timetable, journey);
    }

    test('토요일 휴일 달력 기관: 토요일 탭은 다음 토요일 날짜로 묻고 공휴일 시간표를 받는다', () async {
      // 2026-08-11(화) KST 기준 다음 토요일은 2026-08-15다.
      final (timetable, journey) = await load(
        StationTimetableDayType.saturday,
        DateTime.utc(2026, 8, 10, 15),
        '2026-08-15',
        contract.StationTimetableDayType.sundayHoliday,
      );

      final selector = journey.requests.single.selector;
      expect(selector, isA<contract.StationTimetableServiceDateSelector>());
      expect(
        (selector as contract.StationTimetableServiceDateSelector).serviceDate
            .toString(),
        '2026-08-15',
      );
      expect(timetable.dayType, StationTimetableDayType.sundayHoliday);
      expect(timetable.serviceDate, '2026-08-15');
    });

    test('공휴일 탭은 다음 일요일, 평일 탭은 다음 평일 날짜로 묻는다', () async {
      final (holiday, holidayJourney) = await load(
        StationTimetableDayType.sundayHoliday,
        DateTime.utc(2026, 8, 15, 15), // 2026-08-16(일) KST
        '2026-08-16',
        contract.StationTimetableDayType.sundayHoliday,
      );
      final (weekday, weekdayJourney) = await load(
        StationTimetableDayType.weekday,
        DateTime.utc(2026, 8, 14, 15), // 2026-08-15(토) KST
        '2026-08-17',
        contract.StationTimetableDayType.weekday,
      );

      expect(holidayJourney.requests.single.selector.toJson(), {
        'kind': 'SERVICE_DATE',
        'serviceDate': '2026-08-16',
      });
      expect(holiday.dayType, StationTimetableDayType.sundayHoliday);
      expect(weekdayJourney.requests.single.selector.toJson(), {
        'kind': 'SERVICE_DATE',
        'serviceDate': '2026-08-17',
      });
      expect(weekday.dayType, StationTimetableDayType.weekday);
    });

    test(
      '400 INVALID_JOURNEY_REQUEST와 404 TIMETABLE_NOT_COVERED는 코드를 담은 시간표 사용 불가다',
      () async {
        for (final (status, code) in [
          (400, contract.JourneyErrorCode.invalidJourneyRequest),
          (404, contract.JourneyErrorCode.timetableNotCovered),
        ]) {
          final journey = _FakeJourneyRepository(
            failure: _rejected(statusCode: status, code: code, now: now),
            now: now,
          );
          await expectLater(
            _repository(journey, now: now).loadStationTimetable(
              stationId: 'station-sadang',
              lineId: 'seoul-4',
              dayType: StationTimetableDayType.saturday,
              referenceDate: DateTime.utc(2026, 8, 10, 15),
            ),
            throwsA(
              isA<StationTimetableUnavailable>().having(
                (e) => e.reason,
                'reason',
                code.wire,
              ),
            ),
          );
        }
      },
    );
  });

  test(
    '허용 범위를 벗어난 service-day seconds는 무결성 위반 ServerConnectionException으로 닫는다',
    () async {
      final journey = _FakeJourneyRepository(
        timetable: _success(
          selector: contract.StationTimetableNextDeparturesSelector(
            asOf: now,
            horizonDays: 1,
          ),
          departures: [
            _departure('2026-08-11', 108000, '2026-08-12T21:00:00Z'),
          ],
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
        throwsA(
          isA<ServerConnectionException>().having(
            (e) => e.message,
            'message',
            contains('Station timetable departure ordering mismatch'),
          ),
        ),
      );
    },
  );

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

  test('서버 5xx 장애 시 ServerConnectionException을 던진다', () async {
    final journey = _FakeJourneyRepository(
      failure: _rejected(
        statusCode: 503,
        code: contract.JourneyErrorCode.timetableUnavailable,
        now: now,
      ),
      now: now,
    );

    await expectLater(
      _repository(journey, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      throwsA(
        allOf(
          isA<ServerConnectionException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
          isNot(isA<ServerUnreachableException>()),
        ),
      ),
    );
  });

  test('서버 프로토콜 오류 시 ServerConnectionException을 던진다', () async {
    final journey = _FakeJourneyRepository(
      failure: JourneyProtocolFailure(
        contract.JourneyOperation.searchStationTimetables,
        statusCode: 502,
        cause: 'Bad Gateway',
      ),
      now: now,
    );

    await expectLater(
      _repository(journey, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      throwsA(
        isA<ServerConnectionException>().having(
          (e) => e.statusCode,
          'statusCode',
          502,
        ),
      ),
    );
  });

  test(
    '단순 미지원 역(TIMETABLE_NOT_COVERED) 시 StationTimetableUnavailable을 던진다',
    () async {
      final journey = _FakeJourneyRepository(
        failure: _rejected(
          statusCode: 404,
          code: contract.JourneyErrorCode.timetableNotCovered,
          now: now,
        ),
        now: now,
      );

      await expectLater(
        _repository(journey, now: now).loadStationTimetable(
          stationId: 'station-unknown',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: now,
        ),
        throwsA(isA<StationTimetableUnavailable>()),
      );
    },
  );

  test('네트워크 전송 오류 시 ServerConnectionException을 던진다', () async {
    final journey = _FakeJourneyRepository(
      failure: JourneyTransportFailure(
        contract.JourneyOperation.searchStationTimetables,
        'SocketException: Connection reset by peer',
      ),
      now: now,
    );

    await expectLater(
      _repository(journey, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      // #437 리뷰 F2: 네트워크에 닿지 못한 경우만 로컬 시간표 전환 대상이다.
      throwsA(isA<ServerUnreachableException>()),
    );
  });

  test(
    '세션 발급 중 네트워크 전송 오류(JourneyTransportFailure) 시 ServerConnectionException을 던진다',
    () async {
      final sessionFailure = _FakeJourneyRepository(
        issueFailure: JourneyTransportFailure(
          contract.JourneyOperation.issueJourneySession,
          'SocketException: Failed host lookup',
        ),
        now: now,
      );

      await expectLater(
        _repository(sessionFailure, now: now).loadStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: now,
        ),
        throwsA(isA<ServerUnreachableException>()),
      );
    },
  );

  test('세션 발급 중 서버 503 장애 시 ServerConnectionException을 던진다', () async {
    final sessionFailure = _FakeJourneyRepository(
      issueFailure: _rejected(
        statusCode: 503,
        code: contract.JourneyErrorCode.routeSessionAttestationUnavailable,
        operation: contract.JourneyOperation.issueJourneySession,
        now: now,
      ),
      now: now,
    );

    await expectLater(
      _repository(sessionFailure, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      throwsA(
        allOf(
          isA<ServerConnectionException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
          isNot(isA<ServerUnreachableException>()),
        ),
      ),
    );
  });

  test(
    '세션 발급 중 프로토콜 오류(JourneyProtocolFailure) 시 ServerConnectionException을 던진다',
    () async {
      final sessionFailure = _FakeJourneyRepository(
        issueFailure: JourneyProtocolFailure(
          contract.JourneyOperation.issueJourneySession,
          statusCode: 502,
          cause: const FormatException('Bad Gateway payload'),
        ),
        now: now,
      );

      await expectLater(
        _repository(sessionFailure, now: now).loadStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: now,
        ),
        throwsA(
          isA<ServerConnectionException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having(
                (e) => e.message,
                'message',
                contains('Journey protocol failure: issueJourneySession'),
              ),
        ),
      );
    },
  );

  test('서버 403 거절 시 ServerConnectionException을 던진다', () async {
    final journey = _FakeJourneyRepository(
      failure: _customRejected(statusCode: 403, now: now),
      now: now,
    );

    await expectLater(
      _repository(journey, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      throwsA(
        isA<ServerConnectionException>().having(
          (e) => e.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });

  test('서버 429 레이트 리밋 시 ServerConnectionException을 던진다', () async {
    final journey = _FakeJourneyRepository(
      failure: _rejected(
        statusCode: 429,
        code: contract.JourneyErrorCode.routeRateLimited,
        now: now,
      ),
      now: now,
    );

    await expectLater(
      _repository(journey, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      throwsA(
        isA<ServerConnectionException>().having(
          (e) => e.statusCode,
          'statusCode',
          429,
        ),
      ),
    );
  });

  test('세션 발급 중 429 레이트 리밋 시 ServerConnectionException을 던진다', () async {
    final sessionFailure = _FakeJourneyRepository(
      issueFailure: _customRejected(
        statusCode: 429,
        operation: contract.JourneyOperation.issueJourneySession,
        now: now,
      ),
      now: now,
    );

    await expectLater(
      _repository(sessionFailure, now: now).loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: now,
      ),
      throwsA(
        isA<ServerConnectionException>().having(
          (e) => e.statusCode,
          'statusCode',
          429,
        ),
      ),
    );
  });

  test(
    '세션 응답의 유효기간 검증 실패(JourneySessionInvalid) 시 ServerConnectionException을 던진다',
    () async {
      final invalidSessionJourney = _FakeJourneyRepository(
        sessionResponse: contract.JourneySessionResponse(
          token: 'invalid-token',
          issuedAt: now,
          expiresAt: now.subtract(const Duration(minutes: 1)),
          scope: contract.JourneySessionScope.journeyV3,
        ),
        now: now,
      );

      await expectLater(
        _repository(invalidSessionJourney, now: now).loadStationTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: now,
        ),
        throwsA(
          isA<ServerConnectionException>().having(
            (e) => e.message,
            'message',
            contains('Journey session is invalid or unavailable.'),
          ),
        ),
      );
    },
  );

  test('앱 역 검색 저장소의 역 상세 이름으로 역 이름을 붙인다', () async {
    final resolver = stationDetailNameResolver(_StationDetailRepository());

    expect(await resolver('station-yeoksam'), '역삼');
    await expectLater(resolver('station-unknown'), throwsA(isA<StateError>()));
  });

  group('다음 정차역 기준 방면 묶음(#437)', () {
    contract.StationTimetableSelector selector() =>
        contract.StationTimetableServiceDateSelector(
          contract.JourneyDate.parse('2026-08-11'),
        );
    Future<StationTimetable> load(
      List<contract.StationTimetableDirectionGroup> groups, {
      Future<String> Function(String stationId) stationName = _catalogName,
    }) =>
        _repository(
          _FakeJourneyRepository(
            timetable: _success(
              selector: selector(),
              departures: const [],
              directionGroups: groups,
              now: now,
            ),
            now: now,
          ),
          now: now,
          stationName: stationName,
        ).loadStationTimetableForDate(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          date: now,
        );

    test('2호선 강남 형태: 종착이 같아도 다음 정차역으로 두 방면을 만든다', () async {
      final timetable = await load([
        contract.StationTimetableDirectionGroup(
          nextStationId: 'station-yeoksam',
          directionName: null,
          departures: [
            _departure(
              '2026-08-11',
              32400,
              '2026-08-11T00:00:00Z',
              terminalStationId: 'station-seongsu',
            ),
          ],
        ),
        contract.StationTimetableDirectionGroup(
          nextStationId: 'station-gyodae',
          directionName: null,
          departures: [
            _departure(
              '2026-08-11',
              32460,
              '2026-08-11T00:01:00Z',
              terminalStationId: 'station-seongsu',
            ),
          ],
        ),
      ]);

      expect(timetable.directions.map((d) => d.name), ['역삼 방면', '교대 방면']);
      expect(
        timetable.directions.map((d) => d.departures.single.directionName),
        ['역삼 방면', '교대 방면'],
      );
      expect(timetable.directions.map((d) => d.departures.single.destination), [
        '성수',
        '성수',
      ]);
    });

    test('인천 형태: 원천 방면 이름이 있어도 라벨은 다음 정차역 이름이다', () async {
      final timetable = await load([
        contract.StationTimetableDirectionGroup(
          nextStationId: 'station-incheon-terminal',
          directionName: '송도달빛축제공원행',
          departures: [
            _departure(
              '2026-08-11',
              32400,
              '2026-08-11T00:00:00Z',
              terminalStationId: 'station-songdo-moonlight',
            ),
          ],
        ),
      ]);

      expect(timetable.directions.single.name, '인천터미널 방면');
      expect(
        timetable.directions.single.departures.single.destination,
        '송도달빛축제공원',
      );
    });

    test('카탈로그에 없는 다음 정차역·종착역은 추정 이름 없이 시간표 사용 불가다', () async {
      for (final groups in [
        [
          contract.StationTimetableDirectionGroup(
            nextStationId: 'station-unknown',
            directionName: '어딘가 방면',
            departures: [
              _departure('2026-08-11', 32400, '2026-08-11T00:00:00Z'),
            ],
          ),
        ],
        [
          contract.StationTimetableDirectionGroup(
            nextStationId: 'station-yeoksam',
            directionName: null,
            departures: [
              _departure(
                '2026-08-11',
                32400,
                '2026-08-11T00:00:00Z',
                terminalStationId: 'station-unknown',
              ),
            ],
          ),
        ],
      ]) {
        await expectLater(
          load(groups),
          throwsA(
            isA<StationTimetableUnavailable>().having(
              (e) => e.reason,
              'reason',
              'TIMETABLE_STATION_NAME_UNAVAILABLE',
            ),
          ),
        );
      }
    });

    test('같은 다음 정차역 묶음이 두 번 오면 무결성 오류다', () async {
      contract.StationTimetableDirectionGroup group(String name) =>
          contract.StationTimetableDirectionGroup(
            nextStationId: 'station-yeoksam',
            directionName: name,
            departures: [
              _departure(
                '2026-08-11',
                32400,
                '2026-08-11T00:00:00Z',
                terminalStationId: 'station-seongsu',
              ),
            ],
          );

      await expectLater(
        load([group('가 방면'), group('나 방면')]),
        throwsA(isA<ServerConnectionException>()),
      );
    });
  });
}

// 앱 카탈로그 역 이름(테스트용).
const _catalogNames = <String, String>{
  'station-chongshin': '총신대입구(이수)',
  'station-danggogae': '당고개',
  'station-yeoksam': '역삼',
  'station-gyodae': '교대',
  'station-seongsu': '성수',
  'station-incheon-terminal': '인천터미널',
  'station-gyeyang': '계양',
  'station-songdo-moonlight': '송도달빛축제공원',
};

Future<String> _catalogName(String stationId) async {
  final name = _catalogNames[stationId];
  if (name == null) throw StateError('station $stationId is not in catalog');
  return name;
}

ServerStationTimetableRepository _repository(
  _FakeJourneyRepository journey, {
  required DateTime now,
  JourneyV3IntegrityAttestor? attestor,
  Future<String> Function(String stationId) stationName = _catalogName,
}) => ServerStationTimetableRepository(
  journeyRepository: journey,
  stationNameResolver: stationName,
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
  String departureAt, {
  String terminalStationId = 'station-danggogae',
}) => contract.StationTimetableDeparture(
  serviceDate: contract.JourneyDate.parse(serviceDate),
  secondsFromServiceDayStart: seconds,
  departureAt: DateTime.parse(departureAt),
  servicePattern: contract.StationTimetableServicePattern.local,
  serviceClass: contract.StationTimetableServiceClass.subway,
  terminalStationId: terminalStationId,
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
          nextStationId: 'station-chongshin',
          directionName: null,
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

JourneyRejectedFailure _rejected({
  required int statusCode,
  required contract.JourneyErrorCode code,
  required DateTime now,
  contract.JourneyOperation operation =
      contract.JourneyOperation.searchStationTimetables,
  bool retryable = false,
}) {
  return JourneyRejectedFailure(
    operation,
    statusCode: statusCode,
    error: contract.JourneyV3Error(
      contractVersion: contract.JourneyErrorContractVersion.journeyErrorV1,
      requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
      code: code,
      retryable: retryable,
      occurredAt: now,
    ),
    disposition: contract.JourneyErrorDispositions.lookup(
      operation,
      statusCode,
      code,
    ),
  );
}

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

JourneyRejectedFailure _customRejected({
  required int statusCode,
  required DateTime now,
  contract.JourneyOperation operation =
      contract.JourneyOperation.searchStationTimetables,
}) {
  return JourneyRejectedFailure(
    operation,
    statusCode: statusCode,
    error: contract.JourneyV3Error(
      contractVersion: contract.JourneyErrorContractVersion.journeyErrorV1,
      requestId: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
      code: contract.JourneyErrorCode.invalidJourneyRequest,
      retryable: false,
      occurredAt: now,
    ),
    disposition: contract.JourneyErrorDispositions.lookup(
      contract.JourneyOperation.searchStationTimetables,
      400,
      contract.JourneyErrorCode.invalidJourneyRequest,
    ),
  );
}

class _FakeJourneyRepository implements JourneyRepository {
  _FakeJourneyRepository({
    this.timetable,
    this.failure,
    this.issueFailure,
    this.sessionResponse,
    required this.now,
  });

  final contract.StationTimetableSearchSuccess? timetable;
  final Object? failure;
  final Object? issueFailure;
  final contract.JourneySessionResponse? sessionResponse;
  final DateTime now;
  int issueCalls = 0;
  int searchCalls = 0;
  final requests = <contract.StationTimetableSearchRequest>[];

  @override
  Future<contract.JourneySessionResponse> issueSession(
    contract.JourneySessionRequest request,
  ) async {
    issueCalls++;
    if (issueFailure != null) throw issueFailure!;
    if (sessionResponse != null) return sessionResponse!;
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
    requests.add(request);
    if (failure != null) throw failure!;
    return timetable!;
  }

  @override
  Future<JourneyProfileSuccess> profileJourneys(
    JourneyProfileRequest request, {
    required String sessionToken,
  }) => throw UnimplementedError();
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

class _StationDetailRepository implements StationSearchRepository {
  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    if (stationId != 'station-yeoksam') throw StateError('not in catalog');
    return StationDetail(
      id: stationId,
      nameKo: '역삼',
      nameEn: 'Yeoksam',
      region: 'seoul',
      dataQualityLevel: 'VERIFIED',
      lastVerifiedAt: '2026-08-01',
      lines: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
