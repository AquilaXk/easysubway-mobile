import 'package:easysubway_mobile/accessible_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/rendered_typography.dart';

// 그려진 글자의 서체 검사가 표기를 바꾼 우회까지 잡는지 보인다(#503).
const _alias = 'Alias';

Future<List<String>> _violationsOf(WidgetTester tester, TextStyle style) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Text('샘플', style: style)),
    ),
  );
  return renderedTypographyViolations(tester);
}

void main() {
  testWidgets('역할 굵기와 대비용 700, 아이콘 글꼴은 통과한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text(
                '본문',
                style: TextStyle(fontWeight: EasySubwayFontWeight.regular),
              ),
              Text(
                '강조',
                style: TextStyle(fontWeight: EasySubwayFontWeight.emphasis),
              ),
              Text(
                '노선',
                style: TextStyle(
                  fontWeight: EasySubwayFontWeight.boldForContrast,
                  color: Colors.white,
                ),
              ),
              Text(
                '방면 제목',
                style: TextStyle(
                  fontWeight: EasySubwayFontWeight.boldForContrast,
                  color: Color(0xFF00A84D),
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );

    expect(renderedTypographyViolations(tester), isEmpty);
  });

  testWidgets('상수로 돌려 지정한 family를 잡는다', (tester) async {
    expect(await _violationsOf(tester, const TextStyle(fontFamily: _alias)), [
      '"샘플" family $_alias',
    ]);
  });

  testWidgets('FontWeight.values 인덱스로 고른 굵기를 잡는다', (tester) async {
    expect(
      await _violationsOf(tester, TextStyle(fontWeight: FontWeight.values[8])),
      ['"샘플" 굵기 FontWeight.w900'],
    );
  });

  testWidgets('색이 없는 700을 잡는다', (tester) async {
    expect(
      await _violationsOf(tester, TextStyle(fontWeight: FontWeight.values[6])),
      hasLength(1),
    );
  });

  testWidgets('이미 4.5:1을 넘는 본문색의 700은 대비용이 아니라 잡는다', (tester) async {
    expect(
      await _violationsOf(
        tester,
        TextStyle(
          fontWeight: FontWeight.values[6],
          color: EasySubwayAccessibleColors.contentPrimary,
        ),
      ),
      hasLength(1),
    );
  });

  testWidgets('가변 글꼴 축 지정을 잡는다', (tester) async {
    final violations = await _violationsOf(
      tester,
      const TextStyle(fontVariations: [FontVariation('wght', 900)]),
    );

    expect(violations, hasLength(1));
    expect(violations.single, contains('fontVariations'));
  });
}
