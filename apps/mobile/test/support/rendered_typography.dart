import 'package:easysubway_mobile/accessible_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'datapack_line_colors.dart';

const _materialIconsFamily = 'MaterialIcons';

final _allowedWeights = <FontWeight>{
  EasySubwayFontWeight.regular,
  EasySubwayFontWeight.emphasis,
  EasySubwayFontWeight.boldForContrast,
};

/// 대비용 700이 정당한 글자색이다. 노선색 면 위 흰 글자거나, 흰 바탕 위 노선색 글자다.
/// 노선색 글자는 노선마다 굵기가 달라 보이지 않게 모든 노선을 700으로 맞춘다. 굵게
/// 하면 흰 바탕 위 대비 기준이 4.5:1에서 큰 글자 기준 3:1로 내려가 2·5·6·7·8호선과
/// 공항철도를 구한다. 3·4·9호선, 경의중앙선, 수인분당선은 굵게 해도 3:1에 못 미치며 이는
/// 별도로 추적하는 기존 문제다. 대비율은 여기서 따지지 않는다. 호스트별 대비는
/// `expectHostTextContrast`가 보고, 어느 호스트가 700을 쓸 수 있는지는 소스 쪽
/// `design_guard_test`의 허용 목록이 정한다.
bool _isContrastBoldColor(Color? color) =>
    color != null &&
    (color == EasySubwayColorPrimitives.neutralWhite ||
        datapackLineColors.contains(color));

/// 화면에 그려진 모든 글자의 서체 설정 중 앱 규칙을 어긴 것을 모은다(#503).
///
/// 소스 정규식은 `const _f = 'X'; TextStyle(fontFamily: _f)`, `FontWeight.values[8]`,
/// `FontVariation('wght', 900)`처럼 표기를 바꾼 우회를 놓친다. 이 검사는 표기가 아니라
/// 그려진 결과를 본다. 규칙은 다음과 같다.
/// - family는 테마 기본 서체거나 아이콘 글꼴이다. 앱 번들 글꼴은 없다.
/// - 굵기는 본문 400, 강조 500, 대비용 700 중 하나다. 700은 흰색이나 데이터팩 노선색
///   글자(`_isContrastBoldColor`)에만 쓰고, 본문색 같은 다른 색에는 쓰지 않는다.
///   어느 호스트가 쓸 수 있는지는 소스 쪽 `design_guard_test`의 허용 목록이 정한다.
/// - 글자는 가변 글꼴 축(`fontVariations`)을 따로 지정하지 않는다. 아이콘 글꼴의 축은 제외한다.
///
/// 한계: [RenderParagraph]로 그려진 글자(`Text`, `RichText`)만 본다.
/// `RenderEditable`(입력창)이나 `TextPainter`로 직접 그린 글자(`CustomPaint`, 노선도
/// 캔버스)는 이 검사에 잡히지 않는다.
List<String> renderedTypographyViolations(WidgetTester tester) {
  final themeFamily = Theme.of(
    tester.element(find.byType(Navigator).first),
  ).textTheme.bodyMedium?.fontFamily;
  final violations = <String>[];

  void check(RenderParagraph paragraph) {
    paragraph.text.visitChildren((span) {
      final text = span is TextSpan ? span.text : null;
      final style = span.style;
      if (text == null || text.isEmpty || style == null) {
        return true;
      }
      final family = style.fontFamily;
      if (family != null &&
          family != themeFamily &&
          family != _materialIconsFamily) {
        violations.add('"$text" family $family');
      }
      final weight = style.fontWeight;
      if (weight != null && !_allowedWeights.contains(weight)) {
        violations.add('"$text" 굵기 $weight');
      }
      if (weight == EasySubwayFontWeight.boldForContrast &&
          !_isContrastBoldColor(style.color)) {
        violations.add('"$text" 대비용 700이 흰색도 노선색도 아닌 글자색 ${style.color}');
      }
      final isIcon = family == _materialIconsFamily;
      if (!isIcon && (style.fontVariations?.isNotEmpty ?? false)) {
        violations.add('"$text" fontVariations ${style.fontVariations}');
      }
      return true;
    });
  }

  void visit(RenderObject node) {
    if (node is RenderParagraph) {
      check(node);
    }
    node.visitChildren(visit);
  }

  tester.binding.renderViews.forEach(visit);
  return violations;
}
