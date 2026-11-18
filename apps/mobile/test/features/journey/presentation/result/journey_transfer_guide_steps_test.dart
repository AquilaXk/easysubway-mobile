import 'dart:ui' show Tristate;

import 'package:easysubway_mobile/features/journey/presentation/result/journey_result_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _steps = <String>[
  '1) 사평 방면 승강장',
  '2) 엘리베이터 이용',
  '3) 지하 2층으로 이동',
  '4) 7호선 환승통로 이동',
  '5) 3호선 잠원 방면 엘리베이터 이용',
  '6) 지하 3층으로 이동',
  '7) 3호선 잠원 방면 승강장',
];

Future<void> _pump(
  WidgetTester tester, {
  required List<String> steps,
  required bool expanded,
  VoidCallback? onToggle,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: JourneyTransferGuideSteps(
        legIndex: 2,
        steps: steps,
        expanded: expanded,
        onToggle: onToggle ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('접힌 상태는 토글만 보이고 단계 문장은 없다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, steps: _steps, expanded: false);

    final toggle = find.byKey(const Key('journey-transfer-guide-toggle-2'));
    expect(toggle, findsOneWidget);
    expect(find.text('이동 방법 7단계'), findsOneWidget);
    for (final step in _steps) {
      expect(find.text(step), findsNothing);
    }
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    final node = tester.getSemantics(toggle);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isExpanded, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('펼치면 단계 문장을 원문 그대로 순서대로 보여 준다', (tester) async {
    await _pump(tester, steps: _steps, expanded: true);

    for (final step in _steps) {
      expect(find.text(step), findsOneWidget);
    }
    final tops = [
      for (final step in _steps) tester.getTopLeft(find.text(step)).dy,
    ];
    expect(tops, [...tops]..sort());
  });

  testWidgets('토글을 누르면 onToggle을 부른다', (tester) async {
    var taps = 0;
    await _pump(tester, steps: _steps, expanded: false, onToggle: () => taps++);

    await tester.tap(find.byKey(const Key('journey-transfer-guide-toggle-2')));

    expect(taps, 1);
  });

  testWidgets('단계가 없으면 아무것도 그리지 않는다', (tester) async {
    await _pump(tester, steps: const [], expanded: false);

    expect(find.byType(InkWell), findsNothing);
    expect(find.textContaining('이동 방법'), findsNothing);
    expect(tester.getSize(find.byType(JourneyTransferGuideSteps)), Size.zero);
  });

  testWidgets('스크린리더는 토글 다음에 단계를 순서대로 읽고 펼침 상태를 알린다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, steps: _steps, expanded: true);

    final labels = [
      for (final node in tester.semantics.simulatedAccessibilityTraversal())
        if (node.label.isNotEmpty) node.label,
    ];

    expect(labels, ['이동 방법 7단계', ..._steps]);
    final toggle = tester.getSemantics(
      find.byKey(const Key('journey-transfer-guide-toggle-2')),
    );
    expect(toggle.flagsCollection.isExpanded, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('원문은 다듬지 않고 그대로 낸다(앞뒤 공백·번호·금지어 포함)', (tester) async {
    // 원문은 데이터이지 앱 문구가 아니다. 문구 검사 대상은 코드의 리터럴뿐이다.
    const raw = <String>['1) 서버실 방면 승강장 검증 구간', '  2) 엘리베이터  이용'];
    await _pump(tester, steps: raw, expanded: true);

    expect(find.text(raw[0]), findsOneWidget);
    expect(find.text(raw[1]), findsOneWidget);
  });
}
