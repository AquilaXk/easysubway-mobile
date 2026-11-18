import 'package:clock/clock.dart';
import 'package:easysubway_mobile/features/facility_report/domain/facility_report_target.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SaturdayHolidayRepository implements StationTimetableRepository {
  final requested = <StationTimetableDayType>[];
  final requestedDates = <DateTime>[];
  final requestedReferenceDates = <DateTime>[];

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
              StationTimetableDeparture(
                directionName: '역삼 방면',
                seconds: 87600,
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
    requestedReferenceDates.add(referenceDate);
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
  }) async {
    requestedDates.add(date);
    final dayType = switch (date.weekday) {
      DateTime.saturday => StationTimetableDayType.saturday,
      DateTime.sunday => StationTimetableDayType.sundayHoliday,
      _ => StationTimetableDayType.weekday,
    };
    return _timetable(dayType, '2026-10-07');
  }

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
          now: DateTime.utc(2026, 10, 7, 0),
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

  testWidgets(
    '월요일 00:15 KST(UTC 일요일 15:15)에는 역 시간표 화면과 역 상세 요약 모두 일요일 운행일로 조회하고 서울 벽시계로 카운트다운한다',
    (tester) async {
      final monday0015Kst = DateTime.utc(2026, 7, 5, 15, 15);
      final screenRepo = _SaturdayHolidayRepository();
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
            repository: screenRepo,
            now: monday0015Kst,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(screenRepo.requestedDates, [DateTime.utc(2026, 7, 5)]);
      expect(
        find.byKey(const Key('stationTimetableServiceDayNote')),
        findsNothing,
      );
      expect(find.text('5분 뒤 도착'), findsOneWidget);

      final detailRepo = _SaturdayHolidayRepository();
      await withClock(Clock.fixed(monday0015Kst), () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StationDetailBody(
                state: const StationDetailState(
                  status: StationDetailStatus.success,
                  detail: StationDetail(
                    id: 'station-gangnam',
                    nameKo: '강남',
                    nameEn: 'Gangnam',
                    region: '수도권',
                    dataQualityLevel: 'HIGH',
                    lastVerifiedAt: '2026-07-01',
                    lines: [
                      StationSearchLine(
                        id: 'seoul-2',
                        name: '2호선',
                        color: '#00A84D',
                        stationCode: '222',
                      ),
                    ],
                  ),
                  exits: [],
                  facilities: [],
                ),
                onRetryRealtime: _noop,
                onOpenFacilityReport: _noopReport,
                timetableRepository: detailRepo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      expect(detailRepo.requestedDates, [DateTime.utc(2026, 7, 5)]);
    },
  );
}

void _noop() {}
Future<void> _noopReport(FacilityReportTarget _) async {}
