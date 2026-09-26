import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/composite_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeServerTimetableRepository implements StationTimetableRepository {
  _FakeServerTimetableRepository({
    this.timetableToReturn,
    this.shouldThrow = false,
  });

  StationTimetable? timetableToReturn;
  bool shouldThrow;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    if (shouldThrow) {
      throw const StationTimetableUnavailable('TIMETABLE_NOT_COVERED');
    }
    return timetableToReturn ??
        StationTimetable(
          stationId: stationId,
          lineId: lineId,
          dayType: dayType,
          directions: const [],
        );
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    if (shouldThrow) {
      throw const StationTimetableUnavailable('TIMETABLE_NOT_COVERED');
    }
    return timetableToReturn ??
        StationTimetable(
          stationId: stationId,
          lineId: lineId,
          dayType: StationTimetableDayType.weekday,
          directions: const [],
        );
  }

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async {
    if (shouldThrow) {
      throw const StationTimetableUnavailable('TIMETABLE_NOT_COVERED');
    }
    return timetableToReturn ??
        StationTimetable(
          stationId: stationId,
          lineId: lineId,
          dayType: StationTimetableDayType.weekday,
          directions: const [],
        );
  }
}

void main() {
  group('CompositeStationTimetableRepository', () {
    late CatalogDatabase database;

    setUp(() async {
      database = CatalogDatabase.memory();
      await database.seedBaselineIfEmpty();

      // Seed sample transit data for Sangnoksu
      await database.customStatement('''
        INSERT INTO service_calendars (service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date)
        VALUES ('cal-weekday', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231')
      ''');
      await database.customStatement('''
        INSERT INTO transit_routes (id, line_id, direction_name)
        VALUES ('route-oido', 'seoul-4', '오이도 방면'),
               ('route-jinjeop', 'seoul-4', '진접 방면')
      ''');
      await database.customStatement('''
        INSERT INTO transit_trips (id, route_id, service_id, service_class, service_pattern)
        VALUES ('trip-1', 'route-oido', 'cal-weekday', 'SUBWAY', 'LOCAL'),
               ('trip-2', 'route-jinjeop', 'cal-weekday', 'SUBWAY', 'LOCAL')
      ''');
      await database.customStatement('''
        INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
        VALUES ('trip-1', 1, 'station-sangnoksu', 'seoul-4', 28800, 28800, 0, 0),
               ('trip-2', 1, 'station-sangnoksu', 'seoul-4', 29400, 29400, 0, 0)
      ''');
    });

    tearDown(() => database.close());

    test(
      'DriftStationTimetableRepository loads weekday timetable from catalog',
      () async {
        final localRepo = DriftStationTimetableRepository(database: database);
        final timetable = await localRepo.loadStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: DateTime.utc(2026, 9, 25),
        );

        expect(timetable.isAvailable, isTrue);
        expect(timetable.directions, hasLength(2));
        expect(
          timetable.directions.map((d) => d.name),
          containsAll(['오이도 방면', '진접 방면']),
        );
        expect(timetable.directions.first.departures, hasLength(1));
      },
    );

    test(
      'DriftStationTimetableRepository throws when station line is not covered',
      () async {
        final localRepo = DriftStationTimetableRepository(database: database);
        expect(
          () => localRepo.loadStationTimetable(
            stationId: 'station-unknown',
            lineId: 'seoul-4',
            dayType: StationTimetableDayType.weekday,
            referenceDate: DateTime.utc(2026, 9, 25),
          ),
          throwsA(isA<StationTimetableUnavailable>()),
        );
      },
    );

    test(
      'CompositeStationTimetableRepository returns server timetable when available',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          timetableToReturn: StationTimetable(
            stationId: 'station-itx',
            lineId: 'line-itx',
            dayType: StationTimetableDayType.weekday,
            directions: [
              StationTimetableDirection(
                name: '춘천 방면',
                departures: [
                  StationTimetableDeparture(
                    directionName: '춘천 방면',
                    seconds: 36000,
                    serviceClass: 'ITX_CHEONGCHUN',
                  ),
                ],
              ),
            ],
          ),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final timetable = await composite.loadStationTimetableForDate(
          stationId: 'station-itx',
          lineId: 'line-itx',
          date: DateTime.utc(2026, 9, 25),
        );
        expect(timetable.isAvailable, isTrue);
        expect(timetable.directions.first.name, '춘천 방면');
      },
    );

    test(
      'CompositeStationTimetableRepository falls back to local when server throws',
      () async {
        final serverRepo = _FakeServerTimetableRepository(shouldThrow: true);
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final timetable = await composite.loadStationTimetableForDate(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          date: DateTime.utc(2026, 9, 25),
        );
        expect(timetable.isAvailable, isTrue);
        expect(
          timetable.directions.map((d) => d.name),
          containsAll(['오이도 방면', '진접 방면']),
        );
      },
    );

    test(
      'CompositeStationTimetableRepository falls back to local when server returns empty',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          timetableToReturn: StationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            dayType: StationTimetableDayType.weekday,
            directions: const [],
          ),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final timetable = await composite.loadStationTimetableForDate(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          date: DateTime.utc(2026, 9, 25),
        );
        expect(timetable.isAvailable, isTrue);
        expect(timetable.directions, hasLength(2));
      },
    );
  });
}
