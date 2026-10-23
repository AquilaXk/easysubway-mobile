import 'package:easysubway_mobile/features/journey/domain/journey_profile_models.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_departure_choice.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

// 시각은 서울 시각으로 적고 UTC로 바꿔 넣는다. 기대값은 손으로 적는다.
DateTime _seoul(int day, int hour, int minute) => DateTime.utc(
  2026,
  10,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 9));

void main() {
  test('운행일은 03:00 경계 전이면 전날이다', () {
    expect(
      journeyCurrentServiceDay(_seoul(24, 2, 59)),
      DateTime.utc(2026, 10, 23),
    );
    expect(
      journeyCurrentServiceDay(_seoul(24, 3, 0)),
      DateTime.utc(2026, 10, 24),
    );
    expect(
      journeyCurrentServiceDay(_seoul(24, 23, 59)),
      DateTime.utc(2026, 10, 24),
    );
  });

  test('날짜 문구는 오늘·내일, 그 밖에는 월 일(요일)이다', () {
    final today = DateTime.utc(2026, 10, 24);
    expect(journeyDayLabel(today, today), '오늘');
    expect(journeyDayLabel(DateTime.utc(2026, 10, 25), today), '내일');
    expect(journeyDayLabel(DateTime.utc(2026, 10, 26), today), '10월 26일(월)');
    expect(journeyDayLabel(DateTime.utc(2026, 10, 23), today), '10월 23일(금)');
  });

  test('시간 줄 문구는 출발 기준마다 서울 시각으로 쓴다', () {
    final now = _seoul(24, 0, 36);
    expect(
      journeyDepartureBarLabel(const JourneyDepartNow(), now),
      '오늘 00:36 출발',
    );
    expect(
      journeyDepartureBarLabel(JourneyDepartAt(_seoul(25, 8, 5)), now),
      '내일 08:05 출발',
    );
    expect(
      journeyDepartureBarLabel(
        JourneyLastTrain(DateTime.utc(2026, 10, 23)),
        now,
      ),
      '10월 23일(금) 막차',
    );
  });

  test('출발 기준은 서버가 받는 요청 모드로만 바뀐다', () {
    final (now, nowQuery) = journeyDepartureRequest(const JourneyDepartNow());
    expect(now, isA<JourneyDepartureNow>());
    expect(nowQuery, isNull);

    final at = _seoul(25, 8, 5);
    final (scheduled, scheduledQuery) = journeyDepartureRequest(
      JourneyDepartAt(at),
    );
    expect((scheduled as JourneyDepartureScheduled).requestedAt, at);
    expect(scheduledQuery, isNull);

    final (_, lastQuery) = journeyDepartureRequest(
      JourneyLastTrain(DateTime.utc(2026, 10, 23)),
    );
    expect(
      (lastQuery! as JourneyLastConnectionQuery).serviceDate,
      '2026-10-23',
    );
  });

  test('서울 벽시계와 UTC 변환은 서로 되돌린다', () {
    final instant = _seoul(24, 0, 36);
    final wall = journeySeoulWallTime(instant);
    expect(
      (wall.year, wall.month, wall.day, wall.hour, wall.minute),
      (2026, 10, 24, 0, 36),
    );
    expect(journeyInstantFromSeoul(wall), instant);
  });
}
