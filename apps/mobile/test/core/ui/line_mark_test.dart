import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double scale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: widget!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  const color = Color(0xFF00A84D);

  testWidgets('호선 번호는 노선색 원 안에 흰 글자로 그려진다', (tester) async {
    await _pump(tester, const LineMark(label: '2', color: color));

    expect(tester.getSize(find.byType(LineMark)), const Size(20, 20));
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, color);
    expect(tester.widget<Text>(find.text('2')).style?.color, Colors.white);
  });

  testWidgets('공식 약칭은 Wrap 안에서도 글자 폭만큼만 차지하는 알약이다', (tester) async {
    await _pump(
      tester,
      const SizedBox(
        width: 300,
        child: Wrap(
          children: [LineMark(label: '경의중앙', color: color)],
        ),
      ),
    );

    final size = tester.getSize(find.byType(LineMark));
    expect(size.height, 20);
    expect(size.width, lessThan(100));
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration;
    expect(decoration.shape, BoxShape.rectangle);
    expect(tester.widget<Text>(find.text('경의중앙')).style?.color, Colors.white);
  });

  RenderParagraph paragraphOf(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.text(label));

  for (final scale in [1.0, 1.5, 2.0]) {
    for (final label in ['2', '경의중앙']) {
      testWidgets('글자 $scale배에서 $label 글자는 한 줄로 마크 안에 들어간다', (tester) async {
        await _pump(
          tester,
          LineMark(label: label, color: color),
          scale: scale,
        );

        final mark = tester.getSize(find.byType(LineMark));
        final paragraph = paragraphOf(tester, label);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textSize.height, lessThanOrEqualTo(mark.height));
        expect(paragraph.textSize.width, lessThanOrEqualTo(mark.width));
        expect(mark.height, greaterThanOrEqualTo(20 * scale));
      });
    }
  }

  testWidgets('호선 번호 글자는 원 높이의 절반 이상이라 한눈에 읽힌다', (tester) async {
    await _pump(tester, const LineMark(label: '2', color: color));

    final mark = tester.getSize(find.byType(LineMark));
    final glyph = paragraphOf(tester, '2').textSize.height;
    expect(glyph, greaterThanOrEqualTo(mark.height * 0.5));
    expect(glyph, lessThanOrEqualTo(mark.height));
  });

  for (final size in [14.0, 20.0, 28.0]) {
    testWidgets('마크 크기 $size에서도 알약 글자는 10.5 아래로 줄지 않는다', (tester) async {
      await _pump(tester, LineMark(label: '경의중앙', color: color, size: size));

      final glyph = paragraphOf(tester, '경의중앙').textSize.height;
      expect(glyph, greaterThanOrEqualTo(10.5));
      expect(glyph, lessThanOrEqualTo(size));
    });
  }
}
