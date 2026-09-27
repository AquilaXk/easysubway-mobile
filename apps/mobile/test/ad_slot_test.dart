import 'package:easysubway_mobile/features/ads/ad_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('광고 슬롯은 표준 안내 배너를 제공한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    const slotKey = Key('adSlotTest');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(width: 400, child: AdBannerSlot(slotKey: slotKey)),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(slotKey)).height, 60);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '안내 배너',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.subway), findsOneWidget);
    expect(find.text('쉬운 지하철과 함께하는 편안한 이동'), findsOneWidget);
    expect(find.text('엘리베이터 및 실시간 도착 정보를 확인하세요'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('쉬운 지하철과 함께하는 편안한 이동'),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    semanticsHandle.dispose();
  });
}
