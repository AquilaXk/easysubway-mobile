import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftStationTimetableRepository', () {
    late CatalogDatabase database;
    late DriftStationTimetableRepository repository;

    setUp(() async {
      database = CatalogDatabase.memory();
      await database.seedBaselineIfEmpty();

      // Seed Saturday and Sunday/Holiday calendars
      await database.customStatement('''
        INSERT INTO service_calendars (service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date)
        VALUES ('cal-sat', 0, 0, 0, 0, 0, 1, 0, '20260101', '20261231'),
               ('cal-sun', 0, 0, 0, 0, 0, 0, 1, '20260101', '20261231')
      ''');
      await database.customStatement('''
        INSERT INTO transit_routes (id, line_id, direction_name)
        VALUES ('route-sat', 'seoul-4', '오이도 방면'),
               ('route-sun', 'seoul-4', '진접 방면')
      ''');
      await database.customStatement('''
        INSERT INTO transit_trips (id, route_id, service_id, service_class, service_pattern)
        VALUES ('trip-sat-1', 'route-sat', 'cal-sat', 'SUBWAY', 'LOCAL'),
               ('trip-sun-1', 'route-sun', 'cal-sun', 'SUBWAY', 'LOCAL')
      ''');
      await database.customStatement('''
        INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
        VALUES ('trip-sat-1', 1, 'station-sangnoksu', 'seoul-4', 36000, 36000, 0, 0),
               ('trip-sun-1', 1, 'station-sangnoksu', 'seoul-4', 40000, 40000, 0, 0)
      ''');

      repository = DriftStationTimetableRepository(database: database);
    });

    tearDown(() async {
      await database.close();
    });

    test('토요일 및 공휴일 dayType 조회가 정상 수행된다', () async {
      final sat = await repository.loadStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.saturday,
        referenceDate: DateTime.utc(2026, 9, 26),
      );
      expect(sat.isAvailable, isTrue);
      expect(sat.isOfflineFallback, isTrue);
      expect(
        sat.directions.single.departures.single.departureAt,
        DateTime.utc(2026, 9, 26, 1, 0),
      );

      final sun = await repository.loadStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.sundayHoliday,
        referenceDate: DateTime.utc(2026, 9, 27),
      );
      expect(sun.isAvailable, isTrue);
      expect(sun.isOfflineFallback, isTrue);
    });

    test('loadNextStationTimetable은 서울 벽시계 기준 시각 이후 열차만 필터링하여 반환한다', () async {
      final beforeTrain = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 26, 0, 0, 0),
      );
      expect(beforeTrain.isAvailable, isTrue);
      expect(beforeTrain.isOfflineFallback, isTrue);
      expect(beforeTrain.directions, isNotEmpty);

      final afterTrain = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 26, 2, 0, 0),
      );
      expect(afterTrain.directions, isEmpty);
      expect(afterTrain.isOfflineFallback, isTrue);
    });

    test('심야 00:15 KST에는 달력 자정이 아니라 전날 운행일(금요일·일요일) 연장 열차를 조회한다', () async {
      await database.customStatement('''
        INSERT INTO service_calendars (service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date)
        VALUES ('cal-weekday', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231')
      ''');
      await database.customStatement('''
        INSERT INTO transit_routes (id, line_id, direction_name)
        VALUES ('route-weekday', 'seoul-4', '당고개 방면')
      ''');
      await database.customStatement('''
        INSERT INTO transit_trips (id, route_id, service_id, service_class, service_pattern)
        VALUES ('trip-fri-day', 'route-weekday', 'cal-weekday', 'SUBWAY', 'LOCAL'),
               ('trip-fri-late', 'route-weekday', 'cal-weekday', 'SUBWAY', 'LOCAL'),
               ('trip-sun-late', 'route-sun', 'cal-sun', 'SUBWAY', 'LOCAL')
      ''');
      await database.customStatement('''
        INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
        VALUES ('trip-fri-day', 1, 'station-sangnoksu', 'seoul-4', 60000, 60000, 0, 0),
               ('trip-fri-late', 1, 'station-sangnoksu', 'seoul-4', 88200, 88200, 0, 0),
               ('trip-sun-late', 1, 'station-sangnoksu', 'seoul-4', 87600, 87600, 0, 0)
      ''');

      final saturdayMidnight = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 25, 15, 15),
      );
      expect(saturdayMidnight.dayType, StationTimetableDayType.weekday);
      expect(
        saturdayMidnight.directions.single.departures.map((d) => d.seconds),
        [88200],
      );

      final mondayMidnight = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 27, 15, 15),
      );
      expect(mondayMidnight.dayType, StationTimetableDayType.sundayHoliday);
      expect(
        mondayMidnight.directions.single.departures.map((d) => d.seconds),
        [87600],
      );

      final sundayMidnightNoLateTrain = await repository
          .loadNextStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            asOf: DateTime.utc(2026, 9, 26, 15, 15),
          );
      expect(
        sundayMidnightNoLateTrain.dayType,
        StationTimetableDayType.saturday,
      );
      expect(sundayMidnightNoLateTrain.directions, isEmpty);

      final mondayAfterCutoff = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 27, 18, 15),
      );
      expect(mondayAfterCutoff.dayType, StationTimetableDayType.weekday);
      expect(
        mondayAfterCutoff.directions.single.departures.map((d) => d.seconds),
        [60000, 88200],
      );

      await repository.database.customStatement('''
        INSERT INTO service_calendar_dates (service_id, date, exception_type)
        SELECT service_id, '20260928', 2 FROM service_calendars
      ''');

      await expectLater(
        repository.loadNextStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          asOf: DateTime.utc(2026, 9, 27, 18, 15),
        ),
        throwsA(isA<Exception>()),
      );

      final tuesdayWithoutExclusion = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 28, 18, 15),
      );
      expect(tuesdayWithoutExclusion.dayType, StationTimetableDayType.weekday);
      expect(
        tuesdayWithoutExclusion.directions.single.departures.map(
          (d) => d.seconds,
        ),
        [60000, 88200],
      );
    });

    test(
      'transit_feed_info.feed_end_date 만료 시 TIMETABLE_NOT_COVERED로 거부한다',
      () async {
        await database.customStatement('''
        CREATE TABLE transit_feed_info (
          feed_end_date TEXT NOT NULL
        )
      ''');
        await database.customStatement(
          "INSERT INTO transit_feed_info (feed_end_date) VALUES ('20260926')",
        );

        final onBoundary = await repository.loadStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.saturday,
          referenceDate: DateTime.utc(2026, 9, 26),
        );
        expect(onBoundary.isAvailable, isTrue);

        await expectLater(
          repository.loadStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            dayType: StationTimetableDayType.sundayHoliday,
            referenceDate: DateTime.utc(2026, 9, 27),
          ),
          throwsA(isA<StationTimetableUnavailable>()),
        );
      },
    );

    test('service_calendars start_date/end_date 범위 밖 날짜는 제외한다', () async {
      await database.customStatement('''
        UPDATE service_calendars
        SET start_date = '20260901', end_date = '20260930'
        WHERE service_id = 'cal-sat'
      ''');

      await expectLater(
        repository.loadStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.saturday,
          referenceDate: DateTime.utc(2026, 10, 3),
        ),
        throwsA(isA<StationTimetableUnavailable>()),
      );
    });

    test('service_calendar_dates exception_type = 1 추가 운행을 반영한다', () async {
      await database.customStatement('''
        INSERT INTO service_calendars (service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date)
        VALUES ('cal-weekday', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231'),
               ('cal-special', 0, 0, 0, 0, 0, 0, 0, '20260101', '20261231')
      ''');
      await database.customStatement('''
        INSERT INTO transit_routes (id, line_id, direction_name)
        VALUES ('route-weekday', 'seoul-4', '당고개 방면')
      ''');
      await database.customStatement('''
        INSERT INTO transit_trips (id, route_id, service_id, service_class, service_pattern)
        VALUES ('trip-wd-1', 'route-weekday', 'cal-weekday', 'SUBWAY', 'LOCAL'),
               ('trip-sp-1', 'route-weekday', 'cal-special', 'SUBWAY', 'LOCAL')
      ''');
      await database.customStatement('''
        INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
        VALUES ('trip-wd-1', 1, 'station-sangnoksu', 'seoul-4', 36000, 36000, 0, 0),
               ('trip-sp-1', 1, 'station-sangnoksu', 'seoul-4', 50400, 50400, 0, 0)
      ''');
      await database.customStatement('''
        INSERT INTO service_calendar_dates (service_id, date, exception_type)
        VALUES ('cal-special', '20260929', 1)
      ''');

      // 평일 기본 열차 + exception_type = 1 추가 열차가 함께 조회된다.
      final withExtra = await repository.loadStationTimetableForDate(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        date: DateTime.utc(2026, 9, 29, 3),
      );
      expect(withExtra.directions.single.departures.map((d) => d.seconds), [
        36000,
        50400,
      ]);
    });

    test(
      'loadNextStationTimetable은 horizonDays 상한(1~8)을 검증하고 다음 날 열차를 탐색한다',
      () async {
        await expectLater(
          repository.loadNextStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            asOf: DateTime.utc(2026, 9, 26, 2, 0),
            horizonDays: 0,
          ),
          throwsA(isA<StationTimetableUnavailable>()),
        );
        await expectLater(
          repository.loadNextStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            asOf: DateTime.utc(2026, 9, 26, 2, 0),
            horizonDays: 9,
          ),
          throwsA(isA<StationTimetableUnavailable>()),
        );

        // 토요일 23:00 KST (UTC 14:00) 이후 당일 열차는 끝났지만 horizonDays = 2로 일요일 열차를 찾는다.
        final nextDay = await repository.loadNextStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          asOf: DateTime.utc(2026, 9, 26, 14, 0),
          horizonDays: 2,
        );
        expect(nextDay.dayType, StationTimetableDayType.sundayHoliday);
        expect(nextDay.directions.single.departures.single.seconds, 40000);

        // 당일이 exception_type = 2로 전부 제외돼도 horizonDays = 2면 다음 날 열차를 이어서 탐색한다.
        await database.customStatement(
          "INSERT INTO service_calendar_dates (service_id, date, exception_type) VALUES ('cal-sat', '20260926', 2)",
        );
        final skippedExcludedDay = await repository.loadNextStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          asOf: DateTime.utc(2026, 9, 26, 0, 0),
          horizonDays: 2,
        );
        expect(
          skippedExcludedDay.dayType,
          StationTimetableDayType.sundayHoliday,
        );
        expect(
          skippedExcludedDay.directions.single.departures.single.seconds,
          40000,
        );

        // 탐색 범위 모든 날이 제외되면 TIMETABLE_NOT_COVERED를 던진다.
        await database.customStatement(
          "INSERT INTO service_calendar_dates (service_id, date, exception_type) VALUES ('cal-sun', '20260927', 2)",
        );
        await expectLater(
          repository.loadNextStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            asOf: DateTime.utc(2026, 9, 26, 0, 0),
            horizonDays: 2,
          ),
          throwsA(isA<StationTimetableUnavailable>()),
        );
      },
    );

    test(
      '평일 휴일 대체(exception_type=2 + exception_type=1) 시 일요일·공휴일 시간표를 선택한다',
      () async {
        await database.customStatement('''
        INSERT INTO service_calendars (service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date)
        VALUES ('cal-weekday', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231')
      ''');
        await database.customStatement('''
        INSERT INTO transit_routes (id, line_id, direction_name)
        VALUES ('route-weekday', 'seoul-4', '당고개 방면')
      ''');
        await database.customStatement('''
        INSERT INTO transit_trips (id, route_id, service_id, service_class, service_pattern)
        VALUES ('trip-wd-1', 'route-weekday', 'cal-weekday', 'SUBWAY', 'LOCAL')
      ''');
        await database.customStatement('''
        INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
        VALUES ('trip-wd-1', 1, 'station-sangnoksu', 'seoul-4', 36000, 36000, 0, 0)
      ''');
        await database.customStatement('''
        INSERT INTO service_calendar_dates (service_id, date, exception_type)
        VALUES ('cal-weekday', '20260929', 2),
               ('cal-sun', '20260929', 1)
      ''');

        final holidayWeekday = await repository.loadStationTimetableForDate(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          date: DateTime.utc(2026, 9, 29, 3),
        );
        expect(holidayWeekday.dayType, StationTimetableDayType.sundayHoliday);
        expect(
          holidayWeekday.directions.single.departures.single.seconds,
          40000,
        );
      },
    );

    test(
      '(trip_id, stop_sequence) 인접 순번 조회로 출발 시각이 같아도 다음 역 방면을 찾는다',
      () async {
        await database.customStatement('''
        INSERT INTO stations (id, name_ko, normalized_name)
        VALUES ('station-banwol', '반월', '반월')
      ''');
        await database.customStatement('''
        INSERT INTO station_lines (station_id, line_id, line_sequence)
        VALUES ('station-banwol', 'seoul-4', 42)
      ''');
        await database.customStatement('''
        INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
        VALUES ('trip-sat-1', 2, 'station-banwol', 'seoul-4', 36000, 36000, 0, 0)
      ''');

        final sat = await repository.loadStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.saturday,
          referenceDate: DateTime.utc(2026, 9, 26),
        );
        expect(sat.directions.single.name, '반월 방면');
      },
    );
  });
}
