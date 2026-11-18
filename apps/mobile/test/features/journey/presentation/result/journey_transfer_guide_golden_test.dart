import 'dart:io' show Platform;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/journey/presentation/result/journey_result_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/korean_test_font.dart';

// #451: 환승 노드 아래 이동 안내 단계의 화면 고정. 고속터미널 9호선 사평 방면 →
// 3호선 잠원 방면 문장은 국토교통부 원문 그대로다.
const _boundaryKey = ValueKey('journey-transfer-guide-golden-boundary');
const _injectVisualMutation = bool.fromEnvironment(
  'EASYSUBWAY_GOLDEN_MUTATION',
);
const _goldenBackground = Color(0xFFFFFFFF);
const _mutationBackground = Color(0xFF004D40);

const _steps = <String>[
  '1) 사평 방면 승강장',
  '2) 엘리베이터 이용',
  '3) 지하 2층으로 이동',
  '4) 7호선 환승통로 이동',
  '5) 3호선 잠원 방면 엘리베이터 이용',
  '6) 지하 3층으로 이동',
  '7) 3호선 잠원 방면 승강장',
];

Widget _transferNode({required bool expanded, List<String> steps = _steps}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox.square(
        dimension: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: EasySubwayAccessibleColors.surface,
            border: Border.all(
              color: EasySubwayAccessibleColors.primary,
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.sync_alt_rounded,
            size: 13,
            color: EasySubwayAccessibleColors.primary,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '고속터미널',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: EasySubwayAccessibleColors.text,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '환승 · 도보 4분',
              style: TextStyle(
                fontSize: 13,
                color: EasySubwayAccessibleColors.secondaryText,
              ),
            ),
            JourneyTransferGuideSteps(
              legIndex: 2,
              steps: steps,
              expanded: expanded,
              onToggle: () {},
            ),
          ],
        ),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: koreanTestFontFamily),
      home: Scaffold(
        backgroundColor: _goldenBackground,
        body: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: ColoredBox(
              color: _injectVisualMutation
                  ? _mutationBackground
                  : _goldenBackground,
              child: SizedBox(
                width: 360,
                child: Padding(padding: const EdgeInsets.all(16), child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKoreanTestFont);

  // golden 비교는 macOS 호스트 래스터라이저에서만 수행한다(CI 크로스플랫폼 오탐 방지).
  // 정본 기준 호스트는 GitHub Actions `macos-15` (macOS 15 Sequoia, Flutter `3.44.0`,
  // `.github/workflows/mobile-golden.yml:19`)이며, 다른 macOS 메이저 버전 호스트(예:
  // `macOS 27.0.1`)에서는 CoreGraphics/Skia 폰트·아이콘 서브픽셀 안티에일리어싱 차이로
  // 0.10~0.51% 픽셀 차이가 발생할 수 있다.
  final skipReason = !Platform.isMacOS;

  testWidgets('환승 노드 아래 이동 방법(접힘)', (tester) async {
    await _pump(tester, _transferNode(expanded: false));
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_transfer_guide_collapsed.png'),
    );
  }, skip: skipReason);

  testWidgets('환승 노드 아래 이동 방법(펼침) 고속터미널 9호선 to 3호선', (tester) async {
    await _pump(tester, _transferNode(expanded: true));
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_transfer_guide_expanded.png'),
    );
  }, skip: skipReason);

  testWidgets('이동 안내 행이 없는 환승은 현재 노드 그대로', (tester) async {
    await _pump(tester, _transferNode(expanded: false, steps: const []));
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_transfer_guide_none.png'),
    );
  }, skip: skipReason);
}
