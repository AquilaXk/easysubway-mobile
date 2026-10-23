import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 호스트 위젯 안의 모든 [Text]에 `textContrastGuideline`을 건다(#503).
///
/// `textContrastGuideline`은 의미 노드의 라벨과 글자가 같은 [Text]만 검사한다.
/// 노선색 위 글자는 대개 `ExcludeSemantics` 안에 있거나 "이전역 신림"처럼 접두어가
/// 붙은 라벨로 합쳐져 가이드라인이 글자를 찾지 못하고 통과한다. 이 도우미는 호스트를
/// 그대로 그린 뒤 각 글자 자리에 같은 문구의 빈 의미 노드를 겹쳐, 호스트의 의미
/// 구성과 무관하게 모든 글자가 검사되게 한다. 겹친 노드는 아무것도 그리지 않고
/// 탭도 가로채지 않는다.
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
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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
  final probes = ValueNotifier<List<_Probe>>(const []);
  addTearDown(probes.dispose);
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
            KeyedSubtree(key: hostKey, child: host),
            ValueListenableBuilder<List<_Probe>>(
              valueListenable: probes,
              builder: (context, value, _) => Stack(
                children: [
                  for (final probe in value)
                    Positioned.fromRect(
                      rect: probe.rect,
                      child: Semantics(label: probe.label, container: true),
                    ),
                ],
              ),
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
  final found = <_Probe>[];
  for (final element in texts.evaluate()) {
    final label = (element.widget as Text).data;
    if (label == null || label.trim().isEmpty) {
      continue;
    }
    final box = element.renderObject! as RenderBox;
    found.add(_Probe(label, box.localToGlobal(Offset.zero) & box.size));
  }
  expect(found, isNotEmpty, reason: '호스트에서 검사할 글자를 찾지 못했다');
  probes.value = found;
  await tester.pump();

  return textContrastGuideline.evaluate(tester);
}

class _Probe {
  const _Probe(this.label, this.rect);

  final String label;
  final Rect rect;
}
