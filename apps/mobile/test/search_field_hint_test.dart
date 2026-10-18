import 'package:easysubway_mobile/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 슬롯 라벨이 있는 검색 필드는 hint를 semantics에서 빼려고 hintText 대신 hint 위젯을
/// 쓴다. 이 테스트는 보이는 placeholder가 기본 hintText 경로와 같은 모습인지,
/// 낭독이 한 번뿐이고 입력 필드 역할이 유지되는지 고정한다.
const _hint = '역 이름을 입력해 주세요';

Future<void> _pumpField(
  WidgetTester tester, {
  required String? semanticsLabel,
  required double textScale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SizedBox(
            width: 240,
            child: EasySubwaySearchField(
              hintText: _hint,
              autofocus: true,
              semanticsLabel: semanticsLabel,
            ),
          ),
        ),
      ),
    ),
  );
}

RenderParagraph _hintParagraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.text(_hint));

/// 스크린리더에 노출되는(부모에 병합되지 않은) 입력 필드 노드 하나의 병합 데이터.
SemanticsData _announcedTextField(WidgetTester tester) {
  final found = <SemanticsData>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (!node.isMergedIntoParent && data.flagsCollection.isTextField) {
      found.add(data);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(EasySubwaySearchField)));
  expect(found, hasLength(1));
  return found.single;
}

void main() {
  for (final textScale in [1.0, 2.0]) {
    testWidgets('슬롯 라벨 경로의 placeholder가 기본 hintText 경로와 같다 - 글자 $textScale배', (
      tester,
    ) async {
      await _pumpField(tester, semanticsLabel: null, textScale: textScale);
      final plain = _hintParagraph(tester);
      final plainSize = plain.size;
      final plainStyle = plain.text.style;
      final plainMaxLines = plain.maxLines;
      final plainOverflow = plain.overflow;

      await _pumpField(tester, semanticsLabel: _hint, textScale: textScale);
      final labeled = _hintParagraph(tester);

      expect(labeled.size, plainSize);
      expect(labeled.text.style, plainStyle);
      expect(labeled.maxLines, plainMaxLines);
      expect(labeled.overflow, plainOverflow);
    });
  }

  testWidgets('슬롯 라벨 경로는 같은 문구를 한 번만 낭독하고 입력 필드 역할을 유지한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpField(tester, semanticsLabel: _hint, textScale: 1.0);
    await tester.pumpAndSettle();

    final data = _announcedTextField(tester);
    expect(data.label, _hint);
    expect(data.flagsCollection.isTextField, isTrue);
    expect(data.flagsCollection.isReadOnly, isFalse);
    expect(data.hasAction(SemanticsAction.setText), isTrue);
    expect(data.hasAction(SemanticsAction.focus), isTrue);
    semantics.dispose();
  });

  test('semanticsLabel은 hintText와 같아야 한다', () {
    expect(
      () => EasySubwaySearchField(hintText: _hint, semanticsLabel: '다른 문구'),
      throwsAssertionError,
    );
  });
}
