import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_tap_target_guideline.dart';

/// [FullTapTargetGuideline]이 Flutter 기본 탭 영역 가이드라인이 건너뛰는 스크롤 목록
/// 안의 요소까지 검사하되, 스크롤로 잘렸을 수 있는 요소는 오탐을 막기 위해 건너뛰는지
/// 확인한다. 경계마다 "잘리면 건너뜀"과 "같은 위치에서 완전히 보이면 위반"을 짝으로 둬
/// 각 변의 판정이 따로 검증되게 한다.
const _guideline = FullTapTargetGuideline(androidMinTapTarget);
const _viewport = Size(360, 600);
const _scrollMax = 100000.0;

Widget _button(String label, double width, double height) => Semantics(
  button: true,
  label: label,
  onTap: () {},
  child: SizedBox(width: width, height: height),
);

/// 세로 스크롤 안의 한 줄. 버튼은 왼쪽에 두어 가로로 꽉 차지 않는다. 목록(`ListView`)은
/// 시맨틱스 노드가 항목 칸 전체로 커지므로 버튼 크기를 그대로 검사하려고
/// `SingleChildScrollView`를 쓴다.
Widget _row(String label, double width, double height) =>
    _button(label, width, height);

Widget _gap(double height) => SizedBox(height: height);

Widget _vertical(ScrollController controller, List<Widget> children) =>
    SingleChildScrollView(
      controller: controller,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );

/// 가로 스크롤 안의 칩 줄. 역 시간표 시각 칩 줄과 같은 모양이다. 세로 경계에 닿지 않도록
/// 칩을 줄 높이의 가운데에 둔다.
Widget _horizontal(ScrollController controller, List<Widget> children) => Align(
  alignment: Alignment.topCenter,
  child: SizedBox(
    height: 100,
    child: SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    ),
  ),
);

class _Case {
  const _Case(
    this.name,
    this.build, {
    this.offset = 0,
    this.violating = const {},
    this.present = const {},
  });

  final String name;
  final Widget Function(ScrollController controller) build;

  /// 만든 뒤 스크롤러를 옮길 위치. [_scrollMax]면 끝까지 옮긴다.
  final double offset;

  /// 위반으로 보고돼야 하는 라벨.
  final Set<String> violating;

  /// 시맨틱스 트리에 있어야 하는 라벨. 건너뛰는 케이스가 노드 부재로 통과하지 않게 한다.
  final Set<String> present;
}

final _cases = <_Case>[
  // 세로 스크롤.
  _Case(
    '스크롤 시작에 붙은 첫 항목의 30dp 버튼은 위반이다',
    (c) => _vertical(c, [_row('첫', 100, 30), _gap(2000)]),
    violating: {'첫'},
  ),
  _Case(
    '스크롤 중간의 30dp 버튼은 위반이다',
    (c) => _vertical(c, [_gap(100), _row('중간', 100, 30), _gap(2000)]),
    violating: {'중간'},
  ),
  _Case(
    '스크롤 중간의 48dp 버튼은 통과한다',
    (c) => _vertical(c, [_gap(100), _row('중간', 100, 48), _gap(2000)]),
    present: {'중간'},
  ),
  _Case(
    '위쪽에서 잘린 버튼은 건너뛴다',
    (c) => _vertical(c, [_gap(500), _row('잘림', 100, 40), _gap(2000)]),
    offset: 520,
    present: {'잘림'},
  ),
  _Case(
    '같은 위치라도 위쪽에서 완전히 보이는 버튼은 위반이다',
    (c) => _vertical(c, [_gap(500), _row('보임', 100, 40), _gap(2000)]),
    offset: 480,
    violating: {'보임'},
  ),
  _Case(
    '아래쪽에서 잘린 버튼은 건너뛴다',
    (c) => _vertical(c, [_gap(580), _row('잘림', 100, 40), _gap(2000)]),
    present: {'잘림'},
  ),
  _Case(
    '같은 위치라도 아래쪽에서 완전히 보이는 버튼은 위반이다',
    (c) => _vertical(c, [_gap(500), _row('보임', 100, 40), _gap(2000)]),
    violating: {'보임'},
  ),
  _Case(
    '스크롤 끝에 붙은 마지막 항목의 30dp 버튼은 위반이다',
    (c) => _vertical(c, [_gap(2000), _row('끝', 100, 30)]),
    offset: _scrollMax,
    violating: {'끝'},
  ),
  _Case(
    '폭만 작은 버튼(폭 30, 높이 60)은 위반이다',
    (c) => _vertical(c, [_gap(100), _row('좁음', 30, 60), _gap(2000)]),
    violating: {'좁음'},
  ),
  _Case(
    '화면 밖이지만 시맨틱스 노드가 있는 버튼은 건너뛴다',
    (c) => _vertical(c, [_gap(2000), _row('밖', 100, 30)]),
    present: {'밖'},
  ),
  // 가로 스크롤(역 시간표 시각 칩 줄과 같은 모양).
  _Case(
    '가로 스크롤 시작에 붙은 첫 칩의 36dp 높이는 위반이다',
    (c) =>
        _horizontal(c, [for (var i = 0; i < 12; i++) _button('칩$i', 66, 36)]),
    violating: {for (var i = 0; i < 5; i++) '칩$i'},
    present: {'칩0'},
  ),
  _Case(
    '가로 스크롤의 48dp 높이 칩은 통과한다',
    (c) =>
        _horizontal(c, [for (var i = 0; i < 12; i++) _button('칩$i', 66, 48)]),
    present: {'칩0'},
  ),
  _Case(
    '오른쪽에서 잘린 칩은 건너뛴다',
    (c) =>
        _horizontal(c, [for (var i = 0; i < 12; i++) _button('칩$i', 66, 36)]),
    violating: {for (var i = 0; i < 5; i++) '칩$i'},
    present: {'칩5'},
  ),
  _Case(
    '왼쪽에서 잘린 칩은 건너뛴다',
    (c) =>
        _horizontal(c, [for (var i = 0; i < 12; i++) _button('칩$i', 66, 36)]),
    offset: 100,
    violating: {for (var i = 2; i < 6; i++) '칩$i'},
    present: {'칩1'},
  ),
  _Case(
    '가로 스크롤 끝에 붙은 마지막 칩의 36dp 높이는 위반이다',
    (c) =>
        _horizontal(c, [for (var i = 0; i < 12; i++) _button('칩$i', 66, 36)]),
    offset: _scrollMax,
    violating: {for (var i = 7; i < 12; i++) '칩$i'},
    present: {'칩6'},
  ),
  // 스크롤 밖: 화면 네 변은 Flutter 기본 가이드라인처럼 닿으면 건너뛴다.
  for (final (name, alignment) in [
    ('위', Alignment.topCenter),
    ('아래', Alignment.bottomCenter),
    ('왼쪽', Alignment.centerLeft),
    ('오른쪽', Alignment.centerRight),
  ])
    _Case(
      '스크롤 밖에서 화면 $name 변에 닿은 30dp 버튼은 건너뛴다',
      (_) => Align(alignment: alignment, child: _button('변', 30, 30)),
      present: {'변'},
    ),
  _Case(
    '숨김 노드는 건너뛴다',
    (_) => Center(
      child: Semantics(
        hidden: true,
        button: true,
        label: '숨김',
        onTap: () {},
        child: const SizedBox(width: 30, height: 30),
      ),
    ),
    present: {'숨김'},
  ),
  _Case(
    '부모에 병합된 노드는 따로 세지 않고 병합된 노드만 검사한다',
    (_) => Center(
      child: MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [_button('안', 30, 30), const Text('글')],
        ),
      ),
    ),
    violating: {r'안\n글'},
  ),
  _Case(
    '스크롤 밖 화면 가운데의 30dp 버튼은 위반이다',
    (_) => Center(child: _button('가운데', 30, 30)),
    violating: {'가운데'},
  ),
];

Future<Set<String>> _labels(WidgetTester tester) async {
  final labels = <String>{};
  void visit(SemanticsNode node) {
    labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(MaterialApp)));
  return labels;
}

Set<String> _violatingLabels(Evaluation evaluation) => {
  for (final match in RegExp(
    r'label: "([^"]*)"',
  ).allMatches(evaluation.reason ?? ''))
    match[1]!,
};

Future<void> _pump(
  WidgetTester tester,
  Widget Function(ScrollController) build, {
  double offset = 0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _viewport;
  addTearDown(tester.view.reset);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: build(controller))));
  if (offset > 0) {
    controller.jumpTo(offset.clamp(0, controller.position.maxScrollExtent));
    await tester.pump();
  }
}

void main() {
  for (final testCase in _cases) {
    testWidgets(testCase.name, (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, testCase.build, offset: testCase.offset);
      final evaluation = _guideline.evaluate(tester);
      expect(await _labels(tester), containsAll(testCase.present));
      expect(_violatingLabels(evaluation), testCase.violating);
      expect(evaluation.passed, testCase.violating.isEmpty);
      semantics.dispose();
    });
  }

  group('Flutter 기본 가이드라인과의 차이', () {
    Widget fullWidthRow(ScrollController c) =>
        _vertical(c, [_gap(100), _button('꽉참', 360, 30), _gap(2000)]);

    testWidgets('기본 가이드라인은 가로로 꽉 찬 행의 30dp 버튼을 놓친다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, fullWidthRow);
      expect((await androidTapTargetGuideline.evaluate(tester)).passed, isTrue);
      expect(_violatingLabels(_guideline.evaluate(tester)), {'꽉참'});
      semantics.dispose();
    });

    testWidgets('기본 가이드라인도 좌우에 여백이 있는 행의 30dp 버튼은 잡는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        (c) => ListView(
          controller: c,
          padding: const EdgeInsets.all(20),
          children: [_gap(100), _button('여백', 100, 30), _gap(2000)],
        ),
      );
      expect(
        (await androidTapTargetGuideline.evaluate(tester)).passed,
        isFalse,
      );
      semantics.dispose();
    });
  });
}
