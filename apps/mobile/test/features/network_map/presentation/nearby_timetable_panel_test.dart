import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_timetable_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({NearbyTimetablePanelData? data}) {
    return MaterialApp(
      home: Scaffold(
        body: NearbyTimetablePanel(
          data: data,
          lineColor: Colors.green,
          leftName: '건대입구',
          rightName: '한양대',
          now: DateTime(2026, 8, 12, 10),
          expressBadgeBuilder: () =>
              const SizedBox(key: Key('testExpressBadge')),
        ),
      ),
    );
  }

  testWidgets('현재 이후 첫 두 방면·각 두 출발과 급행 Semantics를 표시한다', (tester) async {
    await tester.pumpWidget(
      subject(
        data: const NearbyTimetablePanelData(
          directions: [
            NearbyTimetableDirectionData(
              name: '성수',
              departures: [
                NearbyTimetableDepartureData(
                  directionName: '성수',
                  seconds: 35940,
                  timeLabel: '09:59',
                  semanticLabel: '성수, 09시 59분 출발',
                  isExpress: false,
                ),
                NearbyTimetableDepartureData(
                  directionName: '성수',
                  seconds: 36060,
                  timeLabel: '10:01',
                  semanticLabel: '성수, 10시 01분 출발',
                  isExpress: false,
                ),
                NearbyTimetableDepartureData(
                  directionName: '성수',
                  seconds: 36120,
                  timeLabel: '10:02',
                  semanticLabel: '성수, 급행, 10시 02분 출발',
                  isExpress: true,
                ),
                NearbyTimetableDepartureData(
                  directionName: '성수',
                  seconds: 36180,
                  timeLabel: '10:03',
                  semanticLabel: '성수, 10시 03분 출발',
                  isExpress: false,
                ),
              ],
            ),
            NearbyTimetableDirectionData(
              name: ' ',
              departures: [
                NearbyTimetableDepartureData(
                  directionName: '왕십리',
                  seconds: 36240,
                  timeLabel: '10:04',
                  semanticLabel: '왕십리, 10시 04분 출발',
                  isExpress: false,
                ),
                NearbyTimetableDepartureData(
                  directionName: '왕십리',
                  seconds: 86460,
                  timeLabel: '00:01',
                  semanticLabel: '왕십리, 00시 01분 출발',
                  isExpress: false,
                ),
              ],
            ),
            NearbyTimetableDirectionData(
              name: '노출 금지',
              departures: [
                NearbyTimetableDepartureData(
                  directionName: '노출 금지',
                  seconds: 36300,
                  timeLabel: '10:05',
                  semanticLabel: '노출 금지, 10시 05분 출발',
                  isExpress: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text('성수 방면'), findsOneWidget);
    expect(find.text('왕십리 방면'), findsOneWidget);
    expect(find.text('10:01'), findsOneWidget);
    expect(find.text('10:02'), findsOneWidget);
    expect(find.text('10:03'), findsNothing);
    expect(find.text('10:04'), findsOneWidget);
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('다음 날 00:01'), findsNothing);
    expect(find.text('노출 금지 방면'), findsNothing);
    expect(find.byKey(const Key('testExpressBadge')), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '성수, 10시 01분 출발, 성수, 급행, 10시 02분 출발, '
        '왕십리, 10시 04분 출발, 왕십리, 00시 01분 출발',
      ),
      findsOneWidget,
    );
  });

  testWidgets('시간표가 없으면 인접역 기반 대시 skeleton을 유지한다', (tester) async {
    await tester.pumpWidget(subject());

    expect(
      find.byKey(const Key('networkMapNearbyTimetableSkeleton')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('건대입구 방면 정보 없음'), findsOneWidget);
    expect(find.bySemanticsLabel('한양대 방면 정보 없음'), findsOneWidget);
  });

  testWidgets('01:28 심야 시간대에 남은 심야 열차(01:30)만 표시하고 첫차(05:48)를 섞지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTimetablePanel(
            data: const NearbyTimetablePanelData(
              directions: [
                NearbyTimetableDirectionData(
                  name: '오이도',
                  departures: [
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 20880, // 05:48
                      timeLabel: '05:48',
                      semanticLabel: '오이도, 05시 48분 출발',
                      isExpress: false,
                    ),
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 91800, // 01:30 (86400 + 5400)
                      timeLabel: '01:30',
                      semanticLabel: '오이도, 01시 30분 출발',
                      isExpress: false,
                    ),
                  ],
                ),
              ],
            ),
            lineColor: Colors.blue,
            leftName: '반월',
            rightName: '한대앞',
            now: DateTime(2026, 9, 27, 1, 28), // 01:28
            expressBadgeBuilder: () => const SizedBox(),
          ),
        ),
      ),
    );

    // 01:30 열차만 노출되어야 하고, 05:48은 섞여 나오지 않아야 함
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('05:48'), findsNothing);
    expect(find.text('첫차 05:48'), findsNothing);
  });

  testWidgets('01:35 당일 심야 운행 종료 시 새벽 4시 전에는 첫차를 띄우지 않고 "운행 종료"를 표시한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTimetablePanel(
            data: const NearbyTimetablePanelData(
              directions: [
                NearbyTimetableDirectionData(
                  name: '오이도',
                  departures: [
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 20880, // 05:48
                      timeLabel: '05:48',
                      semanticLabel: '오이도, 05시 48분 출발',
                      isExpress: false,
                    ),
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 91800, // 01:30 (이미 지나감)
                      timeLabel: '01:30',
                      semanticLabel: '오이도, 01시 30분 출발',
                      isExpress: false,
                    ),
                  ],
                ),
              ],
            ),
            lineColor: Colors.blue,
            leftName: '반월',
            rightName: '한대앞',
            now: DateTime(2026, 9, 27, 1, 35), // 01:35
            expressBadgeBuilder: () => const SizedBox(),
          ),
        ),
      ),
    );

    // 운행 종료 후이므로 첫차(05:48)를 띄우지 않고 "운행 종료"가 표시되어야 함
    expect(find.text('운행 종료'), findsOneWidget);
    expect(find.text('첫차 05:48'), findsNothing);
    expect(find.text('05:48'), findsNothing);
    expect(find.text('01:30'), findsNothing);
    expect(find.bySemanticsLabel('오이도 방면 운행 종료, 한대앞 방면 정보 없음'), findsOneWidget);
  });

  testWidgets('04:30 첫차 운행 개시 전 시간대에는 첫차(05:48)를 "첫차 05:48"로 명확히 표시한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTimetablePanel(
            data: const NearbyTimetablePanelData(
              directions: [
                NearbyTimetableDirectionData(
                  name: '오이도',
                  departures: [
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 20880, // 05:48
                      timeLabel: '05:48',
                      semanticLabel: '오이도, 05시 48분 출발',
                      isExpress: false,
                    ),
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 21600, // 06:00
                      timeLabel: '06:00',
                      semanticLabel: '오이도, 06시 00분 출발',
                      isExpress: false,
                    ),
                  ],
                ),
              ],
            ),
            lineColor: Colors.blue,
            leftName: '반월',
            rightName: '한대앞',
            now: DateTime(2026, 9, 27, 4, 30), // 04:30
            expressBadgeBuilder: () => const SizedBox(),
          ),
        ),
      ),
    );

    expect(find.text('첫차 05:48'), findsOneWidget);
    expect(find.text('06:00'), findsOneWidget);
    expect(find.text('운행 종료'), findsNothing);
  });

  testWidgets('23:50 당일 모든 열차 종료 시 익일 첫차를 띄우지 않고 "운행 종료"를 표시한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTimetablePanel(
            data: const NearbyTimetablePanelData(
              directions: [
                NearbyTimetableDirectionData(
                  name: '오이도',
                  departures: [
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 20880, // 05:48
                      timeLabel: '05:48',
                      semanticLabel: '오이도, 05시 48분 출발',
                      isExpress: false,
                    ),
                    NearbyTimetableDepartureData(
                      directionName: '오이도',
                      seconds: 84600, // 23:30 (이미 지나감)
                      timeLabel: '23:30',
                      semanticLabel: '오이도, 23시 30분 출발',
                      isExpress: false,
                    ),
                  ],
                ),
              ],
            ),
            lineColor: Colors.blue,
            leftName: '반월',
            rightName: '한대앞',
            now: DateTime(2026, 9, 27, 23, 50), // 23:50
            expressBadgeBuilder: () => const SizedBox(),
          ),
        ),
      ),
    );

    expect(find.text('운행 종료'), findsOneWidget);
    expect(find.text('첫차 05:48'), findsNothing);
    expect(find.text('05:48'), findsNothing);
    expect(find.bySemanticsLabel('오이도 방면 운행 종료, 한대앞 방면 정보 없음'), findsOneWidget);
  });

  testWidgets('시간표 모드에서 Ticker가 돌아 1분이 지나면 이전 열차가 사라지고 다음 열차가 롤오버된다', (
    tester,
  ) async {
    // 10:00:50 시작. 10:01 열차와 10:03 열차가 표시됨
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTimetablePanel(
            data: const NearbyTimetablePanelData(
              directions: [
                NearbyTimetableDirectionData(
                  name: '성수',
                  departures: [
                    NearbyTimetableDepartureData(
                      directionName: '성수',
                      seconds: 36060, // 10:01:00
                      timeLabel: '10:01',
                      semanticLabel: '성수, 10시 01분 출발',
                      isExpress: false,
                    ),
                    NearbyTimetableDepartureData(
                      directionName: '성수',
                      seconds: 36180, // 10:03:00
                      timeLabel: '10:03',
                      semanticLabel: '성수, 10시 03분 출발',
                      isExpress: false,
                    ),
                    NearbyTimetableDepartureData(
                      directionName: '성수',
                      seconds: 36300, // 10:05:00
                      timeLabel: '10:05',
                      semanticLabel: '성수, 10시 05분 출발',
                      isExpress: false,
                    ),
                  ],
                ),
              ],
            ),
            lineColor: Colors.green,
            leftName: '건대입구',
            rightName: '한양대',
            now: DateTime(2026, 8, 12, 10, 0, 50),
            enableTicker: true,
            tickerInterval: const Duration(seconds: 5),
            expressBadgeBuilder: () => const SizedBox(),
          ),
        ),
      ),
    );

    // 최초: 10:01(10초 남음 -> 곧 도착), 10:03(2분 뒤 도착) 노출
    expect(find.text('10:01'), findsOneWidget);
    expect(find.text('곧 도착'), findsOneWidget);
    expect(find.text('10:03'), findsOneWidget);
    expect(find.text('2분 뒤 도착'), findsOneWidget);
    expect(find.text('10:05'), findsNothing);

    // 15초 경과 (10:01:05) -> Ticker 3회 틱 실행
    await tester.pump(const Duration(seconds: 15));

    // 롤오버: 10:01 열차는 지나가서 사라지고, 다음 열차 10:03과 10:05가 노출되며 카운트다운 갱신
    expect(find.text('10:01'), findsNothing);
    expect(find.text('10:03'), findsOneWidget);
    expect(find.text('2분 뒤 도착'), findsOneWidget);
    expect(find.text('10:05'), findsOneWidget);
    expect(find.text('4분 뒤 도착'), findsOneWidget);

    // 위젯 unmount 시 타이머 정상 해제
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets(
    '도착 임박 상태 강조: 행선지 선두 배치, 빨간글씨 곧 도착, 띄어쓰기 1분 뒤 도착, 중앙점 및 정적 시각 금지',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyTimetablePanel(
              data: const NearbyTimetablePanelData(
                directions: [
                  NearbyTimetableDirectionData(
                    name: '오이도 방면',
                    departures: [
                      NearbyTimetableDepartureData(
                        directionName: '오이도 방면',
                        destination: '오이도',
                        seconds: 36030, // 30초 남음 -> 곧 도착
                        timeLabel: '10:00',
                        semanticLabel: '오이도, 10시 00분 출발',
                        isExpress: false,
                      ),
                      NearbyTimetableDepartureData(
                        directionName: '오이도 방면',
                        destination: '오이도',
                        seconds: 36080, // 80초 남음 -> 1분 뒤 도착
                        timeLabel: '10:01',
                        semanticLabel: '오이도, 10시 01분 출발',
                        isExpress: false,
                      ),
                    ],
                  ),
                ],
              ),
              lineColor: Colors.blue,
              leftName: '반월',
              rightName: '한대앞',
              now: DateTime(2026, 8, 12, 10, 0, 0),
              expressBadgeBuilder: () => const SizedBox(),
            ),
          ),
        ),
      );

      // 행선지 '오이도행'이 선두에 배치됨
      expect(find.text('오이도행'), findsNWidgets(2));

      // 60초 미만은 빨간색 볼드 statusDanger '곧 도착'
      expect(find.text('곧 도착'), findsOneWidget);
      final soonText = tester.widget<Text>(find.text('곧 도착'));
      expect(soonText.style?.color, EasySubwayColorPrimitives.statusDanger);
      expect(soonText.style?.fontWeight, FontWeight.w700);

      // 1분은 띄어쓰기를 철저히 준수한 '1분 뒤 도착' (1~3분 뒤 도착은 amber 볼드 탑승 임박 강조)
      expect(find.text('1분 뒤 도착'), findsOneWidget);
      final oneMinText = tester.widget<Text>(find.text('1분 뒤 도착'));
      expect(oneMinText.style?.color, EasySubwayAccessibleColors.amber);
      expect(oneMinText.style?.fontWeight, FontWeight.w700);

      // 중앙점(·, .)이나 불필요한 정적 시각(10:00, 10:01) 절대 노출 금지
      expect(find.textContaining('·'), findsNothing);
      expect(find.text('10:00'), findsNothing);
      expect(find.text('10:01'), findsNothing);
    },
  );
}
