import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_timetable_repository.dart';
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
    });
  });
}
