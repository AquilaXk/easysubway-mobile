import 'package:drift/drift.dart';

import '../../../core/database/catalog/catalog_database.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'server_station_timetable_repository.dart';

/// Local Drift/SQLite timetable repository querying packaged [CatalogDatabase].
class DriftStationTimetableRepository implements StationTimetableRepository {
  const DriftStationTimetableRepository({required this.database});

  final CatalogDatabase database;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    final dayKey = switch (dayType) {
      StationTimetableDayType.weekday => 'weekday',
      StationTimetableDayType.saturday => 'saturday',
      StationTimetableDayType.sundayHoliday => 'sundayHoliday',
    };

    final rows = await database
        .customSelect(
          '''
      SELECT DISTINCT r.direction_name, st.departure_seconds,
             t.service_pattern, t.service_class
      FROM transit_stop_times st
      JOIN transit_trips t ON t.id = st.trip_id
      JOIN transit_routes r ON r.id = t.route_id
      JOIN service_calendars sc ON sc.service_id = t.service_id
      WHERE st.station_id = ?
        AND st.line_id = ?
        AND st.pickup_type = 0
        AND (
          (? = 'weekday' AND (sc.monday = 1 OR sc.tuesday = 1 OR sc.wednesday = 1 OR sc.thursday = 1 OR sc.friday = 1))
          OR (? = 'saturday' AND sc.saturday = 1)
          OR (? = 'sundayHoliday' AND sc.sunday = 1)
        )
      ORDER BY r.direction_name, st.departure_seconds
      ''',
          variables: [
            Variable.withString(stationId),
            Variable.withString(lineId),
            Variable.withString(dayKey),
            Variable.withString(dayKey),
            Variable.withString(dayKey),
          ],
        )
        .get();

    final directionsMap = <String, List<StationTimetableDeparture>>{};
    for (final row in rows) {
      final directionName = row.read<String>('direction_name');
      final seconds = row.read<int>('departure_seconds');
      final servicePattern = row.read<String?>('service_pattern') ?? 'LOCAL';
      final serviceClass = row.read<String?>('service_class') ?? 'SUBWAY';

      final departureAt = DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
      ).add(Duration(seconds: seconds));

      directionsMap
          .putIfAbsent(directionName, () => [])
          .add(
            StationTimetableDeparture(
              directionName: directionName,
              seconds: seconds,
              departureAt: departureAt,
              servicePattern: servicePattern,
              serviceClass: serviceClass,
            ),
          );
    }

    final directions = directionsMap.entries
        .map((entry) {
          return StationTimetableDirection(
            name: entry.key,
            departures: List.unmodifiable(entry.value),
          );
        })
        .toList(growable: false);

    if (directions.isEmpty) {
      throw const StationTimetableUnavailable('TIMETABLE_NOT_COVERED');
    }

    return StationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      directions: List.unmodifiable(directions),
    );
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    final dayType = await _resolveDayTypeForDate(date);
    return loadStationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      referenceDate: date,
    );
  }

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async {
    final timetable = await loadStationTimetableForDate(
      stationId: stationId,
      lineId: lineId,
      date: asOf,
    );
    final nowSeconds = asOf.hour * 3600 + asOf.minute * 60 + asOf.second;
    final filteredDirections = <StationTimetableDirection>[];
    for (final dir in timetable.directions) {
      final upcoming = dir.departures
          .where((d) => d.seconds >= nowSeconds)
          .toList(growable: false);
      if (upcoming.isNotEmpty) {
        filteredDirections.add(
          StationTimetableDirection(name: dir.name, departures: upcoming),
        );
      }
    }
    return StationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: timetable.dayType,
      directions: List.unmodifiable(filteredDirections),
    );
  }

  Future<StationTimetableDayType> _resolveDayTypeForDate(DateTime date) async {
    final dateKey =
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';

    final holidayExceptionRows = await database
        .customSelect(
          '''
      SELECT 1 FROM service_calendar_dates
      WHERE date = ? AND exception_type = 1
      LIMIT 1
      ''',
          variables: [Variable.withString(dateKey)],
        )
        .get();

    if (holidayExceptionRows.isNotEmpty || date.weekday == DateTime.sunday) {
      return StationTimetableDayType.sundayHoliday;
    }
    if (date.weekday == DateTime.saturday) {
      return StationTimetableDayType.saturday;
    }
    return StationTimetableDayType.weekday;
  }
}
