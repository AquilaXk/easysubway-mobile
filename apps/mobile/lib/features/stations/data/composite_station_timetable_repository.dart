import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'server_station_timetable_repository.dart';

/// Timetable repository that asks [serverRepository] first and uses
/// [localRepository] only when the server cannot be reached.
///
/// The server is the timetable authority. When it answers explicitly — no
/// timetable for the station or date (`TIMETABLE_NOT_COVERED`), a stale or
/// unavailable timetable (503), an integrity violation, or a station name the
/// app catalog cannot resolve — that answer is shown as is and never covered
/// with the device's stored timetable (#437). Only a transport failure
/// ([ServerUnreachableException]) switches to the local timetable, which is then
/// marked with [StationTimetable.isOfflineFallback].
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
  }) => _load(
    (repository) => repository.loadStationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      referenceDate: referenceDate,
    ),
    serverContext: '서버 시간표 조회 실패',
    localContext: '서버에 연결할 수 없어 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
    stationId: stationId,
    lineId: lineId,
  );

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) => _load(
    (repository) => repository.loadStationTimetableForDate(
      stationId: stationId,
      lineId: lineId,
      date: date,
    ),
    serverContext: '서버 일자별 시간표 조회 실패',
    localContext: '서버에 연결할 수 없어 일자별 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
    stationId: stationId,
    lineId: lineId,
  );

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) => _load(
    (repository) => repository.loadNextStationTimetable(
      stationId: stationId,
      lineId: lineId,
      asOf: asOf,
      horizonDays: horizonDays,
    ),
    serverContext: '서버 다음 열차 시간표 조회 실패',
    localContext: '서버에 연결할 수 없어 다음 열차 로컬 저장 시간표로 전환합니다: $stationId ($lineId)',
    stationId: stationId,
    lineId: lineId,
  );

  Future<StationTimetable> _load(
    Future<StationTimetable> Function(StationTimetableRepository repository)
    call, {
    required String serverContext,
    required String localContext,
    required String stationId,
    required String lineId,
  }) async {
    try {
      final timetable = await call(serverRepository);
      return timetable.copyWith(isOfflineFallback: false);
    } on ServerUnreachableException catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: localContext);
      final local = localRepository;
      if (local != null) {
        try {
          final localTimetable = await call(local);
          if (localTimetable.isAvailable) {
            return localTimetable.copyWith(isOfflineFallback: true);
          }
        } on StationTimetableUnavailable {
          // The device has no stored timetable for this station-line either.
        } catch (localError, localStack) {
          reportMobileError(
            localError,
            localStack,
            context: '로컬 저장 시간표 조회 실패: $stationId ($lineId)',
          );
        }
      }
      rethrow;
    } on StationTimetableUnavailable {
      rethrow;
    } on ServerConnectionException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '$serverContext: $stationId ($lineId)',
      );
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '$serverContext: $stationId ($lineId)',
      );
      throw ServerConnectionException(
        '서버 시간표를 불러올 수 없습니다: $stationId ($lineId)',
        cause: error,
      );
    }
  }
}
