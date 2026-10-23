import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_viewport.dart';

/// 호스트 위젯 안의 모든 글자에 `textContrastGuideline`을 건다(#503).
///
/// `textContrastGuideline`은 의미 노드의 라벨과 글자가 같은 [Text]만 검사한다.
/// 노선색 위 글자는 대개 `ExcludeSemantics` 안에 있거나 "이전역 신림"처럼 접두어가
/// 붙은 라벨로 합쳐져 가이드라인이 글자를 찾지 못하고 통과한다. `Text.rich`는 찾기는
/// 하지만 두 군데서 틀린다. 크기와 굵기를 span이 아니라 `Text.style`에서 읽고(span에만
/// 스타일이 있으면 기본 본문 스타일로 판정), 색은 문구 전체 상자의 최빈 픽셀로 재서
/// "금정 방면"의 노선색 이름과 남색 "방면"이 섞인다.
///
/// 이 도우미는 호스트의 의미 노드를 모두 끄고, 호스트를 그대로 그린 뒤 span마다(일반
/// [Text]는 글자 전체가 span 하나다) 그 자리에 같은 문구의 의미 노드와 투명한 대역
/// [Text]를 겹친다. 대역은 그려진 span의 실제 서체 설정을 그대로 달고 있어서
/// 가이드라인이 span의 크기와 굵기로 판정하고, 대비는 호스트가 그린 화면 픽셀에서
/// span 자리만 잰다. 겹친 대역은 아무것도 그리지 않지만 탭은 받으므로, 이 도우미로
/// 그린 화면을 눌러 보는 용도로 쓰지 않는다.
///
/// 가이드라인은 글자를 못 찾거나 화면 밖이거나 가려져 있으면 조용히 통과한다. 그래서
/// span마다 가이드라인을 따로 돌리고 실제 판정에 닿은 횟수를 센다. 한 번도 닿지
/// 못한 span이 있으면 통과가 아니라 실패다.
Future<void> expectHostTextContrast(
  WidgetTester tester,
  Widget host, {
  double textScale = 1.0,
}) async {
  final result = await evaluateHostTextContrast(
    tester,
    host,
    textScale: textScale,
  );
  expect(result.passed, isTrue, reason: result.reason);
}

/// [expectHostTextContrast]의 판정만 돌려준다. 도우미가 위반을 실제로 잡는지
/// 보이는 테스트가 쓴다.
Future<Evaluation> evaluateHostTextContrast(
  WidgetTester tester,
  Widget host, {
  double textScale = 1.0,
}) async {
  useLogicalViewport(tester, const Size(360, 800));
  final semantics = tester.ensureSemantics();
  try {
    return await _checkContrast(tester, host, textScale);
  } finally {
    semantics.dispose();
  }
}

Future<Evaluation> _checkContrast(
  WidgetTester tester,
  Widget host,
  double textScale,
) async {
  final active = ValueNotifier<_Probe?>(null);
  addTearDown(active.dispose);
  const hostKey = Key('host-text-contrast-host');
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            ExcludeSemantics(
              child: KeyedSubtree(key: hostKey, child: host),
            ),
            ValueListenableBuilder<_Probe?>(
              valueListenable: active,
              builder: (context, probe, _) =>
                  Stack(children: [if (probe != null) probe.overlay()]),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final texts = find.descendant(
    of: find.byKey(hostKey),
    matching: find.byType(Text),
  );
  final probes = <_Probe>[];
  final problems = <String>[];
  for (final element in texts.evaluate()) {
    _collectProbes(element, probes, problems);
  }
  expect(probes, isNotEmpty, reason: '호스트에서 검사할 글자를 찾지 못했다');

  var result = problems.isEmpty
      ? const Evaluation.pass()
      : Evaluation.fail(problems.join('\n'));
  for (final probe in probes) {
    active.value = probe;
    await tester.pump();
    final guideline = _CountingTextContrastGuideline();
    result += await guideline.evaluate(tester);
    if (guideline.judgedCount == 0) {
      result += Evaluation.fail(
        '"${probe.label}"이 가이드라인 판정에 닿지 못했다. 화면 밖이거나 가려졌거나 '
        '색을 잴 픽셀이 없다.',
      );
    }
  }
  return result;
}

/// [Text] 하나가 그린 문단을 span 단위 검사 대상으로 나눠 [probes]에 담는다.
/// 위치를 구하지 못한 span은 건너뛰지 않고 [problems]에 적어 실패로 만든다.
void _collectProbes(Element text, List<_Probe> probes, List<String> problems) {
  final paragraph = _paragraphOf(text.renderObject);
  if (paragraph == null || !paragraph.hasSize) {
    final widget = text.widget as Text;
    final shown = widget.data ?? widget.textSpan?.toPlainText();
    problems.add('Text "$shown"의 문단을 찾지 못했다');
    return;
  }
  final toGlobal = paragraph.getTransformTo(null);
  var offset = 0;

  void visit(InlineSpan span, TextStyle? inherited) {
    final style = span.style == null
        ? inherited
        : (inherited?.merge(span.style) ?? span.style);
    if (span is! TextSpan) {
      offset += 1;
    } else {
      final data = span.text ?? '';
      final start = offset + data.length - data.trimLeft().length;
      final end = offset + data.trimRight().length;
      if (start < end) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        if (boxes.isEmpty) {
          problems.add('"${data.trim()}"의 화면 위치를 구하지 못했다');
        } else {
          final local = boxes
              .map((box) => box.toRect())
              .reduce((a, b) => a.expandToInclude(b));
          probes.add(
            _Probe(
              data.trim(),
              MatrixUtils.transformRect(toGlobal, local),
              (style ?? const TextStyle()).copyWith(inherit: false),
            ),
          );
        }
      }
      offset += data.length;
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }
  }

  visit(paragraph.text, null);
}

RenderParagraph? _paragraphOf(RenderObject? root) {
  RenderParagraph? found;
  void visit(RenderObject node) {
    if (found != null) {
      return;
    }
    if (node is RenderParagraph) {
      found = node;
      return;
    }
    node.visitChildren(visit);
  }

  if (root != null) {
    visit(root);
  }
  return found;
}

class _Probe {
  const _Probe(this.label, this.rect, this.style);

  final String label;
  final Rect rect;
  final TextStyle style;

  Widget overlay() => Positioned.fromRect(
    rect: rect,
    child: Semantics(
      label: label,
      container: true,
      child: Opacity(
        opacity: 0,
        child: Text(label, style: style, maxLines: 1, softWrap: false),
      ),
    ),
  );
}

/// `textContrastGuideline`과 같은 판정에, 실제로 판정까지 간 글자 수를 센다.
/// `targetContrastRatio`는 가이드라인이 위치·화면 안·픽셀 검사를 모두 넘은 글자에만
/// 부른다.
class _CountingTextContrastGuideline extends MinimumTextContrastGuideline {
  _CountingTextContrastGuideline();

  int judgedCount = 0;

  @override
  double targetContrastRatio(double? fontSize, {required bool bold}) {
    judgedCount++;
    return super.targetContrastRatio(fontSize, bold: bold);
  }
}
