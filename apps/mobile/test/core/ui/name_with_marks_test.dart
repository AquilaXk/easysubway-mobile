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
  bool hideMarksOverBudget = false,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: NameWithMarks(
          marksFirst: marksFirst,
          gap: gap,
          hideMarksOverBudget: hideMarksOverBudget,
          name: const SizedBox(key: _nameKey, height: 10),
          marks: Wrap(
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

class _CountingPainter extends CustomPainter {
  int paintCount = 0;

  @override
  void paint(Canvas canvas, Size size) => paintCount += 1;

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => true;
}

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

  testWidgets('감춤을 켠 칸은 마크 하나가 예산보다 넓으면 마크와 간격을 함께 감춘다', (tester) async {
    await tester.pumpWidget(
      _host(width: 200, markWidths: [150, 30], hideMarksOverBudget: true),
    );

    expect(tester.getSize(find.byKey(_marksKey)), Size.zero);
    expect(tester.getSize(find.byKey(_nameKey)).width, 200);
    expect(
      tester.getRect(find.byKey(_nameKey)).left,
      0,
      reason: '감춘 마크 자리에 간격이 남지 않는다',
    );
  });

  testWidgets('같은 자리에서 간격·마크 위치·감춤 설정이 바뀌면 다시 배치한다', (tester) async {
    const marks = [150.0, 30.0];
    await tester.pumpWidget(_host(width: 200, markWidths: marks));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 150 - 8);

    await tester.pumpWidget(
      _host(width: 200, markWidths: marks, hideMarksOverBudget: true),
    );
    expect(tester.getSize(find.byKey(_marksKey)), Size.zero);
    expect(tester.getSize(find.byKey(_nameKey)).width, 200);

    await tester.pumpWidget(_host(width: 200, markWidths: marks, gap: 20));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 150 - 20);

    await tester.pumpWidget(
      _host(width: 200, markWidths: marks, gap: 20, marksFirst: false),
    );
    expect(tester.getRect(find.byKey(_nameKey)).left, 0);
    expect(tester.getRect(find.byKey(_marksKey)).left, 200 - 150);
  });

  testWidgets('감춘 마크 묶음의 건조 레이아웃은 0이고 기준선은 없다', (tester) async {
    await tester.pumpWidget(
      _host(width: 200, markWidths: [150, 30], hideMarksOverBudget: true),
    );

    final budget =
        tester.renderObject<RenderBox>(find.byKey(_marksKey)).parent!
            as RenderBox;
    const unbounded = BoxConstraints(maxWidth: double.infinity);
    expect(budget.getDryLayout(unbounded), Size.zero);
    expect(budget.getDryBaseline(unbounded, TextBaseline.alphabetic), isNull);
  });

  testWidgets('감춤을 켠 칸도 마크가 예산 안이면 그대로 보이고 이름이 나머지를 쓴다', (tester) async {
    await tester.pumpWidget(
      _host(width: 200, markWidths: [60, 30], hideMarksOverBudget: true),
    );

    expect(tester.getSize(find.byKey(_marksKey)), const Size(60, 40));
    expect(tester.getSize(find.byKey(_nameKey)).width, 200 - 60 - 8);
  });

  for (final (markWidth, painted) in [(150.0, false), (60.0, true)]) {
    testWidgets('마크 폭 $markWidth는 ${painted ? '그려진다' : '예산을 넘어 그려지지 않는다'}', (
      tester,
    ) async {
      final painter = _CountingPainter();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: NameWithMarks(
                marksFirst: true,
                hideMarksOverBudget: true,
                name: const SizedBox(height: 10),
                marks: CustomPaint(painter: painter, size: Size(markWidth, 20)),
              ),
            ),
          ),
        ),
      );

      expect(painter.paintCount > 0, painted);
    });
  }

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
