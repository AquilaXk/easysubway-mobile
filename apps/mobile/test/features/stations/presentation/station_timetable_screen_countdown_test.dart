import 'package:clock/clock.dart';
import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_timetable_screen.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimetableRepo implements StationTimetableRepository {
  _FakeTimetableRepo(this.timetables, {this.errorToThrow});
  final Map<StationTimetableDayType, StationTimetable> timetables;
  Object? errorToThrow;

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final t = timetables[dayType];
    if (t == null) {
      throw const StationTimetableUnavailable('No timetable');
    }
    return t;
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    return loadStationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: StationTimetableDayType.weekday,
      referenceDate: date,
    );
  }

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async {
    return loadStationTimetableForDate(
      stationId: stationId,
      lineId: lineId,
      date: asOf,
    );
  }
}

void main() {
  testWidgets('시간표 화면은 다음 열차 카운트다운을 박스 없이 인라인 텍스트로 자연스럽게 결합한다', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 7, 6, 10, 0, 50)), () async {
      const line = StationSearchLine(
        id: 'seoul-2',
        name: '2호선',
        color: '#00A84D',
        stationCode: '222',
      );

      final timetable = StationTimetable(
        stationId: 'station-gangnam',
        lineId: 'seoul-2',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '외선순환',
            departures: [
              // 10:01 (36060초) -> 10초 뒤 (곧 출발)
              StationTimetableDeparture(directionName: '외선순환', seconds: 36060),
              // 10:03 (36180초) -> 1분 10초 뒤 (1분 뒤)
              StationTimetableDeparture(directionName: '외선순환', seconds: 36180),
              // 10:07 (36420초) -> 6분 뒤
              StationTimetableDeparture(directionName: '외선순환', seconds: 36420),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: timetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-gangnam',
            stationName: '강남',
            lines: const [line],
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 10:01(다음 열차)은 방면/행선지 선두, 정적 시각(10:01)과 '곧 도착' 텍스트를 함께 표시한다
      expect(find.text('10:01'), findsOneWidget);
      expect(find.text('외선순환'), findsAtLeastNWidgets(1));
      expect(find.text('곧 도착'), findsOneWidget);
      expect(find.text('· 곧 도착'), findsNothing);
      expect(find.text('· 곧 출발'), findsNothing);

      // 10:03, 10:07은 다음 열차가 아니므로 정적 시각을 표시하고 카운트다운이 없다
      expect(find.text('10:03'), findsOneWidget);
      expect(find.text('2분 뒤 도착'), findsNothing);

      // AI 슬롭 박스(Container decoration with Border)가 카운트다운을 감싸지 않는다
      // 인라인 Text 위젯으로 바로 렌더링되며 빨간색 볼드 강조
      final countdownWidget = tester.widget<Text>(find.text('곧 도착'));
      expect(
        countdownWidget.style?.color,
        EasySubwayColorPrimitives.statusDanger,
      );
      expect(countdownWidget.style?.fontWeight, FontWeight.w700);
      expect(countdownWidget.style?.fontSize, 13);

      // 25초 경과 (10:01:15) -> Ticker 2회 틱(20초) 실행되어 10:01 열차가 지나가고 다음 열차가 10:03으로 롤오버
      await tester.pump(const Duration(seconds: 25));

      // 10:01 열차는 지나가서 지난 열차 시각(10:01)으로 노출
      expect(find.text('10:01'), findsOneWidget);
      expect(find.text('곧 도착'), findsNothing);

      // 이제 10:03이 다음 열차가 되고 시각(10:03)과 함께 '2분 뒤 도착'으로 표시됨
      expect(find.text('10:03'), findsOneWidget);
      expect(find.text('2분 뒤 도착'), findsOneWidget);
      expect(find.text('· 2분 뒤 도착'), findsNothing);
      expect(find.text('· 2분 뒤'), findsNothing);

      final nextCountdown = tester.widget<Text>(find.text('2분 뒤 도착'));
      expect(nextCountdown.style?.color, EasySubwayAccessibleColors.amber);
      expect(nextCountdown.style?.fontWeight, FontWeight.w700);
      expect(nextCountdown.style?.fontSize, 13);
    });
  });

  testWidgets('시간표 화면은 인접역 기준 방면 칩 정규화 및 열차 종착역 행선지(사당행, 진접행)를 명확히 표시한다', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 7, 6, 10, 0, 0)), () async {
      const line = StationSearchLine(
        id: 'seoul-4',
        name: '4호선',
        color: '#00A4E3',
        stationCode: '449',
      );

      final timetable = StationTimetable(
        stationId: 'station-sangnoksu',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '진접 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '진접 방면',
                destination: '사당',
                seconds: 36060,
              ),
              StationTimetableDeparture(
                directionName: '진접 방면',
                destination: '진접',
                seconds: 36180,
              ),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: timetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            lines: const [line],
            repository: repo,
            previousStation: '반월',
            nextStation: '한대앞',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 방면 칩이 먼 종점 '진접 방면' 대신 인접역 '반월 방면'으로 정규화되어 노출됨
      expect(find.text('반월 방면'), findsOneWidget);

      // 각 출발 열차의 행선지 '사당행', '진접행'이 빠짐없이 명확하게 표시됨
      expect(find.text('사당행'), findsOneWidget);
      expect(find.text('진접행'), findsOneWidget);
    });
  });

  testWidgets(
    '심야 시간대(00:00~03:59)에도 24시 이후(86400+ 초) 열차 카운트다운과 곧 도착이 정상 동작한다',
    (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 7, 6, 0, 15, 0)), () async {
        const line = StationSearchLine(
          id: 'seoul-4',
          name: '4호선',
          color: '#00A4E3',
          stationCode: '449',
        );

        final timetable = StationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          directions: const [
            StationTimetableDirection(
              name: '오이도 방면',
              departures: [
                // 아침 첫차 05:30 (19800초)
                StationTimetableDeparture(
                  directionName: '오이도 방면',
                  destination: '오이도',
                  seconds: 19800,
                ),
                // 심야 열차 24:20 (87600초) -> 00:15 기준 5분 뒤
                StationTimetableDeparture(
                  directionName: '오이도 방면',
                  destination: '오이도',
                  seconds: 87600,
                ),
              ],
            ),
          ],
        );

        final repo = _FakeTimetableRepo({
          StationTimetableDayType.weekday: timetable,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: StationTimetableScreen(
              stationId: 'station-sangnoksu',
              stationName: '상록수',
              lines: const [line],
              repository: repo,
              previousStation: '반월',
              nextStation: '한대앞',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 아침 첫차 05:30으로 건너뛰지 않고 심야 24:20 열차를 다음 열차로 인식하여 '5분 뒤 도착' 표시
        expect(find.text('5분 뒤 도착'), findsOneWidget);
        expect(find.text('오이도행'), findsNWidgets(2));
      });
    },
  );

  testWidgets(
    '종착역 필터에서 개별 종착역 선택 시 해당 열차만 필터링되고 전체를 선택하면 전체 ∨ 표시와 함께 모든 열차가 복원된다',
    (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 7, 6, 10, 0, 0)), () async {
        const line = StationSearchLine(
          id: 'seoul-4',
          name: '4호선',
          color: '#00A4E3',
          stationCode: '449',
        );

        final timetable = StationTimetable(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
          dayType: StationTimetableDayType.weekday,
          directions: const [
            StationTimetableDirection(
              name: '진접 방면',
              departures: [
                StationTimetableDeparture(
                  directionName: '진접 방면',
                  destination: '사당',
                  seconds: 36060, // 10:01
                ),
                StationTimetableDeparture(
                  directionName: '진접 방면',
                  destination: '진접',
                  seconds: 36180, // 10:03
                ),
              ],
            ),
          ],
        );

        final repo = _FakeTimetableRepo({
          StationTimetableDayType.weekday: timetable,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: StationTimetableScreen(
              stationId: 'station-sangnoksu',
              stationName: '상록수',
              lines: const [line],
              repository: repo,
              previousStation: '반월',
              nextStation: '한대앞',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 초기 상태: 사당행, 진접행 모두 노출됨
        expect(find.text('사당행'), findsOneWidget);
        expect(find.text('진접행'), findsOneWidget);

        // 종착역 드롭다운 탭
        final dropdownFinder = find.byKey(
          const Key('stationTimetableTerminusDropdown-진접 방면'),
        );
        expect(dropdownFinder, findsOneWidget);
        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        // '사당' 선택
        final sadangItemFinder = find.byKey(
          const Key('stationTimetableTerminusItem-사당'),
        );
        expect(sadangItemFinder, findsOneWidget);
        await tester.tap(sadangItemFinder);
        await tester.pumpAndSettle();

        // 드롭다운 텍스트가 '사당행'으로 갱신되고, 사당행만 노출, 진접행은 필터링됨
        expect(find.text('사당행'), findsWidgets);
        expect(find.text('진접행'), findsNothing);

        // 다시 드롭다운 탭 후 '전체' 선택
        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        final allItemFinder = find.byKey(
          const Key('stationTimetableTerminusItem-all'),
        );
        expect(allItemFinder, findsOneWidget);
        await tester.tap(allItemFinder);
        await tester.pumpAndSettle();

        // '전체' 텍스트가 드롭다운에 표시되고, 사당행과 진접행 모두 다시 노출됨
        expect(find.text('전체'), findsWidgets);
        expect(find.text('사당행'), findsOneWidget);
        expect(find.text('진접행'), findsOneWidget);
      });
    },
  );

  testWidgets('전국 모든 노선(부산 1호선, 대구 1호선, 2호선 순환선 등)에서 하드코딩 없이 방면명이 정확히 정규화된다', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 7, 6, 10, 0, 0)), () async {
      // 1. 부산 1호선 서면역 (부전 <-> 서면 <-> 범내골)
      const busanLine = StationSearchLine(
        id: 'busan-1',
        name: '부산 1호선',
        color: '#F99D1C',
        stationCode: '119',
      );

      final busanTimetable = StationTimetable(
        stationId: 'station-seomyeon',
        lineId: 'busan-1',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '노포 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '노포 방면',
                destination: '노포',
                seconds: 36000,
              ),
            ],
          ),
          StationTimetableDirection(
            name: '다대포해수욕장 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '다대포해수욕장 방면',
                destination: '다대포해수욕장',
                seconds: 36060,
              ),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: busanTimetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-seomyeon',
            stationName: '서면',
            lines: const [busanLine],
            repository: repo,
            previousStation: '부전',
            nextStation: '범내골',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 좌우 2열에서 이전역/다음역 기준 정규화 검증
      expect(find.text('부전 방면'), findsOneWidget);
      expect(find.text('범내골 방면'), findsOneWidget);
      expect(find.text('노포행'), findsOneWidget);
      expect(find.text('다대포해수욕장행'), findsOneWidget);

      // 2. 대구 1호선 반월당역 (중앙로 <-> 반월당 <-> 명덕)
      const daeguLine = StationSearchLine(
        id: 'daegu-1',
        name: '대구 1호선',
        color: '#D93B30',
        stationCode: '130',
      );

      final daeguTimetable = StationTimetable(
        stationId: 'station-banwoldang',
        lineId: 'daegu-1',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '안심 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '안심 방면',
                destination: '안심',
                seconds: 36000,
              ),
              StationTimetableDeparture(
                directionName: '안심 방면',
                destination: '안심',
                seconds: 36120,
              ),
            ],
          ),
          StationTimetableDirection(
            name: '설화명곡 방면',
            departures: [
              StationTimetableDeparture(
                directionName: '설화명곡 방면',
                destination: '설화명곡',
                seconds: 36060,
              ),
              StationTimetableDeparture(
                directionName: '설화명곡 방면',
                destination: '설화명곡',
                seconds: 36180,
              ),
            ],
          ),
        ],
      );

      final daeguRepo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: daeguTimetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-banwoldang',
            stationName: '반월당',
            lines: const [daeguLine],
            repository: daeguRepo,
            previousStation: '중앙로',
            nextStation: '명덕',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('중앙로 방면'), findsOneWidget);
      expect(find.text('명덕 방면'), findsOneWidget);
      expect(find.text('안심행'), findsWidgets);
      expect(find.text('설화명곡행'), findsWidgets);
    });
  });

  testWidgets('첫·막차 및 급행 필터 토글 시 첫/막 뱃지가 유지되고 필터된 시간대 알약 탭이 안정적으로 스크롤된다', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 7, 6, 6, 0, 0)), () async {
      const line = StationSearchLine(
        id: 'seoul-1',
        name: '1호선',
        color: '#0052A4',
        stationCode: '100',
      );

      final timetable = StationTimetable(
        stationId: 'station-cheongnyangni',
        lineId: 'seoul-1',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '소요산 방면',
            departures: [
              // 06:10 일반 (첫차)
              StationTimetableDeparture(
                directionName: '소요산 방면',
                destination: '소요산',
                seconds: 22200, // 06:10:00
                servicePattern: 'LOCAL',
              ),
              // 07:20 급행
              StationTimetableDeparture(
                directionName: '소요산 방면',
                destination: '동두천',
                seconds: 26400, // 07:20:00
                servicePattern: 'EXPRESS',
              ),
              // 08:30 급행
              StationTimetableDeparture(
                directionName: '소요산 방면',
                destination: '소요산',
                seconds: 30600, // 08:30:00
                servicePattern: 'EXPRESS',
              ),
              // 23:40 일반 (막차)
              StationTimetableDeparture(
                directionName: '소요산 방면',
                destination: '의정부',
                seconds: 85200, // 23:40:00
                servicePattern: 'LOCAL',
              ),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: timetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-cheongnyangni',
            stationName: '청량리',
            lines: const [line],
            repository: repo,
            previousStation: '제기동',
            nextStation: '회기',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 전체 열차 4편 노출 확인
      expect(find.text('06:10'), findsOneWidget);
      expect(find.text('07:20'), findsOneWidget);
      expect(find.text('첫차'), findsOneWidget);
      expect(find.text('막차'), findsOneWidget);

      // '첫·막차' 필터 캡슐 탭
      await tester.tap(find.byKey(const Key('stationTimetableFilter-첫·막차')));
      await tester.pumpAndSettle();

      // 첫차(06:10)와 막차(23:40)만 노출되고 중간 열차(07:20, 08:30)는 숨겨짐
      expect(find.text('06:10'), findsOneWidget);
      expect(find.text('23:40'), findsOneWidget);
      expect(find.text('07:20'), findsNothing);
      expect(find.text('08:30'), findsNothing);
      expect(find.text('첫차'), findsOneWidget);
      expect(find.text('막차'), findsOneWidget);

      // '첫·막차' 필터 해제
      await tester.tap(find.byKey(const Key('stationTimetableFilter-첫·막차')));
      await tester.pumpAndSettle();

      // '급행' 필터 캡슐 탭
      await tester.tap(find.byKey(const Key('stationTimetableFilter-급행')));
      await tester.pumpAndSettle();

      // 급행 2편(07:20, 08:30)만 노출됨
      expect(find.text('07:20'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('06:10'), findsNothing);
      expect(find.text('23:40'), findsNothing);

      // 급행 필터 상태에서 8시 알약 탭 시 오류 없이 안정적으로 동작
      expect(find.text('8시'), findsWidgets);
      await tester.tap(find.text('8시').first);
      await tester.pumpAndSettle();
    });
  });

  test('formatStationDirectionName은 다양한 인접역, 토큰, 인덱스 조건에 따라 방면명을 정규화한다', () {
    // 1. Direct match with adjacent
    expect(
      formatStationDirectionName('제기동 방면', previousStation: '제기동'),
      '제기동 방면',
    );
    expect(formatStationDirectionName('회기 방면', nextStation: '회기'), '회기 방면');

    // 2. Generic tokens
    expect(formatStationDirectionName('상행', previousStation: '제기동'), '제기동 방면');
    expect(
      formatStationDirectionName('내선순환', previousStation: '제기동'),
      '제기동 방면',
    );
    expect(formatStationDirectionName('하행', nextStation: '회기'), '회기 방면');
    expect(formatStationDirectionName('외선순환', nextStation: '회기'), '회기 방면');

    // 3. Direction index fallback
    expect(
      formatStationDirectionName(
        '방면',
        previousStation: '제기동',
        directionIndex: 0,
      ),
      '제기동 방면',
    );
    expect(
      formatStationDirectionName('방면', nextStation: '회기', directionIndex: 1),
      '회기 방면',
    );

    // 4. Terminal station
    expect(
      formatStationDirectionName('임의', previousStation: '제기동', nextStation: ''),
      '제기동 방면',
    );
    expect(
      formatStationDirectionName('임의', nextStation: '회기', previousStation: ''),
      '회기 방면',
    );

    // 5. Fallback
    expect(formatStationDirectionName('미정 방면'), '미정 방면');
    expect(formatStationDirectionName('미정'), '미정 방면');
  });

  testWidgets(
    'StationTimetableScreen은 다중 노선 선택, 닫기, 라이프사이클 및 1편 열차 첫막차 필터를 정상 처리한다',
    (tester) async {
      const line1 = StationSearchLine(
        id: 'seoul-1',
        name: '1호선',
        color: '#0052A4',
        stationCode: '123',
      );
      const line2 = StationSearchLine(
        id: 'seoul-2',
        name: '2호선',
        color: '#00A84D',
        stationCode: '222',
      );

      final timetable1 = StationTimetable(
        stationId: 'station-test',
        lineId: 'seoul-1',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '상행',
            departures: [
              // 1편만 있는 열차 (first == last)
              StationTimetableDeparture(
                directionName: '상행',
                destination: '소요산',
                seconds: 36000,
              ),
            ],
          ),
          StationTimetableDirection(
            name: '하행',
            departures: [
              StationTimetableDeparture(
                directionName: '하행',
                destination: '인천',
                seconds: 36000,
              ),
              StationTimetableDeparture(
                directionName: '하행',
                destination: '수원',
                seconds: 40000,
              ),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: timetable1,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-test',
            stationName: '테스트역',
            lines: const [line1, line2],
            repository: repo,
            previousStation: '이전역',
            nextStation: '다음역',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 라이프사이클 이벤트
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // 2. 닫기 버튼 탭
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 3. 다중 노선 ChoiceChip 탭
      final line2Chip = find.byKey(const Key('stationTimetableLine-seoul-2'));
      if (line2Chip.evaluate().isNotEmpty) {
        await tester.tap(line2Chip);
        await tester.pumpAndSettle();
      }

      // 4. didUpdateWidget 트리거
      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-test-updated',
            stationName: '테스트역2',
            lines: const [line2],
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    '시간표 화면은 isOfflineFallback이 true일 때 오프라인 안내 배너를 렌더링하고 false일 때는 숨긴다',
    (tester) async {
      const line = StationSearchLine(
        id: 'seoul-2',
        name: '2호선',
        color: '#00A84D',
        stationCode: '222',
      );

      final offlineTimetable = StationTimetable(
        stationId: 'station-gangnam',
        lineId: 'seoul-2',
        dayType: StationTimetableDayType.weekday,
        isOfflineFallback: true,
        directions: const [
          StationTimetableDirection(
            name: '외선순환',
            departures: [
              StationTimetableDeparture(directionName: '외선순환', seconds: 36000),
            ],
          ),
        ],
      );

      final onlineTimetable = StationTimetable(
        stationId: 'station-gangnam',
        lineId: 'seoul-2',
        dayType: StationTimetableDayType.weekday,
        isOfflineFallback: false,
        directions: const [
          StationTimetableDirection(
            name: '외선순환',
            departures: [
              StationTimetableDeparture(directionName: '외선순환', seconds: 36000),
            ],
          ),
        ],
      );

      // 1. 오프라인 시간표일 때 배너 표시 확인
      final offlineRepo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: offlineTimetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-gangnam',
            stationName: '강남',
            lines: const [line],
            repository: offlineRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stationTimetableOfflineBanner')),
        findsOneWidget,
      );
      expect(
        find.text('오프라인 모드: 기기에 저장된 시간표를 표시하고 있어요. 최신 운행 정보와 다를 수 있어요.'),
        findsOneWidget,
      );

      // 2. 온라인 정상 시간표일 때 배너 미노출 확인
      final onlineRepo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: onlineTimetable,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-gangnam',
            stationName: '강남',
            lines: const [line],
            repository: onlineRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stationTimetableOfflineBanner')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'StationTimetableScreen displays network error view and retries successfully when ServerConnectionException occurs',
    (tester) async {
      final reportedErrors = <FlutterErrorDetails>[];
      const line = StationSearchLine(
        id: 'seoul-2',
        name: '2호선',
        color: '#00A84D',
        stationCode: '222',
      );

      final timetable = StationTimetable(
        stationId: 'station-gangnam',
        lineId: 'seoul-2',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '외선순환',
            departures: [
              StationTimetableDeparture(directionName: '외선순환', seconds: 36000),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo(
        {StationTimetableDayType.weekday: timetable},
        errorToThrow: const ServerConnectionException(
          '503 Service Unavailable',
          statusCode: 503,
        ),
      );

      await runWithMobileErrorReporter(reportedErrors.add, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: StationTimetableScreen(
              stationId: 'station-gangnam',
              stationName: '강남',
              lines: const [line],
              repository: repo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('station-timetable-network-error-view')),
          findsOneWidget,
        );
        expect(find.text('네트워크 연결 불안정'), findsOneWidget);
        expect(
          find.text('시간표 정보를 불러올 수 없어요.\n네트워크 상태를 확인하고 다시 시도해 주세요.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('station-timetable-retry-button')),
          findsOneWidget,
        );
        expect(find.text('시간표 정보가 없어요'), findsNothing);
        expect(reportedErrors, isNotEmpty);

        // When user taps retry after network recovers
        repo.errorToThrow = null;
        await tester.tap(
          find.byKey(const Key('station-timetable-retry-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('station-timetable-network-error-view')),
          findsNothing,
        );
        expect(find.text('외선순환'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'StationTimetableScreen displays empty timetable state without network error view when StationTimetableUnavailable occurs',
    (tester) async {
      final reportedErrors = <FlutterErrorDetails>[];
      const line = StationSearchLine(
        id: 'seoul-2',
        name: '2호선',
        color: '#00A84D',
        stationCode: '222',
      );

      final repo = _FakeTimetableRepo(
        {},
        errorToThrow: const StationTimetableUnavailable('NOT_COVERED'),
      );

      await runWithMobileErrorReporter(reportedErrors.add, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: StationTimetableScreen(
              stationId: 'station-gangnam',
              stationName: '강남',
              lines: const [line],
              repository: repo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('station-timetable-network-error-view')),
          findsNothing,
        );
        expect(find.text('시간표 정보가 없어요'), findsOneWidget);
        expect(reportedErrors, isEmpty);
      });
    },
  );

  testWidgets(
    '운행일 변경 시 서버 장애(ServerConnectionException)가 발생하면 네트워크 에러 뷰를 렌더링한다',
    (tester) async {
      final reportedErrors = <FlutterErrorDetails>[];
      const line = StationSearchLine(
        id: 'seoul-2',
        name: '2호선',
        color: '#00A84D',
        stationCode: '222',
      );

      final timetable = StationTimetable(
        stationId: 'station-gangnam',
        lineId: 'seoul-2',
        dayType: StationTimetableDayType.weekday,
        directions: const [
          StationTimetableDirection(
            name: '외선순환',
            departures: [
              StationTimetableDeparture(directionName: '외선순환', seconds: 36000),
            ],
          ),
        ],
      );

      final repo = _FakeTimetableRepo({
        StationTimetableDayType.weekday: timetable,
      });

      await runWithMobileErrorReporter(reportedErrors.add, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: StationTimetableScreen(
              stationId: 'station-gangnam',
              stationName: '강남',
              lines: const [line],
              repository: repo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('station-timetable-network-error-view')),
          findsNothing,
        );

        // Change day to Saturday when server is down
        repo.errorToThrow = const ServerConnectionException(
          '토요일 서버 에러',
          statusCode: 503,
        );
        await tester.tap(find.byKey(const Key('stationTimetableDay-saturday')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('station-timetable-network-error-view')),
          findsOneWidget,
        );
        expect(reportedErrors, isNotEmpty);

        // Change day to Sunday when generic error occurs
        repo.errorToThrow = StateError('generic error');
        await tester.tap(
          find.byKey(const Key('stationTimetableDay-sundayHoliday')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('station-timetable-network-error-view')),
          findsNothing,
        );
        expect(find.text('시간표 정보가 없어요'), findsOneWidget);
      });
    },
  );
}
