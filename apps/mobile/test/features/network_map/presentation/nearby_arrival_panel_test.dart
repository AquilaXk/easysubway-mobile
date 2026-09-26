import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_arrival_panel.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_columns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({
    required NearbyArrivalPanelData data,
    String? leftName = '건대입구',
    String? rightName = '한양대',
    VoidCallback? onSelectTimetable,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NearbyArrivalPanel(
          data: data,
          lineColor: Colors.green,
          leftName: leftName,
          rightName: rightName,
          onSelectTimetable: onSelectTimetable,
        ),
      ),
    );
  }

  testWidgets('fresh 도착 정보를 방면별 두 건으로 투영한다', (tester) async {
    await tester.pumpWidget(
      subject(
        data: const NearbyArrivalPanelData(
          status: NearbyArrivalPanelStatus.fresh,
          arrivals: [
            NearbyArrivalData(
              direction: '건대입구 방면',
              destination: '성수',
              etaSeconds: 150,
              message: '',
            ),
            NearbyArrivalData(
              direction: '건대입구 방면',
              destination: '을지로입구',
              etaSeconds: null,
              message: '전역 출발',
            ),
            NearbyArrivalData(
              direction: '건대입구 방면',
              destination: '신도림',
              etaSeconds: 600,
              message: '',
            ),
            NearbyArrivalData(
              direction: '',
              destination: '한양대',
              etaSeconds: 1,
              message: '',
            ),
          ],
        ),
      ),
    );

    expect(find.text('3분뒤 도착'), findsOneWidget);
    expect(find.text('전역 출발'), findsOneWidget);
    expect(find.text('곧 도착'), findsOneWidget);
    expect(find.text('신도림행'), findsNothing);
    expect(
      find.bySemanticsLabel(
        '건대입구 방면 성수행 3분뒤 도착, 건대입구 방면 을지로입구행 전역 출발, 한양대 방면 한양대행 곧 도착',
      ),
      findsOneWidget,
    );
  });

  testWidgets('도착 시간 표기 규칙 및 곧 도착 빨간색 강조 검증', (tester) async {
    final fixedNow = DateTime(2026, 9, 26, 20, 0); // 20:00
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyArrivalPanel(
            data: const NearbyArrivalPanelData(
              status: NearbyArrivalPanelStatus.fresh,
              arrivals: [
                NearbyArrivalData(
                  direction: '당고개 방면',
                  destination: '당고개',
                  etaSeconds: 45, // 1분 미만 -> 곧 도착
                  message: '',
                ),
                NearbyArrivalData(
                  direction: '당고개 방면',
                  destination: '노원',
                  etaSeconds: 300, // 5분뒤 도착
                  message: '',
                ),
                NearbyArrivalData(
                  direction: '오이도 방면',
                  destination: '오이도',
                  etaSeconds: 600, // 10분뒤 도착
                  message: '',
                ),
                NearbyArrivalData(
                  direction: '오이도 방면',
                  destination: '안산',
                  etaSeconds: 1140, // 19분 -> 10분 초과: 20:19
                  message: '',
                ),
              ],
            ),
            lineColor: Colors.blue,
            leftName: '반월',
            rightName: '한대앞',
            now: fixedNow,
          ),
        ),
      ),
    );

    expect(find.text('곧 도착'), findsOneWidget);
    expect(find.text('5분뒤 도착'), findsOneWidget);
    expect(find.text('10분뒤 도착'), findsOneWidget);
    expect(find.text('20:19'), findsOneWidget);

    // 곧 도착 텍스트 위젯은 빨간색 강조 (statusDestructive w700)
    final soonText = tester.widget<Text>(find.text('곧 도착'));
    expect(soonText.style?.color, EasySubwayAccessibleColors.statusDestructive);
    expect(soonText.style?.fontWeight, FontWeight.w700);

    // 일반 도착 텍스트 위젯은 secondaryText w600
    final regularText = tester.widget<Text>(find.text('5분뒤 도착'));
    expect(regularText.style?.color, EasySubwayAccessibleColors.secondaryText);
    expect(regularText.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('eta가 0이어도 상세 위치 메시지가 있으면 메시지를 우선 표시한다 (코레일 구간 방어)', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        data: const NearbyArrivalPanelData(
          status: NearbyArrivalPanelStatus.fresh,
          arrivals: [
            NearbyArrivalData(
              direction: '건대입구 방면',
              destination: '당고개',
              etaSeconds: 0,
              message: '[3]번째 전역',
            ),
            NearbyArrivalData(
              direction: '한양대 방면',
              destination: '오이도',
              etaSeconds: 0,
              message: '',
            ),
          ],
        ),
      ),
    );

    expect(find.text('[3]번째 전역'), findsOneWidget);
    expect(find.text('곧 도착'), findsOneWidget);
  });

  testWidgets(
    'message가 "곧 도착"이고 positionMessage가 있으면 positionMessage를 우선 표시한다',
    (tester) async {
      await tester.pumpWidget(
        subject(
          data: const NearbyArrivalPanelData(
            status: NearbyArrivalPanelStatus.fresh,
            arrivals: [
              NearbyArrivalData(
                direction: '건대입구 방면',
                destination: '오이도',
                etaSeconds: null,
                message: '곧 도착',
                positionMessage: '신길온천',
              ),
              NearbyArrivalData(
                direction: '한양대 방면',
                destination: '당고개',
                etaSeconds: 0,
                message: '곧 도착',
                positionMessage: '고잔',
              ),
            ],
          ),
        ),
      );

      expect(find.text('신길온천'), findsOneWidget);
      expect(find.text('고잔'), findsOneWidget);
    },
  );

  testWidgets('stale 정보의 수신 시각을 표시한다', (tester) async {
    await tester.pumpWidget(
      subject(
        data: const NearbyArrivalPanelData(
          status: NearbyArrivalPanelStatus.stale,
          receivedAt: '오전 10:30',
          arrivals: [
            NearbyArrivalData(
              direction: '건대입구 방면',
              destination: '성수',
              etaSeconds: 180,
              message: '',
            ),
          ],
        ),
      ),
    );

    expect(find.text('최근 도착 정보 · 오전 10:30'), findsOneWidget);
  });

  testWidgets('unavailable은 arrivals를 노출하지 않고 인접역 skeleton을 유지한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        data: const NearbyArrivalPanelData(
          status: NearbyArrivalPanelStatus.unavailable,
          arrivals: [
            NearbyArrivalData(
              direction: '건대입구 방면',
              destination: '노출 금지',
              etaSeconds: 60,
              message: '',
            ),
          ],
        ),
      ),
    );

    expect(
      find.byKey(const Key('networkMapNearbyArrivalSkeleton')),
      findsOneWidget,
    );
    expect(find.text('노출 금지행'), findsNothing);
    expect(find.bySemanticsLabel('건대입구 방면 정보 없음'), findsOneWidget);
    expect(find.bySemanticsLabel('한양대 방면 정보 없음'), findsOneWidget);
  });

  testWidgets('unavailable은 AI 슬롭 문구 없이 방면 대시 스켈레톤을 노출한다', (tester) async {
    await tester.pumpWidget(
      subject(
        data: const NearbyArrivalPanelData(
          status: NearbyArrivalPanelStatus.unavailable,
        ),
      ),
    );

    expect(find.text('실시간 도착 정보를 불러올 수 없습니다.'), findsNothing);
    expect(find.text('시간표 보기'), findsNothing);
    expect(
      find.byKey(const Key('networkMapNearbyArrivalSkeleton')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('건대입구 방면 정보 없음'), findsOneWidget);
    expect(find.bySemanticsLabel('한양대 방면 정보 없음'), findsOneWidget);
  });

  testWidgets(
    'unavailable에 방면 슬롯이 없을 때도 에러 문구 없이 NearbyDataUnavailable을 노출한다',
    (tester) async {
      await tester.pumpWidget(
        subject(
          data: const NearbyArrivalPanelData(
            status: NearbyArrivalPanelStatus.unavailable,
          ),
          leftName: null,
          rightName: null,
        ),
      );

      expect(find.text('실시간 도착 정보를 불러올 수 없습니다.'), findsNothing);
      expect(find.text('시간표 보기'), findsNothing);
      expect(find.byType(NearbyDataUnavailable), findsOneWidget);
    },
  );
}
