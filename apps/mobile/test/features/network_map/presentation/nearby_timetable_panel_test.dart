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
                  timeLabel: '다음 날 00:01',
                  semanticLabel: '왕십리, 다음 날 00시 01분 출발',
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
    expect(find.text('다음 날 00:01'), findsOneWidget);
    expect(find.text('노출 금지 방면'), findsNothing);
    expect(find.byKey(const Key('testExpressBadge')), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '성수, 10시 01분 출발, 성수, 급행, 10시 02분 출발, '
        '왕십리, 10시 04분 출발, 왕십리, 다음 날 00시 01분 출발',
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
}
