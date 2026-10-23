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

  // 아래 두 표의 기대값은 실제 레이아웃에서 잰 값을 그대로 적었다. 상한 상수로
  // 계산하면 상한을 없애거나 글자만 배율을 놓쳐도 기대값이 같이 따라가 통과한다.
  // 기본 마크는 상한이 없어 한 변이 20 * 배율이고, 글자는 원 20 * 0.6 = 12와 알약
  // 20 * 0.58 = 11.6에 같은 배율을 곱한 값이다. 알약 폭은 4글자 알약의 글자 폭에
  // 좌우 여백(높이의 0.33배씩)을 더한 값이다.
  for (final (scale, label, side, width, fontSize) in [
    (1.0, '2', 20.0, 20.0, 12.0),
    (1.3, '2', 26.0, 26.0, 15.6),
    (1.5, '2', 30.0, 30.0, 18.0),
    (2.0, '2', 40.0, 40.0, 24.0),
    (1.0, '경의중앙', 20.0, 60.6, 11.6),
    (1.0, '수인분당', 20.0, 60.6, 11.6),
    (1.3, '경의중앙', 26.0, 78.48, 15.08),
    (1.5, '경의중앙', 30.0, 90.4, 17.4),
    (2.0, '경의중앙', 40.0, 120.2, 23.2),
    (2.0, '수인분당', 40.0, 120.2, 23.2),
  ]) {
    testWidgets(
      '상한 없는 마크는 글자 $scale배에서 $label 한 변 $side, 폭 $width, 글자 $fontSize다',
      (tester) async {
        await _pump(
          tester,
          LineMark(label: label, color: color),
          scale: scale,
        );

        final mark = tester.getSize(find.byType(LineMark));
        final paragraph = paragraphOf(tester, label);
        expect(mark.height, side);
        expect(mark.width, closeTo(width, 0.05));
        expect(paragraph.text.style!.fontSize, closeTo(fontSize, 0.001));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textSize.height, lessThanOrEqualTo(mark.height));
        expect(paragraph.textSize.width, lessThanOrEqualTo(mark.width));
      },
    );
  }

  // 높이가 정해진 칸의 마크는 1.3배에서 멈춘다. 1.3배 이상에서는 한 변 26, 글자
  // 15.6(원)과 15.08(알약)로 같다.
  for (final (scale, label, side, width, fontSize) in [
    (1.0, '2', 20.0, 20.0, 12.0),
    (1.3, '2', 26.0, 26.0, 15.6),
    (1.5, '2', 26.0, 26.0, 15.6),
    (2.0, '2', 26.0, 26.0, 15.6),
    (1.0, '경의중앙', 20.0, 60.6, 11.6),
    (1.3, '경의중앙', 26.0, 78.48, 15.08),
    (1.5, '경의중앙', 26.0, 78.48, 15.08),
    (2.0, '경의중앙', 26.0, 78.48, 15.08),
    (2.0, '수인분당', 26.0, 78.48, 15.08),
  ]) {
    testWidgets(
      '고정 칸 마크는 글자 $scale배에서 $label 한 변 $side, 폭 $width, 글자 $fontSize다',
      (tester) async {
        await _pump(
          tester,
          LineMark(
            label: label,
            color: color,
            maxTextScale: lineMarkFixedChromeMaxTextScale,
          ),
          scale: scale,
        );

        final mark = tester.getSize(find.byType(LineMark));
        final paragraph = paragraphOf(tester, label);
        expect(mark.height, side);
        expect(mark.width, closeTo(width, 0.05));
        expect(paragraph.text.style!.fontSize, closeTo(fontSize, 0.001));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textSize.height, lessThanOrEqualTo(mark.height));
        expect(paragraph.textSize.width, lessThanOrEqualTo(mark.width));
      },
    );
  }

  // 상용 서비스 역 검색 화면 3x 캡처 실측: 높이 18pt 알약의 폭은 수인분당 53.7pt,
  // 신분당 43.3pt다.
  for (final (label, width) in [('수인분당', 53.7), ('신분당', 43.3)]) {
    testWidgets('높이 18 알약 $label은 실측 폭 $width에 맞게 조밀하다', (tester) async {
      await _pump(tester, LineMark(label: label, color: color, size: 18));

      final mark = tester.getSize(find.byType(LineMark));
      expect(mark.height, 18);
      expect(mark.width, closeTo(width, 1.5));
    });
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

  group('노선색 막대 위 마크와 흰 바탕 노선 글자색(#509)', () {
    double contrastOnWhite(Color color) =>
        (1.05) / (color.computeLuminance() + 0.05);

    test('흰 바탕과 4.5:1을 넘는 노선색은 그대로 쓴다', () {
      const lineOne = Color(0xFF0052A4);
      expect(contrastOnWhite(lineOne), greaterThan(4.5));
      expect(lineInkOnWhite(lineOne), lineOne);
    });

    for (final (name, color) in const [
      ('수인분당', Color(0xFFF5A200)),
      ('4호선', Color(0xFF00A5DE)),
      ('9호선', Color(0xFFBDB092)),
    ]) {
      test('$name 노선색은 같은 색상에서 명도만 낮춰 4.5:1을 넘긴다', () {
        expect(contrastOnWhite(color), lessThan(4.5));
        final ink = lineInkOnWhite(color);
        expect(contrastOnWhite(ink), greaterThanOrEqualTo(4.5));
        expect(
          HSLColor.fromColor(ink).hue,
          closeTo(HSLColor.fromColor(color).hue, 1.0),
        );
        // 필요한 만큼만 어둡게 한다. 한 단계 덜 어두우면 기준에 못 미친다.
        final lighter = HSLColor.fromColor(
          ink,
        ).withLightness(HSLColor.fromColor(ink).lightness + 0.01).toColor();
        expect(contrastOnWhite(lighter), lessThan(4.5));
      });
    }

    testWidgets('막대 위 마크는 흰 면에 노선색 테두리와 노선색 글자를 쓴다', (tester) async {
      await _pump(
        tester,
        const LineMark(label: '4', color: color, onLineColor: true),
      );

      expect(paragraphOf(tester, '4').text.style?.color, color);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(LineMark),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect((decoration.border! as Border).top.color, color);
    });
  });
}
