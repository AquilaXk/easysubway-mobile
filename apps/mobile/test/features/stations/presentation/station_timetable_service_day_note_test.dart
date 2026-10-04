import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버가 판정한 요일 종류를 돌려주는 가짜 저장소. 토요일 탭 요청에 휴일 달력
/// 기관처럼 공휴일 시간표를 답한다.
class _SaturdayHolidayRepository implements StationTimetableRepository {
  final requested = <StationTimetableDayType>[];

  StationTimetable _timetable(StationTimetableDayType dayType, String date) =>
      StationTimetable(
        stationId: 'station-gangnam',
        lineId: 'seoul-2',
        dayType: dayType,
        serviceDate: date,
        directions: const [
          StationTimetableDirection(
            name: '역삼 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '역삼 방면',
                seconds: 36000,
                destination: '성수',
              ),
            ],
          ),
        ],
      );

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    requested.add(dayType);
    return switch (dayType) {
      StationTimetableDayType.saturday => _timetable(
        StationTimetableDayType.sundayHoliday,
        '2026-10-10',
      ),
      _ => _timetable(dayType, '2026-10-07'),
    };
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async => _timetable(StationTimetableDayType.weekday, '2026-10-07');

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) => loadStationTimetableForDate(
    stationId: stationId,
    lineId: lineId,
    date: asOf,
  );
}

void main() {
  testWidgets('토요일 탭에 서버가 공휴일 시간표를 답하면 그 날짜와 서버 요일 종류를 알린다(#437 리뷰 F1)', (
    tester,
  ) async {
    final repository = _SaturdayHolidayRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: StationTimetableScreen(
          stationId: 'station-gangnam',
          stationName: '강남',
          lines: const [
            StationSearchLine(
              id: 'seoul-2',
              name: '2호선',
              color: '#00A84D',
              stationCode: '222',
            ),
          ],
          repository: repository,
          now: DateTime(2026, 10, 7, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('station-timetable-service-day-note')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('stationTimetableDay-saturday')));
    await tester.pumpAndSettle();

    expect(repository.requested, [StationTimetableDayType.saturday]);
    expect(find.text('10월 10일(토)은 공휴일 시간표로 운행해요'), findsOneWidget);
  });
}
