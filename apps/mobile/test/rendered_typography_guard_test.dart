import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/datapack_line_colors.dart';
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

  testWidgets('본문색의 700은 대비용이 아니라 잡는다', (tester) async {
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

  testWidgets('노선색을 흰 바탕용으로 어둡게 한 글자색의 700은 통과한다', (tester) async {
    for (final color in datapackLineColors) {
      expect(
        await _violationsOf(
          tester,
          TextStyle(
            fontWeight: EasySubwayFontWeight.boldForContrast,
            color: lineInkOnWhite(color),
          ),
        ),
        isEmpty,
        reason: '$color',
      );
    }
  });

  testWidgets('흰색도 노선색도 아닌 색의 700을 잡는다', (tester) async {
    final violations = await _violationsOf(
      tester,
      TextStyle(
        fontWeight: FontWeight.values[6],
        color: const Color(0xFF123456),
      ),
    );

    expect(violations, hasLength(1));
    expect(violations.single, contains('흰색도 노선색도 아닌'));
  });

  group('흰 바탕 위 노선색 글자의 700은 노선과 관계없이 통과한다', () {
    Future<List<String>> titleViolations(
      WidgetTester tester,
      Color color,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text(
              '금정',
              style: TextStyle(
                color: color,
                fontWeight: EasySubwayFontWeight.boldForContrast,
              ),
            ),
          ),
        ),
      );
      return renderedTypographyViolations(tester);
    }

    // 1호선 7.66:1과 신분당선 5.44:1은 굵게 하지 않아도 4.5:1을 넘지만, 노선마다
    // 굵기가 달라 보이지 않게 같은 700을 쓴다.
    for (final lineName in const ['1호선', '2호선', '신분당선', '공항철도']) {
      testWidgets('$lineName 노선색 이름이 통과한다', (tester) async {
        final color = stationLineColor(
          fallbackLineColorHex(lineName: lineName),
        );

        expect(await titleViolations(tester, color), isEmpty);
      });
    }

    testWidgets('데이터팩의 모든 노선색 이름이 통과한다', (tester) async {
      for (final color in datapackLineColors) {
        expect(await titleViolations(tester, color), isEmpty, reason: '$color');
      }
    });

    testWidgets('데이터팩 노선색은 표준 노선 13개를 모두 품는다', (tester) async {
      for (final lineName in const [
        '1호선',
        '2호선',
        '3호선',
        '4호선',
        '5호선',
        '6호선',
        '7호선',
        '8호선',
        '9호선',
        '경의중앙선',
        '수인분당선',
        '신분당선',
        '공항철도',
      ]) {
        expect(
          datapackLineColors,
          contains(stationLineColor(fallbackLineColorHex(lineName: lineName))),
          reason: lineName,
        );
      }
    });
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
