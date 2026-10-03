import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_timetable_screen.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingRepository implements StationTimetableRepository {
  _ThrowingRepository(this.error);
  final Object error;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async => throw error;

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async => throw error;

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async => throw error;
}

void main() {
  // #437 리뷰 F2: 서버가 명시적으로 답한 실패는 로컬 시간표로 덮지 않고, 사실과
  // 행동으로 상태를 보인다. 네트워크에 닿지 못한 경우만 연결 안내를 보인다.
  for (final (name, error, text, networkView)
      in <(String, Object, String, bool)>[
        (
          'server unavailable or stale',
          const ServerConnectionException('TIMETABLE_STALE', statusCode: 503),
          '지금은 시간표를 불러올 수 없어요',
          false,
        ),
        (
          'integrity violation',
          const ServerConnectionException(
            'Station timetable data integrity violation',
          ),
          '지금은 시간표를 불러올 수 없어요',
          false,
        ),
        (
          'station name unavailable',
          const StationTimetableUnavailable(
            'TIMETABLE_STATION_NAME_UNAVAILABLE',
          ),
          '지금은 시간표를 불러올 수 없어요',
          false,
        ),
        (
          'not covered',
          const StationTimetableUnavailable('TIMETABLE_NOT_COVERED'),
          '시간표 정보가 없어요',
          false,
        ),
        (
          'network unreachable',
          const ServerUnreachableException('Network transport failure'),
          '네트워크 연결 불안정',
          true,
        ),
      ]) {
    testWidgets('역 시간표는 $name 상태를 명시적으로 보인다', (tester) async {
      await runWithMobileErrorReporter((_) {}, () async {
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
              repository: _ThrowingRepository(error),
              now: DateTime(2026, 10, 7, 9),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      expect(find.text(text), findsOneWidget);
      expect(
        find.byKey(const Key('station-timetable-network-error-view')),
        networkView ? findsOneWidget : findsNothing,
      );
    });
  }
}
