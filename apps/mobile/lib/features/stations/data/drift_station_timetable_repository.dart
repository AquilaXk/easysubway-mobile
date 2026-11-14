import 'package:drift/drift.dart';

import '../../../core/database/catalog/catalog_database.dart';
import '../../../core/format/date_time_labels.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'server_station_timetable_repository.dart';

/// Local Drift/SQLite timetable repository querying packaged [CatalogDatabase].
class DriftStationTimetableRepository implements StationTimetableRepository {
  const DriftStationTimetableRepository({required this.database});

  static const int _maxHorizonDays = 8;

  final CatalogDatabase database;

  static String _formatDateKey(DateTime seoulDate) {
    return '${seoulDate.year.toString().padLeft(4, '0')}'
        '${seoulDate.month.toString().padLeft(2, '0')}'
        '${seoulDate.day.toString().padLeft(2, '0')}';
  }

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

    final seoulRef = journeySeoulWallTime(referenceDate);
    final dateKey = _formatDateKey(seoulRef);
    final feedEndDate = await database.transitFeedEndDate();
    if (feedEndDate != null && dateKey.compareTo(feedEndDate) > 0) {
      throw const StationTimetableUnavailable('TIMETABLE_NOT_COVERED');
    }

    final rows = await database
        .customSelect(
          '''
      SELECT DISTINCT
        r.direction_name,
        COALESCE(
          (
            SELECT s2.name_ko
            FROM transit_stop_times st2
            JOIN stations s2 ON s2.id = st2.station_id
            WHERE st2.trip_id = st.trip_id
              AND st2.stop_sequence > st.stop_sequence
            ORDER BY st2.stop_sequence ASC LIMIT 1
          ) || ' 방면',
          r.direction_name
        ) AS resolved_direction_name,
        st.departure_seconds,
        COALESCE(t.trip_headsign, '') AS trip_headsign,
        t.service_pattern,
        t.service_class
      FROM transit_stop_times st
      JOIN transit_trips t ON t.id = st.trip_id
      JOIN transit_routes r ON r.id = t.route_id
      LEFT JOIN service_calendars sc ON sc.service_id = t.service_id
      WHERE st.station_id = ?
        AND st.line_id = ?
        AND st.pickup_type = 0
        AND (
          (
            sc.start_date <= ?
            AND sc.end_date >= ?
            AND (
              (? = 'weekday' AND (sc.monday = 1 OR sc.tuesday = 1 OR sc.wednesday = 1 OR sc.thursday = 1 OR sc.friday = 1))
              OR (? = 'saturday' AND sc.saturday = 1)
              OR (? = 'sundayHoliday' AND sc.sunday = 1)
            )
            AND NOT EXISTS (
              SELECT 1
              FROM service_calendar_dates scd
              WHERE scd.service_id = t.service_id
                AND scd.date = ?
                AND scd.exception_type = 2
            )
          )
          OR EXISTS (
            SELECT 1
            FROM service_calendar_dates scd_add
            WHERE scd_add.service_id = t.service_id
              AND scd_add.date = ?
              AND scd_add.exception_type = 1
          )
        )
      ORDER BY resolved_direction_name, st.departure_seconds
      ''',
          variables: [
            Variable.withString(stationId),
            Variable.withString(lineId),
            Variable.withString(dateKey),
            Variable.withString(dateKey),
            Variable.withString(dayKey),
            Variable.withString(dayKey),
            Variable.withString(dayKey),
            Variable.withString(dateKey),
            Variable.withString(dateKey),
          ],
        )
        .get();
    final directionsMap = <String, List<StationTimetableDeparture>>{};
    for (final row in rows) {
      final directionName = row.read<String>('resolved_direction_name');
      final rawDirectionName = row.read<String>('direction_name');
      final seconds = row.read<int>('departure_seconds');
      final destination = row.read<String>('trip_headsign');
      final servicePattern = row.read<String?>('service_pattern') ?? 'LOCAL';
      final serviceClass = row.read<String?>('service_class') ?? 'SUBWAY';

      final departureAt = DateTime.utc(
        seoulRef.year,
        seoulRef.month,
        seoulRef.day,
      ).subtract(const Duration(hours: 9)).add(Duration(seconds: seconds));

      directionsMap
          .putIfAbsent(directionName, () => [])
          .add(
            StationTimetableDeparture(
              directionName: directionName,
              seconds: seconds,
              departureAt: departureAt,
              destination: destination.isNotEmpty
                  ? destination
                  : rawDirectionName.replaceAll('방면', '').trim(),
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
      isOfflineFallback: true,
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
    if (horizonDays < 1 || horizonDays > _maxHorizonDays) {
      throw const StationTimetableUnavailable(
        'Invalid next-departures horizon.',
      );
    }
    final serviceDate = journeyCurrentServiceDay(asOf);
    final wall = journeySeoulWallTime(asOf);
    final nowSeconds = wall.hour * 3600 + wall.minute * 60 + wall.second;
    final effectiveSeconds = wall.hour < 3 ? nowSeconds + 86400 : nowSeconds;

    StationTimetableDayType? firstCoveredDayType;
    late StationTimetableUnavailable lastUnavailable;

    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final targetDate = DateTime.utc(
        serviceDate.year,
        serviceDate.month,
        serviceDate.day + dayOffset,
      );
      final StationTimetable timetable;
      try {
        timetable = await loadStationTimetableForDate(
          stationId: stationId,
          lineId: lineId,
          date: targetDate,
        );
      } on StationTimetableUnavailable catch (error) {
        lastUnavailable = error;
        if (dayOffset == 0 && horizonDays == 1) {
          rethrow;
        }
        continue;
      }

      firstCoveredDayType ??= timetable.dayType;
      final minSeconds = dayOffset == 0 ? effectiveSeconds : 0;
      final filteredDirections = <StationTimetableDirection>[];
      for (final dir in timetable.directions) {
        final upcoming = dir.departures
            .where((d) => d.seconds >= minSeconds)
            .toList(growable: false);
        if (upcoming.isNotEmpty) {
          filteredDirections.add(
            StationTimetableDirection(name: dir.name, departures: upcoming),
          );
        }
      }
      if (filteredDirections.isNotEmpty) {
        return StationTimetable(
          stationId: stationId,
          lineId: lineId,
          dayType: timetable.dayType,
          directions: List.unmodifiable(filteredDirections),
          isOfflineFallback: true,
        );
      }
    }

    if (firstCoveredDayType != null) {
      return StationTimetable(
        stationId: stationId,
        lineId: lineId,
        dayType: firstCoveredDayType,
        directions: const [],
        isOfflineFallback: true,
      );
    }
    throw lastUnavailable;
  }

  Future<StationTimetableDayType> _resolveDayTypeForDate(DateTime date) async {
    final seoulDate = journeySeoulWallTime(date);
    if (seoulDate.weekday == DateTime.sunday) {
      return StationTimetableDayType.sundayHoliday;
    }
    final dateKey = _formatDateKey(seoulDate);
    final weekday = seoulDate.weekday;

    final holidayOverrideRow = await database
        .customSelect(
          '''
      SELECT EXISTS(
        SELECT 1
        FROM service_calendar_dates scd
        JOIN service_calendars sc ON sc.service_id = scd.service_id
        WHERE scd.date = ?
          AND scd.exception_type = 1
          AND (
            sc.sunday = 1
            OR NOT EXISTS (
              SELECT 1
              FROM service_calendars reg
              WHERE reg.start_date <= ?
                AND reg.end_date >= ?
                AND (
                  (? = 6 AND reg.saturday = 1)
                  OR (? BETWEEN 1 AND 5 AND (reg.monday = 1 OR reg.tuesday = 1 OR reg.wednesday = 1 OR reg.thursday = 1 OR reg.friday = 1))
                )
                AND NOT EXISTS (
                  SELECT 1
                  FROM service_calendar_dates exc
                  WHERE exc.service_id = reg.service_id
                    AND exc.date = ?
                    AND exc.exception_type = 2
                )
            )
          )
      ) AS is_holiday_override
      ''',
          variables: [
            Variable.withString(dateKey),
            Variable.withString(dateKey),
            Variable.withString(dateKey),
            Variable.withInt(weekday),
            Variable.withInt(weekday),
            Variable.withString(dateKey),
          ],
        )
        .getSingle();

    if (holidayOverrideRow.read<int>('is_holiday_override') == 1) {
      return StationTimetableDayType.sundayHoliday;
    }
    if (weekday == DateTime.saturday) {
      return StationTimetableDayType.saturday;
    }
    return StationTimetableDayType.weekday;
  }
}
