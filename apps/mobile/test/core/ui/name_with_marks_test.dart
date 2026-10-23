import 'package:easysubway_mobile/core/ui/name_with_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _marksKey = Key('marks');
const _nameKey = Key('name');

Widget _host({
  required double width,
  required List<double> markWidths,
  double markHeight = 20,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: NameWithMarks(
          marksFirst: true,
          gap: 8,
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
                children: [
                  for (final label in ['수인분당', '경의중앙'])
                    Text(label, style: const TextStyle(fontSize: 24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 줄 폭 200의 40%인 예산 80보다 글자 한 개(96)가 넓어 96이 마크 묶음 폭이다.
    final marks = tester.renderObject<RenderBox>(find.byType(Wrap));
    final budget = marks.parent! as RenderBox;
    const unbounded = BoxConstraints(maxWidth: double.infinity);
    expect(budget.getDryLayout(unbounded), marks.size);
    expect(
      budget.getDryBaseline(unbounded, TextBaseline.alphabetic),
      marks.getDryBaseline(
        const BoxConstraints(maxWidth: 96),
        TextBaseline.alphabetic,
      ),
    );
  });
}
