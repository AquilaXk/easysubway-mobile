import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'server_station_timetable_repository.dart';

/// Timetable repository that delegates to [serverRepository] first,
/// and falls back to [localRepository] when the server does not cover the station
/// or is temporarily unavailable.
///
/// When falling back to the local repository, the returned [StationTimetable]
/// is explicitly marked with [StationTimetable.isOfflineFallback] set to true,
/// ensuring transparent notification to users and preventing silent stale-data fallbacks.
///
/// When the server experiences a connection failure ([ServerConnectionException]),
/// [reportMobileError] is called. If no local fallback is available, the connection
/// exception is propagated so UI layers can render an actionable offline error state.
class CompositeStationTimetableRepository
    implements StationTimetableRepository {
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
    Object? serverError;
    try {
      final timetable = await serverRepository.loadStationTimetable(
        stationId: stationId,
        lineId: lineId,
        dayType: dayType,
        referenceDate: referenceDate,
      );
      if (timetable.isAvailable) {
        return timetable.copyWith(isOfflineFallback: false);
      }
    } on StationTimetableUnavailable {
      // Server does not cover this station/line; fall through to local repository
    } catch (error, stackTrace) {
      serverError = error;
      reportMobileError(
        error,
        stackTrace,
        context: '서버 시간표 조회 실패로 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
      );
    }

    final local = localRepository;
    if (local != null) {
      try {
        final localTimetable = await local.loadStationTimetable(
          stationId: stationId,
          lineId: lineId,
          dayType: dayType,
          referenceDate: referenceDate,
        );
        if (localTimetable.isAvailable) {
          return localTimetable.copyWith(isOfflineFallback: true);
        }
      } on StationTimetableUnavailable {
        // Local database also has no timetable
      } catch (localError, localStack) {
        reportMobileError(
          localError,
          localStack,
          context: '로컬 저장 시간표 조회 실패: $stationId ($lineId)',
        );
      }
    }

    if (serverError != null) {
      if (serverError is ServerConnectionException) {
        throw serverError;
      }
      throw ServerConnectionException(
        '서버 장애로 시간표를 불러올 수 없습니다: $stationId ($lineId)',
        cause: serverError,
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
    Object? serverError;
    try {
      final timetable = await serverRepository.loadStationTimetableForDate(
        stationId: stationId,
        lineId: lineId,
        date: date,
      );
      if (timetable.isAvailable) {
        return timetable.copyWith(isOfflineFallback: false);
      }
    } on StationTimetableUnavailable {
      // Server does not cover this station/line; fall through to local repository
    } catch (error, stackTrace) {
      serverError = error;
      reportMobileError(
        error,
        stackTrace,
        context: '서버 일자별 시간표 조회 실패로 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
      );
    }

    final local = localRepository;
    if (local != null) {
      try {
        final localTimetable = await local.loadStationTimetableForDate(
          stationId: stationId,
          lineId: lineId,
          date: date,
        );
        if (localTimetable.isAvailable) {
          return localTimetable.copyWith(isOfflineFallback: true);
        }
      } on StationTimetableUnavailable {
        // Local database also has no timetable
      } catch (localError, localStack) {
        reportMobileError(
          localError,
          localStack,
          context: '로컬 일자별 시간표 조회 실패: $stationId ($lineId)',
        );
      }
    }

    if (serverError != null) {
      if (serverError is ServerConnectionException) {
        throw serverError;
      }
      throw ServerConnectionException(
        '서버 장애로 일자별 시간표를 불러올 수 없습니다: $stationId ($lineId)',
        cause: serverError,
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
    Object? serverError;
    try {
      final timetable = await serverRepository.loadNextStationTimetable(
        stationId: stationId,
        lineId: lineId,
        asOf: asOf,
        horizonDays: horizonDays,
      );
      if (timetable.isAvailable) {
        return timetable.copyWith(isOfflineFallback: false);
      }
    } on StationTimetableUnavailable {
      // Server does not cover this station/line; fall through to local repository
    } catch (error, stackTrace) {
      serverError = error;
      reportMobileError(
        error,
        stackTrace,
        context: '서버 다음 출발 시간표 조회 실패로 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
      );
    }

    final local = localRepository;
    if (local != null) {
      try {
        final localTimetable = await local.loadNextStationTimetable(
          stationId: stationId,
          lineId: lineId,
          asOf: asOf,
          horizonDays: horizonDays,
        );
        if (localTimetable.isAvailable) {
          return localTimetable.copyWith(isOfflineFallback: true);
        }
      } on StationTimetableUnavailable {
        // Local database also has no timetable
      } catch (localError, localStack) {
        reportMobileError(
          localError,
          localStack,
          context: '로컬 다음 출발 시간표 조회 실패: $stationId ($lineId)',
        );
      }
    }

    if (serverError != null) {
      if (serverError is ServerConnectionException) {
        throw serverError;
      }
      throw ServerConnectionException(
        '서버 장애로 다음 출발 시간표를 불러올 수 없습니다: $stationId ($lineId)',
        cause: serverError,
      );
    }

    throw const StationTimetableUnavailable('TIMETABLE_UNAVAILABLE');
  }
}
