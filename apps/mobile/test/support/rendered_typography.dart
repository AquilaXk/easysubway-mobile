import 'package:easysubway_mobile/accessible_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _materialIconsFamily = 'MaterialIcons';

final _allowedWeights = <FontWeight>{
  EasySubwayFontWeight.regular,
  EasySubwayFontWeight.emphasis,
  EasySubwayFontWeight.boldForContrast,
};

/// 화면에 그려진 모든 글자의 서체 설정 중 앱 규칙을 어긴 것을 모은다(#503).
///
/// 소스 정규식은 `const _f = 'X'; TextStyle(fontFamily: _f)`, `FontWeight.values[8]`,
/// `FontVariation('wght', 900)`처럼 표기를 바꾼 우회를 놓친다. 이 검사는 표기가 아니라
/// 그려진 결과를 본다. 규칙은 다음과 같다.
/// - family는 테마 기본 서체거나 아이콘 글꼴이다. 앱 번들 글꼴은 없다.
/// - 굵기는 본문 400, 강조 500, 대비용 700 중 하나다. 700은 노선색 면 위 흰 글자만 쓴다.
/// - 글자는 가변 글꼴 축(`fontVariations`)을 따로 지정하지 않는다. 아이콘 글꼴의 축은 제외한다.
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
          style.color != EasySubwayColorPrimitives.neutralWhite) {
        violations.add('"$text" 대비용 700이 흰 글자가 아님 ${style.color}');
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
