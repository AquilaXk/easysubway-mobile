import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'server_station_timetable_repository.dart';

/// Timetable repository that delegates to [serverRepository] first,
/// and falls back to [localRepository] when the server does not cover the station
/// or is temporarily unavailable.
class CompositeStationTimetableRepository implements StationTimetableRepository {
  const CompositeStationTimetableRepository({
    required this.serverRepository,
    this.localRepository,
  });

  final StationTimetableRepository serverRepository;
  final StationTimetableRepository? localRepository;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    try {
      final timetable = await serverRepository.loadStationTimetable(
        stationId: stationId,
        lineId: lineId,
        dayType: dayType,
        referenceDate: referenceDate,
      );
      if (timetable.isAvailable) return timetable;
    } on StationTimetableUnavailable {
      // Fall through to local repository
    } catch (_) {
      // Fall through to local repository
    }
    final local = localRepository;
    if (local != null) {
      return local.loadStationTimetable(
        stationId: stationId,
        lineId: lineId,
        dayType: dayType,
        referenceDate: referenceDate,
      );
    }
    throw const StationTimetableUnavailable('TIMETABLE_UNAVAILABLE');
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    try {
      final timetable = await serverRepository.loadStationTimetableForDate(
        stationId: stationId,
        lineId: lineId,
        date: date,
      );
      if (timetable.isAvailable) return timetable;
    } on StationTimetableUnavailable {
      // Fall through to local repository
    } catch (_) {
      // Fall through to local repository
    }
    final local = localRepository;
    if (local != null) {
      return local.loadStationTimetableForDate(
        stationId: stationId,
        lineId: lineId,
        date: date,
      );
    }
    throw const StationTimetableUnavailable('TIMETABLE_UNAVAILABLE');
  }

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async {
    try {
      final timetable = await serverRepository.loadNextStationTimetable(
        stationId: stationId,
        lineId: lineId,
        asOf: asOf,
        horizonDays: horizonDays,
      );
      if (timetable.isAvailable) return timetable;
    } on StationTimetableUnavailable {
      // Fall through to local repository
    } catch (_) {
      // Fall through to local repository
    }
    final local = localRepository;
    if (local != null) {
      return local.loadNextStationTimetable(
        stationId: stationId,
        lineId: lineId,
        asOf: asOf,
        horizonDays: horizonDays,
      );
    }
    throw const StationTimetableUnavailable('TIMETABLE_UNAVAILABLE');
  }
}
