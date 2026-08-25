import '../../../generated/journey_v3/journey_v3_contract.dart' as contract;
import '../../journey/application/journey_session_provider.dart';
import '../../journey/domain/journey_repository.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

/// Server-authoritative timetable adapter. It never consults the catalog or
/// retains a prior timetable when the Journey V3 operation rejects a request.
class ServerStationTimetableRepository implements StationTimetableRepository {
  ServerStationTimetableRepository({
    required JourneyRepository journeyRepository,
    required JourneySessionProvider sessionProvider,
    DateTime Function()? now,
  }) : this._(journeyRepository, sessionProvider, now ?? DateTime.now);

  ServerStationTimetableRepository._(
    this._journeyRepository,
    this._sessionProvider,
    this._now,
  );

  final JourneyRepository _journeyRepository;
  final JourneySessionProvider _sessionProvider;
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
    contract.StationTimetableDayTypeSelector(
      dayType: _toContractDayType(dayType),
      referenceDate: contract.JourneyDate.parse(_seoulDate(referenceDate)),
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
    try {
      final session = await _sessionProvider.session();
      final response = await _journeyRepository.searchStationTimetables(
        contract.StationTimetableSearchRequest(
          stationId: stationId,
          lineId: lineId,
          selector: selector,
        ),
        sessionToken: session.token,
      );
      return _map(
        response,
        stationId: stationId,
        lineId: lineId,
        selector: selector,
      );
    } on JourneyRejectedFailure catch (error) {
      if (error.statusCode == 401) _sessionProvider.invalidate();
      throw StationTimetableUnavailable(error.error.code.wire);
    } on JourneySessionInvalid {
      throw const StationTimetableUnavailable(
        'Journey session is unavailable.',
      );
    } on JourneyRepositoryFailure catch (error) {
      throw StationTimetableUnavailable(error.operation.wire);
    } on FormatException catch (error) {
      throw StationTimetableUnavailable(error.message);
    } catch (_) {
      throw const StationTimetableUnavailable(
        'Journey timetable is unavailable.',
      );
    }
  }

  StationTimetable _map(
    contract.StationTimetableSearchSuccess response, {
    required String stationId,
    required String lineId,
    required contract.StationTimetableSelector selector,
  }) {
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
    final directionNames = <String>{};
    final directions = <StationTimetableDirection>[];
    for (final group in response.directionGroups) {
      if (group.directionName.trim().isEmpty ||
          !directionNames.add(group.directionName)) {
        throw const FormatException('Station timetable direction mismatch');
      }
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
        departures.add(
          StationTimetableDeparture(
            directionName: group.directionName,
            seconds: departure.secondsFromServiceDayStart,
            departureAt: departure.departureAt,
            servicePattern: departure.servicePattern.wire,
            serviceClass: departure.serviceClass.wire,
          ),
        );
      }
      if (departures.isNotEmpty) {
        directions.add(
          StationTimetableDirection(
            name: group.directionName,
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
    );
  }

  bool _matchesSeoulServiceDate(contract.StationTimetableDeparture departure) {
    try {
      return _serviceDayInstantUtc(
        departure.serviceDate.toString(),
        departure.secondsFromServiceDayStart,
      ).isAtSameMomentAs(departure.departureAt.toUtc());
    } on FormatException {
      return false;
    }
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

  contract.StationTimetableDayType _toContractDayType(
    StationTimetableDayType value,
  ) => switch (value) {
    StationTimetableDayType.weekday => contract.StationTimetableDayType.weekday,
    StationTimetableDayType.saturday =>
      contract.StationTimetableDayType.saturday,
    StationTimetableDayType.sundayHoliday =>
      contract.StationTimetableDayType.sundayHoliday,
  };

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
