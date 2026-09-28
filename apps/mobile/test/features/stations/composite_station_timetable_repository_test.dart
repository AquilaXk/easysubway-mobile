import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/composite_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeServerTimetableRepository implements StationTimetableRepository {
  _FakeServerTimetableRepository({this.timetableToReturn, this.errorToThrow});

  StationTimetable? timetableToReturn;
  Object? errorToThrow;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
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
    if (errorToThrow != null) {
      throw errorToThrow!;
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
    if (errorToThrow != null) {
      throw errorToThrow!;
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
      'DriftStationTimetableRepository resolves adjacent next station as direction and extracts destination',
      () async {
        await database.customStatement('''
          INSERT INTO stations (id, name_ko, normalized_name)
          VALUES ('station-handaeap', '한대앞', '한대앞'),
                 ('station-banwol', '반월', '반월')
        ''');
        await database.customStatement('''
          INSERT INTO station_lines (station_id, line_id, line_sequence)
          VALUES ('station-handaeap', 'seoul-4', 44),
                 ('station-banwol', 'seoul-4', 42)
        ''');
        await database.customStatement('''
          INSERT INTO transit_trips (id, route_id, service_id, trip_headsign, service_class, service_pattern)
          VALUES ('trip-dest-1', 'route-oido', 'cal-weekday', '오이도', 'SUBWAY', 'LOCAL'),
                 ('trip-dest-2', 'route-jinjeop', 'cal-weekday', '사당', 'SUBWAY', 'LOCAL')
        ''');
        await database.customStatement('''
          INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, arrival_seconds, departure_seconds, pickup_type, drop_off_type)
          VALUES ('trip-dest-1', 1, 'station-sangnoksu', 'seoul-4', 30000, 30000, 0, 0),
                 ('trip-dest-1', 2, 'station-handaeap', 'seoul-4', 30120, 30120, 0, 0),
                 ('trip-dest-2', 1, 'station-sangnoksu', 'seoul-4', 30600, 30600, 0, 0),
                 ('trip-dest-2', 2, 'station-banwol', 'seoul-4', 30720, 30720, 0, 0)
        ''');

        final localRepo = DriftStationTimetableRepository(database: database);
        final timetable = await localRepo.loadStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: DateTime.utc(2026, 9, 25),
        );

        final dirNames = timetable.directions.map((d) => d.name).toList();
        expect(dirNames, containsAll(['한대앞 방면', '반월 방면']));

        final banwolDir = timetable.directions.firstWhere(
          (d) => d.name == '반월 방면',
        );
        final sadangDep = banwolDir.departures.firstWhere(
          (d) => d.seconds == 30600,
        );
        expect(sadangDep.destination, '사당');
        expect(sadangDep.destinationLabel, '사당행');

        final handaeapDir = timetable.directions.firstWhere(
          (d) => d.name == '한대앞 방면',
        );
        final oidoDep = handaeapDir.departures.firstWhere(
          (d) => d.seconds == 30000,
        );
        expect(oidoDep.destination, '오이도');
        expect(oidoDep.destinationLabel, '오이도행');
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
        expect(timetable.isOfflineFallback, isFalse);
        expect(timetable.directions.first.name, '춘천 방면');
      },
    );

    test(
      'CompositeStationTimetableRepository falls back to local and marks offline when server throws',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          errorToThrow: Exception('Server network failure'),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final reportedErrors = <FlutterErrorDetails>[];
        final timetable = await runWithMobileErrorReporter(
          (details) => reportedErrors.add(details),
          () => composite.loadStationTimetableForDate(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            date: DateTime.utc(2026, 9, 25),
          ),
        );

        expect(timetable.isAvailable, isTrue);
        expect(timetable.isOfflineFallback, isTrue);
        expect(reportedErrors, isNotEmpty);
        expect(
          reportedErrors.first.context?.toString(),
          contains('서버 일자별 시간표 조회 실패로 로컬 저장 시간표로 전환합니다'),
        );
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
        expect(timetable.isOfflineFallback, isTrue);
        expect(timetable.directions, hasLength(2));
      },
    );

    test(
      'CompositeStationTimetableRepository delegates loadStationTimetable and falls back to local with offline mark',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          errorToThrow: Exception('Server 500 error'),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final reportedErrors = <FlutterErrorDetails>[];
        final timetable = await runWithMobileErrorReporter(
          (details) => reportedErrors.add(details),
          () => composite.loadStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            dayType: StationTimetableDayType.weekday,
            referenceDate: DateTime.utc(2026, 9, 25),
          ),
        );
        expect(timetable.isAvailable, isTrue);
        expect(timetable.isOfflineFallback, isTrue);
        expect(reportedErrors, isNotEmpty);

        final serverSuccess = _FakeServerTimetableRepository(
          timetableToReturn: timetable,
        );
        final compositeSuccess = CompositeStationTimetableRepository(
          serverRepository: serverSuccess,
          localRepository: localRepo,
        );
        final successResult = await compositeSuccess.loadStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          referenceDate: DateTime.utc(2026, 9, 25),
        );
        expect(successResult.isAvailable, isTrue);
        expect(successResult.isOfflineFallback, isFalse);
      },
    );

    test(
      'CompositeStationTimetableRepository delegates loadNextStationTimetable and falls back to local with offline mark',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          errorToThrow: Exception('Server timeout'),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final reportedErrors = <FlutterErrorDetails>[];
        final timetable = await runWithMobileErrorReporter(
          (details) => reportedErrors.add(details),
          () => composite.loadNextStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            asOf: DateTime.utc(2026, 9, 25, 7, 0),
          ),
        );
        expect(timetable.isAvailable, isTrue);
        expect(timetable.isOfflineFallback, isTrue);
        expect(reportedErrors, isNotEmpty);

        final serverSuccess = _FakeServerTimetableRepository(
          timetableToReturn: timetable,
        );
        final compositeSuccess = CompositeStationTimetableRepository(
          serverRepository: serverSuccess,
          localRepository: localRepo,
        );
        final successResult = await compositeSuccess.loadNextStationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          asOf: DateTime.utc(2026, 9, 25, 7, 0),
        );
        expect(successResult.isAvailable, isTrue);
        expect(successResult.isOfflineFallback, isFalse);
      },
    );

    test(
      'StationTimetable copyWith correctly updates isOfflineFallback and other fields',
      () {
        const original = StationTimetable(
          stationId: 'st-1',
          lineId: 'line-1',
          dayType: StationTimetableDayType.weekday,
          directions: [],
          isOfflineFallback: false,
        );
        final updated = original.copyWith(isOfflineFallback: true);
        expect(updated.isOfflineFallback, isTrue);
        expect(updated.stationId, 'st-1');

        final preserved = updated.copyWith();
        expect(preserved.isOfflineFallback, isTrue);
      },
    );

    test(
      'CompositeStationTimetableRepository does NOT report error when server throws StationTimetableUnavailable',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          errorToThrow: const StationTimetableUnavailable('NOT_COVERED'),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final reportedErrors = <FlutterErrorDetails>[];
        final timetable = await runWithMobileErrorReporter(
          (details) => reportedErrors.add(details),
          () => composite.loadStationTimetable(
            stationId: 'station-sangnoksu',
            lineId: 'seoul-4',
            dayType: StationTimetableDayType.weekday,
            referenceDate: DateTime.utc(2026, 9, 25),
          ),
        );

        expect(timetable.isAvailable, isTrue);
        expect(timetable.isOfflineFallback, isTrue);
        expect(reportedErrors, isEmpty);
      },
    );

    test(
      'CompositeStationTimetableRepository rethrows ServerConnectionException when server fails and local has no cache',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          errorToThrow: const ServerConnectionException(
            '500 Internal Error',
            statusCode: 500,
          ),
        );
        final localRepo = DriftStationTimetableRepository(database: database);
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: localRepo,
        );

        final reportedErrors = <FlutterErrorDetails>[];
        await expectLater(
          runWithMobileErrorReporter(
            (details) => reportedErrors.add(details),
            () => composite.loadStationTimetable(
              stationId: 'station-unknown',
              lineId: 'seoul-4',
              dayType: StationTimetableDayType.weekday,
              referenceDate: DateTime.utc(2026, 9, 25),
            ),
          ),
          throwsA(isA<ServerConnectionException>()),
        );

        expect(reportedErrors, isNotEmpty);
      },
    );

    test(
      'ServerConnectionException toString prints message, statusCode and cause',
      () {
        const e1 = ServerConnectionException('timeout');
        expect(e1.toString(), 'ServerConnectionException: timeout');

        const e2 = ServerConnectionException('server error', statusCode: 500);
        expect(
          e2.toString(),
          'ServerConnectionException: server error (HTTP 500)',
        );

        final e3 = ServerConnectionException(
          'failed',
          statusCode: 502,
          cause: Exception('bad gateway'),
        );
        expect(e3.toString(), contains('(HTTP 502)'));
        expect(e3.toString(), contains('[cause: Exception: bad gateway]'));
      },
    );

    test(
      'CompositeStationTimetableRepository handles local repository unexpected errors and wraps generic server errors in ServerConnectionException',
      () async {
        final serverRepo = _FakeServerTimetableRepository(
          errorToThrow: StateError('unexpected server failure'),
        );
        final throwingLocal = _FakeThrowingLocalTimetableRepository();
        final composite = CompositeStationTimetableRepository(
          serverRepository: serverRepo,
          localRepository: throwingLocal,
        );

        final reportedErrors = <FlutterErrorDetails>[];
        // 1. loadStationTimetable
        await expectLater(
          runWithMobileErrorReporter(
            (details) => reportedErrors.add(details),
            () => composite.loadStationTimetable(
              stationId: 'station-unknown',
              lineId: 'seoul-4',
              dayType: StationTimetableDayType.weekday,
              referenceDate: DateTime.utc(2026, 9, 25),
            ),
          ),
          throwsA(isA<ServerConnectionException>()),
        );

        // 2. loadStationTimetableForDate
        await expectLater(
          runWithMobileErrorReporter(
            (details) => reportedErrors.add(details),
            () => composite.loadStationTimetableForDate(
              stationId: 'station-unknown',
              lineId: 'seoul-4',
              date: DateTime.utc(2026, 9, 25),
            ),
          ),
          throwsA(isA<ServerConnectionException>()),
        );

        // 3. loadNextStationTimetable
        await expectLater(
          runWithMobileErrorReporter(
            (details) => reportedErrors.add(details),
            () => composite.loadNextStationTimetable(
              stationId: 'station-unknown',
              lineId: 'seoul-4',
              asOf: DateTime.utc(2026, 9, 25),
            ),
          ),
          throwsA(isA<ServerConnectionException>()),
        );

        // Both server failure and local unexpected errors are reported
        expect(reportedErrors.length, greaterThanOrEqualTo(6));
      },
    );
  });
}

class _FakeThrowingLocalTimetableRepository
    implements StationTimetableRepository {
  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    throw StateError('local db read failed');
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    throw StateError('local db date read failed');
  }

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async {
    throw StateError('local db next read failed');
  }
}
