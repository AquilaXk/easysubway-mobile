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

      final sun = await repository.loadStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.sundayHoliday,
        referenceDate: DateTime.utc(2026, 9, 27),
      );
      expect(sun.isAvailable, isTrue);
      expect(sun.isOfflineFallback, isTrue);
    });

    test('loadNextStationTimetable은 기준 시각 이후 열차만 필터링하여 반환한다', () async {
      // 2026-09-26 is Saturday, departure is at 36000 (10:00:00)
      final beforeTrain = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 26, 9, 0, 0),
      );
      expect(beforeTrain.isAvailable, isTrue);
      expect(beforeTrain.isOfflineFallback, isTrue);
      expect(beforeTrain.directions, isNotEmpty);

      final afterTrain = await repository.loadNextStationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        asOf: DateTime.utc(2026, 9, 26, 11, 0, 0),
      );
      expect(afterTrain.directions, isEmpty);
      expect(afterTrain.isOfflineFallback, isTrue);
    });
  });
}
