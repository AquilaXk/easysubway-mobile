import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/core_screen_sweep_fixtures.dart';
import 'support/core_screen_sweep_screens.dart';
import 'support/full_tap_target_guideline.dart';
import 'support/rendered_typography.dart';

/// 핵심 화면 x 테마 x 글자 크기 x 접근성 가이드라인 전수 검사(#464).
///
/// 화면은 [sweepScreens] 표의 한 줄로 추가한다. 가이드라인 6종은 [_guidelines]
/// 표 하나로 모든 조합에 같은 방식으로 적용한다. 위반은 예외 목록 없이 그대로
/// 실패로 드러난다.
///
/// 번들 폰트는 일부러 로드하지 않는다. `textContrastGuideline`은 화면 캡처의 색
/// 빈도로 글자색을 추정하므로, 얇은 실제 글꼴은 플랫폼별 안티앨리어싱 차이로
/// 같은 코드에서도 macOS와 Linux 결과가 갈린다. 테스트 기본 폰트(Ahem)는 글자가
/// 단색 사각형이라 색 추정이 플랫폼과 무관하게 같다.
///
/// 팬 메뉴의 글자는 CustomPaint로 그려져 `textContrastGuideline`이 볼 수 없다.
/// 팬 메뉴 역할색의 글자 대비는 `design_tokens_test`가 단언한다.
///
/// 한계: 이 테스트는 기기 시스템 서체의 글자 대비와 오버플로를 검증하지
/// 않는다. Ahem은 글자 폭이 달라 1.5배 줄바꿈과 넘침도 근사치다. 실제 폰트의
/// 대비·오버플로는 실기기 점검(에픽 #3036 체크리스트 4번 후속 행)이 맡는다.

const _textScales = <double>[1.0, 1.5];

/// 긴 목록도 화면 안에 모두 그려 가이드라인이 끝까지 검사하도록 세로를 길게 둔다.
const _logicalViewport = Size(360, 2000);
const _devicePixelRatio = 3.0;

final _guidelines = <String, AccessibilityGuideline>{
  'Android 탭 영역 48dp': androidTapTargetGuideline,
  'iOS 탭 영역 44pt': iOSTapTargetGuideline,
  '스크롤 안 포함 Android 탭 영역 48dp': FullTapTargetGuideline(androidMinTapTarget),
  '스크롤 안 포함 iOS 탭 영역 44pt': FullTapTargetGuideline(iosMinTapTarget),
  '탭 가능한 요소의 라벨': labeledTapTargetGuideline,
  '글자 대비': textContrastGuideline,
};

void main() {
  // 지도 역 위치가 실행 순서에 따라 달라지지 않도록 오너 노드·라벨 사이드카를 비운다.
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });
  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  for (final screen in sweepScreens) {
    for (final theme in SweepTheme.values) {
      for (final textScale in _textScales) {
        testWidgets('${screen.name} - ${theme.label} - 글자 $textScale배', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          final reportedErrors = <FlutterErrorDetails>[];
          Future<void> checkScreen() async {
            final navigatorKey = GlobalKey<NavigatorState>();
            await _pumpApp(tester, screen, navigatorKey, theme, textScale);
            await screen.open(
              SweepScreenContext(
                tester: tester,
                navigatorKey: navigatorKey,
                theme: theme,
              ),
            );

            expect(screen.shown, findsOneWidget);
            expect(tester.takeException(), isNull);
            expect(await _violations(tester), isEmpty);
            expect(_ambiguousTapLabels(tester), isEmpty);
            expect(renderedTypographyViolations(tester), isEmpty);
          }

          try {
            if (screen.inboxLoad != SweepInboxLoad.normal) {
              // 조회 실패는 화면에 오류 상태로 드러나야 하고 오류 보고로도 남아야 한다.
              await runWithMobileErrorReporter(reportedErrors.add, checkScreen);
              expect(reportedErrors, isNotEmpty);
            } else {
              await checkScreen();
            }
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}

/// 화면 하나에 모든 가이드라인을 적용하고 위반한 요소마다 한 줄씩 모은다.
Future<List<String>> _violations(WidgetTester tester) async {
  final violations = <String>[];
  for (final MapEntry(:key, :value) in _guidelines.entries) {
    final evaluation = await value.evaluate(tester);
    if (!evaluation.passed) {
      violations.addAll(
        _violatingNodes(evaluation.reason).map((n) => '$key | $n'),
      );
    }
  }
  return violations;
}

/// 한 화면에서 탭할 수 있는 요소가 같은 라벨을 나눠 쓰거나, 한 요소의 라벨이 같은
/// 문구를 되풀이하면 스크린리더 사용자가 요소를 구분하지 못하거나 같은 말을 두 번
/// 듣는다. 둘 중 하나에 걸린 라벨을 사유와 함께 모아 돌려준다.
///
/// 부모에 병합된 노드는 스크린리더에 따로 노출되지 않으므로 세지 않는다.
List<String> _ambiguousTapLabels(WidgetTester tester) {
  final counts = <String, int>{};
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (!node.isInvisible &&
        !node.isMergedIntoParent &&
        data.hasAction(SemanticsAction.tap)) {
      // 아이콘 버튼은 라벨 없이 tooltip만으로 이름을 얻는다.
      final name = data.label.isNotEmpty ? data.label : data.tooltip;
      if (name.isNotEmpty) {
        counts.update(name, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(MaterialApp)));
  return [
    for (final MapEntry(:key, :value) in counts.entries) ...[
      if (value > 1) '$key | 같은 라벨 x$value',
      if (_hasRepeatedLine(key)) '$key | 라벨 문구 반복',
    ],
  ];
}

/// 병합된 라벨에 같은 문구가 이웃한 줄로 되풀이되는 경우(예: "A\nA")다. 병합이 같은
/// 문구를 두 번 더하면 이렇게 붙어 나온다. 한 글자짜리 줄("-" 같은 빈 값 표시)은
/// 서로 다른 항목에서 우연히 이웃할 수 있어 제외한다. 떨어진 곳의 같은 줄은 서로 다른
/// 항목의 같은 값일 수 있어 보지 않는다.
bool _hasRepeatedLine(String label) {
  final lines = label.split('\n');
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].length > 1 && lines[i] == lines[i - 1]) {
      return true;
    }
  }
  return false;
}

final _nodeLabelPattern = RegExp(r'label: "([^"]*)"');
final _nodeRectPattern = RegExp(r'Rect\.fromLTRB\(([^)]*)\)');

/// 가이드라인이 돌려준 여러 줄 사유를 요소 단위 한 줄(라벨, 영역, 사유)로 줄인다.
List<String> _violatingNodes(String? reason) {
  final text = reason ?? '';
  final nodes = text.split('SemanticsNode#').skip(1).map((chunk) {
    final label = _nodeLabelPattern.firstMatch(chunk)?[1] ?? '';
    final rect = _nodeRectPattern.firstMatch(chunk)?[1] ?? '';
    final detail = chunk.split('):\n').skip(1).join().split('\n').first;
    return '"$label" [$rect] $detail';
  }).toList();
  return nodes.isEmpty ? [text] : nodes;
}

Future<void> _pumpApp(
  WidgetTester tester,
  SweepScreen screen,
  GlobalKey<NavigatorState> navigatorKey,
  SweepTheme theme,
  double textScale,
) async {
  tester.view.devicePixelRatio = _devicePixelRatio;
  tester.view.physicalSize = _logicalViewport * _devicePixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue =
      theme.platformBrightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
  await tester.pumpWidget(
    buildSweepApp(
      navigatorKey: navigatorKey,
      onboardingState: screen.onboardingState(theme),
      stationResults: screen.stationResults,
      inboxLoad: screen.inboxLoad,
    ),
  );
  await tester.pumpAndSettle();
}
