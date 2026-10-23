import 'package:easysubway_mobile/core/ui/name_with_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _marksKey = Key('marks');
const _nameKey = Key('name');

Widget _host({
  required double width,
  required List<double> markWidths,
  double markHeight = 20,
  double gap = 8,
  bool marksFirst = true,
  double maxMarksFraction = 0.4,
  Widget? marks,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: NameWithMarks(
          marksFirst: marksFirst,
          gap: gap,
          maxMarksFraction: maxMarksFraction,
          name: const SizedBox(key: _nameKey, height: 10),
          marks:
              marks ??
              Wrap(
                key: _marksKey,
                children: [
                  for (final markWidth in markWidths)
                    SizedBox(width: markWidth, height: markHeight),
                ],
              ),
        ),
      ),
    ),
  );
}

const unbounded = BoxConstraints(maxWidth: double.infinity);

RenderBox budgetOf(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byKey(_marksKey)).parent! as RenderBox;

void main() {
  testWidgets('마크 묶음은 줄 폭의 40%까지만 쓰고 줄 폭이 바뀌면 예산도 따라 바뀐다', (tester) async {
    const marks = [30.0, 30.0, 30.0, 30.0];

    await tester.pumpWidget(_host(width: 300, markWidths: marks));
    expect(tester.getSize(find.byKey(_marksKey)), const Size(120, 20));
    expect(tester.getSize(find.byKey(_nameKey)).width, 300 - 120 - 8);

    await tester.pumpWidget(_host(width: 200, markWidths: marks));
    expect(tester.getSize(find.byKey(_marksKey)), const Size(60, 40));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 60 - 8);
  });

  testWidgets('마크 하나가 예산보다 넓으면 눌리지 않고 이름이 나머지 폭을 쓴다', (tester) async {
    await tester.pumpWidget(_host(width: 200, markWidths: [150, 30]));

    expect(tester.getSize(find.byKey(_marksKey)), const Size(150, 40));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 150 - 8);
  });

  testWidgets('같은 자리에서 간격·마크 위치가 바뀌면 다시 배치한다', (tester) async {
    const marks = [150.0, 30.0];
    await tester.pumpWidget(_host(width: 200, markWidths: marks));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 150 - 8);

    await tester.pumpWidget(_host(width: 200, markWidths: marks, gap: 20));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 150 - 20);

    await tester.pumpWidget(
      _host(width: 200, markWidths: marks, gap: 20, marksFirst: false),
    );
    expect(tester.getRect(find.byKey(_nameKey)).left, 0);
    expect(tester.getRect(find.byKey(_marksKey)).left, 200 - 150);
  });

  const textMark = Text('수인분당', key: _marksKey, style: TextStyle(fontSize: 24));
  testWidgets('보이는 글자 마크 묶음의 건조 기준선은 글자의 기준선이다', (tester) async {
    await tester.pumpWidget(
      _host(width: 400, markWidths: const [], marks: textMark),
    );

    final budget = budgetOf(tester);
    final markBaseline = tester
        .renderObject<RenderBox>(find.byKey(_marksKey))
        .getDryBaseline(const BoxConstraints(), TextBaseline.alphabetic);
    expect(markBaseline, isNotNull);
    expect(
      budget.getDryBaseline(unbounded, TextBaseline.alphabetic),
      markBaseline,
    );
  });

  testWidgets('간격만 바뀌어도 다시 배치한다', (tester) async {
    await tester.pumpWidget(_host(width: 200, markWidths: [60]));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 60 - 8);
    expect(tester.getRect(find.byKey(_nameKey)).left, 60 + 8);

    await tester.pumpWidget(_host(width: 200, markWidths: [60], gap: 20));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 60 - 20);
    expect(tester.getRect(find.byKey(_nameKey)).left, 60 + 20);
  });

  // Row는 비유연 자식에게 가로 폭을 무한으로 주므로 줄 폭에서 간격을 빼는 한도는
  // 폭이 정해진 부모가 마크 묶음을 직접 재볼 때 나타난다.
  testWidgets('폭이 정해진 부모가 재면 마크 묶음은 줄 폭에서 간격을 뺀 폭 안에 든다', (tester) async {
    // 예산이 줄 폭 전체여도 간격 8을 남기므로 50dp 마크 둘은 한 줄(100)에 못 놓이고
    // 둘째 줄로 접힌다.
    await tester.pumpWidget(
      _host(width: 200, markWidths: [50, 50], maxMarksFraction: 1),
    );

    expect(
      budgetOf(tester).getDryLayout(const BoxConstraints(maxWidth: 100)),
      const Size(50 + 8, 40),
    );
  });

  testWidgets('줄 폭이 간격보다 좁아도 마크 묶음 폭이 음수가 되지 않는다', (tester) async {
    await tester.pumpWidget(_host(width: 100, markWidths: [30]));

    expect(
      budgetOf(tester).getDryLayout(const BoxConstraints(maxWidth: 6)),
      const Size(6, 20),
    );
  });

  testWidgets('건조 레이아웃과 기준선은 마크 묶음이 실제로 받는 폭을 기준으로 잰다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: NameWithMarks(
              marksFirst: true,
              name: const SizedBox(height: 10),
              marks: Wrap(
                children: const [
                  Text('수인분당', style: TextStyle(fontSize: 24)),
                  Text('경의중앙', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 줄 폭 200의 40%인 예산 80보다 큰 글자(96)가 마크 묶음 폭이라 둘째 마크는 둘째
    // 줄로 접힌다. 큰 글자가 첫 줄이라 기준선은 큰 글자의 것이고, 폭을 풀어 한 줄에
    // 놓으면 작은 글자의 기준선으로 바뀐다.
    final marks = tester.renderObject<RenderBox>(find.byType(Wrap));
    final budget = marks.parent! as RenderBox;
    const unbounded = BoxConstraints(maxWidth: double.infinity);
    const budgeted = BoxConstraints(maxWidth: 96);
    expect(budget.getDryLayout(unbounded), marks.size + const Offset(8, 0));
    final budgetedBaseline = marks.getDryBaseline(
      budgeted,
      TextBaseline.alphabetic,
    );
    expect(
      budget.getDryBaseline(unbounded, TextBaseline.alphabetic),
      budgetedBaseline,
    );
    expect(
      marks.getDryBaseline(unbounded, TextBaseline.alphabetic),
      isNot(budgetedBaseline),
      reason: '폭을 풀면 기준선이 달라져야 위 비교가 예산 적용을 증명한다',
    );
  });
}
