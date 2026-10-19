import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_tap_target_guideline.dart';

/// [FullTapTargetGuideline]이 Flutter 기본 탭 영역 가이드라인이 건너뛰는 스크롤 목록
/// 안의 요소까지 검사하되, 일부만 보이는 요소는 오탐을 막기 위해 건너뛰는지 확인한다.
const _guideline = FullTapTargetGuideline(Size(48, 48));
const _viewport = Size(360, 600);

Widget _button(double size, {String label = '버튼'}) => Semantics(
  button: true,
  label: label,
  onTap: () {},
  child: SizedBox(width: size, height: size),
);

Widget _list(List<Widget> children, {ScrollController? controller}) =>
    ListView(controller: controller, children: children);

Future<Evaluation> _evaluate(WidgetTester tester, Widget body) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _viewport;
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  await tester.pump();
  final evaluation = _guideline.evaluate(tester);
  semantics.dispose();
  return evaluation;
}

void main() {
  testWidgets('Flutter 기본 가이드라인은 같은 30dp 버튼을 놓친다', (tester) async {
    // 새 가이드라인이 필요한 이유다. 기본 가이드라인이 이 요소를 잡으면 이 테스트가 실패해
    // 새 가이드라인의 존재 이유를 다시 확인하게 한다.
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _list([
            const SizedBox(height: 100),
            Center(child: _button(30)),
          ]),
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('스크롤 목록 안의 30dp 버튼은 위반이다', (tester) async {
    final evaluation = await _evaluate(
      tester,
      _list([const SizedBox(height: 100), Center(child: _button(30))]),
    );
    expect(evaluation.passed, isFalse);
    expect(evaluation.reason, contains('버튼'));
  });

  testWidgets('스크롤 목록 안의 48dp 버튼은 통과한다', (tester) async {
    final evaluation = await _evaluate(
      tester,
      _list([const SizedBox(height: 100), Center(child: _button(48))]),
    );
    expect(evaluation.passed, isTrue, reason: evaluation.reason);
  });

  testWidgets('뷰포트에 일부만 보이는 버튼은 건너뛴다', (tester) async {
    final controller = ScrollController(initialScrollOffset: 520);
    addTearDown(controller.dispose);
    // 작은 버튼이 목록 위쪽 경계에 걸쳐 일부만 보인다.
    final evaluation = await _evaluate(
      tester,
      _list([
        const SizedBox(height: 500),
        Center(child: _button(40)),
        const SizedBox(height: 1000),
      ], controller: controller),
    );
    expect(evaluation.passed, isTrue, reason: evaluation.reason);
  });

  testWidgets('스크롤 밖의 작은 버튼도 위반이다', (tester) async {
    final evaluation = await _evaluate(tester, Center(child: _button(30)));
    expect(evaluation.passed, isFalse);
  });

  testWidgets('화면 밖으로 밀려난 버튼은 건너뛴다', (tester) async {
    final evaluation = await _evaluate(
      tester,
      _list([const SizedBox(height: 2000), _button(30)]),
    );
    expect(evaluation.passed, isTrue, reason: evaluation.reason);
  });
}
