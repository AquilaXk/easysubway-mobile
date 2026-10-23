import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../domain/journey_profile_models.dart';

/// 경로 검색의 출발 기준. 서버가 받는 요청 모드만 둔다(지금 출발, 출발 시각
/// 지정, 막차). 도착 시각과 첫차는 서버 요청 모드가 없어 두지 않는다.
sealed class JourneyDepartureChoice {
  const JourneyDepartureChoice();
}

final class JourneyDepartNow extends JourneyDepartureChoice {
  const JourneyDepartNow();
}

/// [requestedAt]은 UTC 시각이다.
final class JourneyDepartAt extends JourneyDepartureChoice {
  const JourneyDepartAt(this.requestedAt);

  final DateTime requestedAt;
}

/// [serviceDay]는 서울 날짜를 `DateTime.utc(연, 월, 일)`로 담는다.
final class JourneyLastTrain extends JourneyDepartureChoice {
  const JourneyLastTrain(this.serviceDay);

  final DateTime serviceDay;

  String get serviceDate =>
      '${serviceDay.year.toString().padLeft(4, '0')}-'
      '${serviceDay.month.toString().padLeft(2, '0')}-'
      '${serviceDay.day.toString().padLeft(2, '0')}';
}

const _seoulOffset = Duration(hours: 9);
const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// UTC 시각을 서울 벽시계 값(연·월·일·시·분)으로 바꾼다.
DateTime journeySeoulWallTime(DateTime instant) {
  final value = instant.toUtc().add(_seoulOffset);
  return DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
  );
}

/// 서울 벽시계 값을 UTC 시각으로 바꾼다.
DateTime journeyInstantFromSeoul(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
).subtract(_seoulOffset);

DateTime _seoulDay(DateTime wall) =>
    DateTime.utc(wall.year, wall.month, wall.day);

/// 운행일 경계. Journey V3 계약의 `serviceDayCutoff`가 `03:00` 하나만 허용한다
/// (backend `contracts/api/journey-v3.openapi.yaml` JourneySearchSuccess).
const _serviceDayCutoff = Duration(hours: 3);

/// [now]가 속한 운행일(서울 날짜). 03:00 전은 전날 운행일이다.
DateTime journeyCurrentServiceDay(DateTime now) =>
    _seoulDay(journeySeoulWallTime(now.subtract(_serviceDayCutoff)));

/// 오늘·내일, 그 밖에는 `10월 26일(월)`. [day]와 [today]는 서울 날짜다.
String journeyDayLabel(DateTime day, DateTime today) {
  final offset = _seoulDay(day).difference(_seoulDay(today)).inDays;
  if (offset == 0) return '오늘';
  if (offset == 1) return '내일';
  return '${day.month}월 ${day.day}일(${_weekdays[day.weekday - 1]})';
}

String _clock(DateTime wall) =>
    '${wall.hour.toString().padLeft(2, '0')}:'
    '${wall.minute.toString().padLeft(2, '0')}';

/// 시간 줄 가운데 문구(`오늘 00:36 출발`, `내일 08:05 출발`, `오늘 막차`).
String journeyDepartureBarLabel(JourneyDepartureChoice choice, DateTime now) {
  final today = journeySeoulWallTime(now);
  return switch (choice) {
    JourneyDepartNow() =>
      '${journeyDayLabel(today, today)} ${_clock(today)} 출발',
    JourneyDepartAt(:final requestedAt) => () {
      final wall = journeySeoulWallTime(requestedAt);
      return '${journeyDayLabel(wall, today)} ${_clock(wall)} 출발';
    }(),
    JourneyLastTrain(:final serviceDay) =>
      '${journeyDayLabel(serviceDay, today)} 막차',
  };
}

/// 출발 기준을 서버 요청의 출발(`departure`)과 프로필 질의로 바꾼다. 막차는
/// 운행일 하나만 보내는 `LAST_CONNECTION` 프로필 질의다.
(JourneyDeparture, JourneyTemporalQuery?) journeyDepartureRequest(
  JourneyDepartureChoice choice,
) => switch (choice) {
  JourneyDepartNow() => (const JourneyDepartureNow(), null),
  JourneyDepartAt(:final requestedAt) => (
    JourneyDepartureScheduled(requestedAt),
    null,
  ),
  final JourneyLastTrain lastTrain => (
    JourneyDepartureScheduled(lastTrain.serviceDay),
    JourneyLastConnectionQuery(serviceDate: lastTrain.serviceDate),
  ),
};
