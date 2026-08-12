import 'package:easysubway_mobile/features/network_map/presentation/nearby_arrival_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({
    required NearbyArrivalPanelData data,
    String? leftName = '건대입구',
    String? rightName = '한양대',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NearbyArrivalPanel(
          data: data,
          lineColor: Colors.green,
          leftName: leftName,
          rightName: rightName,
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

    expect(find.text('약 3분'), findsOneWidget);
    expect(find.text('전역 출발'), findsOneWidget);
    expect(find.text('곧 도착'), findsOneWidget);
    expect(find.text('신도림행'), findsNothing);
    expect(
      find.bySemanticsLabel(
        '건대입구 방면 성수행 약 3분, 건대입구 방면 을지로입구행 전역 출발, 한양대 방면 한양대행 곧 도착',
      ),
      findsOneWidget,
    );
  });

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
}
