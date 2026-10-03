import '../../../generated/journey_v3/journey_v3_contract.dart' as contract;
import '../../journey/journey_session_provider.dart';
import '../../journey/domain/journey_repository.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

export '../domain/station_repositories.dart' show ServerConnectionException;

/// 역 ID의 앱 카탈로그 이름. 찾지 못하면 예외를 던진다.
typedef StationTimetableStationNameResolver =
    Future<String> Function(String stationId);

/// 역 검색 저장소(앱 카탈로그)의 역 상세 이름으로 이름을 붙인다.
StationTimetableStationNameResolver stationDetailNameResolver(
  StationSearchRepository repository,
) =>
    (stationId) async => (await repository.getStationDetail(stationId)).nameKo;

/// Server-authoritative timetable adapter. It never retains a prior timetable
/// when the Journey V3 operation rejects a request. The catalog is used only to
/// name stations the server identifies (next stop and terminal, #437).
class ServerStationTimetableRepository implements StationTimetableRepository {
  ServerStationTimetableRepository({
    required JourneyRepository journeyRepository,
    required JourneySessionProvider sessionProvider,
    required StationTimetableStationNameResolver stationNameResolver,
    DateTime Function()? now,
  }) : this._(
         journeyRepository,
         sessionProvider,
         stationNameResolver,
         now ?? DateTime.now,
       );

  ServerStationTimetableRepository._(
    this._journeyRepository,
    this._sessionProvider,
    this._stationNameResolver,
    this._now,
  );

  final JourneyRepository _journeyRepository;
  final JourneySessionProvider _sessionProvider;
  final StationTimetableStationNameResolver _stationNameResolver;
  final DateTime Function() _now;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) => _load(
    stationId,
    lineId,
    // 요일 종류(DAY_TYPE)를 보내지 않는다. 토요일 시간표가 없는 기관에
    // DAY_TYPE=SATURDAY를 보내면 400이다(backend #479). 탭 요일에 맞는 가장
    // 가까운 날짜를 보내고, 그 날의 요일 종류는 서버가 판정한다(resolvedDayType).
    contract.StationTimetableServiceDateSelector(
      contract.JourneyDate.parse(_nextSeoulDateFor(dayType, referenceDate)),
    ),
  );

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) => _load(
    stationId,
    lineId,
    contract.StationTimetableServiceDateSelector(
      contract.JourneyDate.parse(_seoulDate(date)),
    ),
  );

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) {
    if (horizonDays < 1 || horizonDays > 8) {
      throw const StationTimetableUnavailable(
        'Invalid next-departures horizon.',
      );
    }
    return _load(
      stationId,
      lineId,
      contract.StationTimetableNextDeparturesSelector(
        asOf: asOf,
        horizonDays: horizonDays,
      ),
    );
  }

  Future<StationTimetable> _load(
    String stationId,
    String lineId,
    contract.StationTimetableSelector selector,
  ) async {
    final contract.JourneySessionResponse session;
    try {
      session = await _sessionProvider.session();
    } on JourneyRejectedFailure catch (error) {
      if (error.statusCode >= 500 ||
          error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 429) {
        throw ServerConnectionException(
          'Journey server rejected session (${error.statusCode}).',
          statusCode: error.statusCode,
          cause: error,
        );
      }
      throw StationTimetableUnavailable(error.error.code.wire);
    } on JourneyTransportFailure catch (error) {
      throw ServerConnectionException(
        'Network transport failure: ${error.operation.wire}',
        cause: error.cause,
      );
    } on JourneyProtocolFailure catch (error) {
      throw ServerConnectionException(
        'Journey protocol failure: ${error.operation.wire}',
        statusCode: error.statusCode,
        cause: error.cause,
      );
    } on JourneySessionInvalid catch (error) {
      throw ServerConnectionException(
        'Journey session is invalid or unavailable.',
        cause: error,
      );
    } catch (error) {
      throw ServerConnectionException(
        'Journey session issuance failed: $error',
        cause: error,
      );
    }
    try {
      final response = await _journeyRepository.searchStationTimetables(
        contract.StationTimetableSearchRequest(
          stationId: stationId,
          lineId: lineId,
          selector: selector,
        ),
        sessionToken: session.token,
      );
      return await _map(
        response,
        stationId: stationId,
        lineId: lineId,
        selector: selector,
      );
    } on JourneyRejectedFailure catch (error) {
      if (error.statusCode == 401) _sessionProvider.invalidate();
      if (error.statusCode >= 500 ||
          error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 429) {
        throw ServerConnectionException(
          'Journey server rejected timetable request (${error.statusCode}).',
          statusCode: error.statusCode,
          cause: error,
        );
      }
      throw StationTimetableUnavailable(error.error.code.wire);
    } on JourneyTransportFailure catch (error) {
      throw ServerConnectionException(
        'Network transport failure: ${error.operation.wire}',
        cause: error.cause,
      );
    } on JourneyProtocolFailure catch (error) {
      throw ServerConnectionException(
        'Journey protocol failure: ${error.operation.wire}',
        statusCode: error.statusCode,
        cause: error.cause,
      );
    } on FormatException catch (error) {
      throw ServerConnectionException(
        'Station timetable data integrity violation: ${error.message}',
        cause: error,
      );
    } on StationTimetableUnavailable {
      rethrow;
    } catch (_) {
      throw const StationTimetableUnavailable(
        'Journey timetable is unavailable.',
      );
    }
  }

  Future<StationTimetable> _map(
    contract.StationTimetableSearchSuccess response, {
    required String stationId,
    required String lineId,
    required contract.StationTimetableSelector selector,
  }) async {
    if (response.stationId != stationId ||
        response.lineId != lineId ||
        response.selector.toJson().toString() != selector.toJson().toString() ||
        response.serviceTimezone !=
            contract.StationTimetableServiceTimezone.asiaSeoul ||
        !response.sourceIdentity.freshUntil.isAfter(_now())) {
      throw const FormatException(
        'Station timetable identity or freshness mismatch',
      );
    }
    // 방면은 다음 정차역(backend #479 nextStationId)으로 묶고 이름은 앱
    // 카탈로그에서 붙인다. 원천 방면 이름(directionName)은 라벨에 쓰지 않고,
    // 방면 문자열을 잘라 행선지를 만들지 않는다.
    final nextStationIds = <String>{};
    final directions = <StationTimetableDirection>[];
    final names = <String, String>{};
    Future<String> stationName(String stationId) async {
      final cached = names[stationId];
      if (cached != null) return cached;
      final String name;
      try {
        name = await _stationNameResolver(stationId);
      } catch (_) {
        throw const StationTimetableUnavailable(
          'TIMETABLE_STATION_NAME_UNAVAILABLE',
        );
      }
      if (name.trim().isEmpty) {
        throw const StationTimetableUnavailable(
          'TIMETABLE_STATION_NAME_UNAVAILABLE',
        );
      }
      return names[stationId] = name;
    }

    for (final group in response.directionGroups) {
      final nextStationId = group.nextStationId;
      if (!nextStationIds.add(nextStationId)) {
        throw const FormatException('Station timetable direction mismatch');
      }
      final directionName = '${await stationName(nextStationId)} 방면';
      DateTime? previousDepartureAt;
      final departures = <StationTimetableDeparture>[];
      for (final departure in group.departures) {
        if ((previousDepartureAt != null &&
                departure.departureAt.isBefore(previousDepartureAt)) ||
            departure.secondsFromServiceDayStart < 0 ||
            departure.secondsFromServiceDayStart > 107999 ||
            !_matchesSeoulServiceDate(departure)) {
          throw const FormatException(
            'Station timetable departure ordering mismatch',
          );
        }
        previousDepartureAt = departure.departureAt;
        final destination = await stationName(departure.terminalStationId);
        departures.add(
          StationTimetableDeparture(
            directionName: directionName,
            seconds: departure.secondsFromServiceDayStart,
            departureAt: departure.departureAt,
            destination: destination,
            servicePattern: departure.servicePattern.wire,
            serviceClass: departure.serviceClass.wire,
          ),
        );
      }
      if (departures.isNotEmpty) {
        directions.add(
          StationTimetableDirection(
            name: directionName,
            departures: List.unmodifiable(departures),
          ),
        );
      }
    }
    return StationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: _fromContractDayType(response.resolvedDayType),
      directions: List.unmodifiable(directions),
      serviceDate: switch (response.selector) {
        final contract.StationTimetableServiceDateSelector date =>
          date.serviceDate.toString(),
        final contract.StationTimetableDayTypeSelector dayType =>
          dayType.referenceDate.toString(),
        contract.StationTimetableNextDeparturesSelector() => null,
      },
    );
  }

  bool _matchesSeoulServiceDate(contract.StationTimetableDeparture departure) {
    return _serviceDayInstantUtc(
      departure.serviceDate.toString(),
      departure.secondsFromServiceDayStart,
    ).isAtSameMomentAs(departure.departureAt.toUtc());
  }

  DateTime _serviceDayInstantUtc(String serviceDate, int seconds) {
    final parts = serviceDate.split('-').map(int.parse).toList(growable: false);
    if (parts.length != 3 || seconds < 0 || seconds > 107999) {
      throw const FormatException('Station timetable service day is invalid');
    }
    return DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
    ).subtract(const Duration(hours: 9)).add(Duration(seconds: seconds));
  }

  String _seoulDate(DateTime instant) {
    final seoul = instant.toUtc().add(const Duration(hours: 9));
    return '${seoul.year.toString().padLeft(4, '0')}-${seoul.month.toString().padLeft(2, '0')}-${seoul.day.toString().padLeft(2, '0')}';
  }

  /// [referenceDate]의 서울 날짜부터 [dayType] 탭에 해당하는 첫 날짜.
  /// 평일 탭은 월~금, 토요일 탭은 토요일, 공휴일 탭은 일요일이다. 그 날이
  /// 실제로 어떤 시간표로 운행하는지는 서버가 판정한다.
  String _nextSeoulDateFor(
    StationTimetableDayType dayType,
    DateTime referenceDate,
  ) {
    final seoul = referenceDate.toUtc().add(const Duration(hours: 9));
    var date = DateTime.utc(seoul.year, seoul.month, seoul.day);
    bool matches(DateTime value) => switch (dayType) {
      StationTimetableDayType.weekday => value.weekday <= DateTime.friday,
      StationTimetableDayType.saturday => value.weekday == DateTime.saturday,
      StationTimetableDayType.sundayHoliday => value.weekday == DateTime.sunday,
    };
    while (!matches(date)) {
      date = date.add(const Duration(days: 1));
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  StationTimetableDayType _fromContractDayType(
    contract.StationTimetableDayType value,
  ) => switch (value) {
    contract.StationTimetableDayType.weekday => StationTimetableDayType.weekday,
    contract.StationTimetableDayType.saturday =>
      StationTimetableDayType.saturday,
    contract.StationTimetableDayType.sundayHoliday =>
      StationTimetableDayType.sundayHoliday,
  };
}

class StationTimetableUnavailable implements Exception {
  const StationTimetableUnavailable(this.reason);
  final String reason;
}
