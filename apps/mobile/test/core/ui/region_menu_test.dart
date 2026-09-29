import 'dart:async';

import 'package:easysubway_mobile/core/ui/region_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('지역 메뉴를 열면 트리거 버튼 바로 아래에 정갈한 드롭다운 패널이 열린다', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 40),
              child: Builder(
                builder: (ctx) => TextButton(
                  key: const Key('openRegionMenuButton'),
                  onPressed: () {
                    unawaited(
                      showEasySubwayRegionMenu(
                        triggerContext: ctx,
                        regions: const [
                          EasySubwayRegionMenuItem(id: '수도권', label: '수도권'),
                          EasySubwayRegionMenuItem(id: '부산', label: '부산'),
                          EasySubwayRegionMenuItem(id: '대구', label: '대구'),
                          EasySubwayRegionMenuItem(id: '광주', label: '광주'),
                          EasySubwayRegionMenuItem(id: '대전', label: '대전'),
                        ],
                        selectedRegion: '수도권',
                        onRegionSelected: (val) => selected = val,
                      ),
                    );
                  },
                  child: const Text('수도권 ⌵'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final triggerFinder = find.byKey(const Key('openRegionMenuButton'));
    final triggerRect = tester.getRect(triggerFinder);

    await tester.tap(triggerFinder);
    await tester.pumpAndSettle();

    final panelFinder = find.byType(EasySubwayRegionMenuPanel);
    expect(panelFinder, findsOneWidget);

    // 트리거 버튼 바로 아래 및 좌측 벽 완벽 밀착 검증
    final panelRect = tester.getRect(panelFinder);
    expect(panelRect.left, equals(0.0));
    expect(panelRect.top, greaterThanOrEqualTo(triggerRect.bottom));

    // 미니멀 정돈: AI 슬롭 타이틀/서브설명/노선수 TMI가 없는지 검증
    expect(
      find.descendant(of: panelFinder, matching: find.text('지역 선택')),
      findsNothing,
    );
    expect(find.text('노선도를 확인할 지역을 선택해 주세요'), findsNothing);
    expect(find.text('23개 노선'), findsNothing);

    // 5대 도시권 목록 검증 및 터치 영역(48dp) 검증
    for (final regionName in ['수도권', '부산', '대구', '광주', '대전']) {
      final item = find.text(regionName);
      expect(item, findsOneWidget);
      final rowFinder = find.byKey(
        ValueKey('networkMapRegionMenuRow_$regionName'),
      );
      expect(rowFinder, findsOneWidget);
      final rowSize = tester.getSize(rowFinder);
      expect(rowSize.height, equals(48.0));
    }

    // 현재 선택된 지역(수도권) 하이라이트 및 체크마크(✓) 검증
    final checkmarkFinder = find.byKey(const Key('regionSelectedCheckmark'));
    expect(checkmarkFinder, findsOneWidget);

    final selectedRow = find.byKey(
      const ValueKey('networkMapRegionMenuRow_수도권'),
    );
    expect(selectedRow, findsOneWidget);

    // 부산 탭 시 햅틱 및 콜백 호출 후 닫힘 검증
    await tester.tap(find.byKey(const ValueKey('networkMapRegionMenuRow_부산')));
    await tester.pumpAndSettle();

    expect(selected, '부산');
    expect(find.byType(EasySubwayRegionMenuPanel), findsNothing);
  });

  testWidgets('드롭다운 외부 스크림을 탭하면 정상적으로 닫힌다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => TextButton(
                key: const Key('openRegionMenuButton'),
                onPressed: () {
                  unawaited(
                    showEasySubwayRegionMenu(
                      triggerContext: ctx,
                      regions: const [
                        EasySubwayRegionMenuItem(id: '수도권', label: '수도권'),
                        EasySubwayRegionMenuItem(id: '부산', label: '부산'),
                      ],
                      selectedRegion: '수도권',
                      onRegionSelected: (_) {},
                    ),
                  );
                },
                child: const Text('수도권 ⌵'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('openRegionMenuButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EasySubwayRegionMenuPanel), findsOneWidget);

    // 스크림 영역 (x: 10, y: 10) 탭
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byType(EasySubwayRegionMenuPanel), findsNothing);
  });

  testWidgets('지역 목록이 비어 있으면 기본 수도권 항목이 제공된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => TextButton(
                key: const Key('openEmptyRegionMenuButton'),
                onPressed: () {
                  unawaited(
                    showEasySubwayRegionMenu(
                      triggerContext: ctx,
                      regions: const [],
                      selectedRegion: '수도권',
                      onRegionSelected: (_) {},
                    ),
                  );
                },
                child: const Text('수도권 ⌵'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('openEmptyRegionMenuButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EasySubwayRegionMenuPanel), findsOneWidget);
    expect(find.text('수도권'), findsWidgets);
  });

  group('#404 큰 글자 설정에서 권역명이 잘리지 않는다', () {
    testWidgets('세로 화면·글자 배율 1.0에서는 행 48dp·패널 124×248dp 모양이 그대로다', (
      tester,
    ) async {
      await _openRegionMenuAtTextScale(
        tester,
        screenSize: _portraitPhone,
        textScaler: TextScaler.linear(1.0),
        regions: _fiveMetroRegions,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(EasySubwayRegionMenuPanel)),
        const Size(124.0, 248.0),
      );
      for (final region in _fiveMetroRegions) {
        final rowSize = tester.getSize(
          find.byKey(ValueKey('networkMapRegionMenuRow_${region.id}')),
        );
        expect(rowSize.height, 48.0, reason: '${region.label} 행 높이');
      }
    });

    // 테스트 폰트는 모든 글자가 1em 정사각형이다. 가장 긴 행은 선택된 `수도권`
    // (글자 3개, 글자마다 자간 -0.2 + 간격 8 + 체크 아이콘 20 + 좌우 패딩 28)이다.
    // 1.5배는 3×(24-0.2)+56=127.4, 2.0배는 3×(32-0.2)+56=151.4다.
    for (final (textScale, expectedPanelWidth) in const [
      (1.5, 127.4),
      (2.0, 151.4),
    ]) {
      testWidgets('글자 배율 $textScale에서 모든 권역명이 한 줄로 전부 보이고 패널 폭은 가장 긴 행에 맞춘다', (
        tester,
      ) async {
        await _openRegionMenuAtTextScale(
          tester,
          screenSize: _portraitPhone,
          textScaler: TextScaler.linear(textScale),
          regions: _fiveMetroRegions,
        );

        expect(tester.takeException(), isNull);
        _expectPanelInsideScreen(tester, _portraitPhone);
        expect(
          tester.getSize(find.byType(EasySubwayRegionMenuPanel)).width,
          moreOrLessEquals(expectedPanelWidth, epsilon: 0.001),
          reason: '패널 폭은 글자 배율 비례 추정이 아니라 가장 긴 권역 행 폭(최소 124)이어야 한다',
        );
        _expectEveryRegionLabelFullyVisible(tester, _fiveMetroRegions);
        for (final region in _fiveMetroRegions) {
          _expectRegionLabelOnOneLine(tester, region);
        }
        _expectSelectedCheckmarkVisible(
          tester,
          screenWidth: _portraitPhone.width,
        );
        if (textScale == 2.0) {
          final selectedRow = find.byKey(
            const ValueKey('networkMapRegionMenuRow_수도권'),
          );
          final labelRect = tester.getRect(
            find.descendant(of: selectedRow, matching: find.text('수도권')),
          );
          final checkRect = tester.getRect(
            find.descendant(
              of: selectedRow,
              matching: find.byKey(const Key('regionSelectedCheckmark')),
            ),
          );
          expect(
            checkRect.left - labelRect.right,
            greaterThanOrEqualTo(8.0),
            reason: '큰 글자에서도 체크 아이콘이 권역명에 붙지 않고 8dp 이상 떨어져야 한다',
          );
        }
      });
    }

    testWidgets('큰 글자일수록 덜 키우는 비선형 배율에서도 선택 권역명이 한 줄로 전부 보인다', (tester) async {
      const textScaler = _AndroidLikeNonlinearTextScaler();
      // 픽스처 전제: 권역명 글자(16)는 2배가 되지만, 124 같은 큰 값은 늘지 않는다.
      // 그래서 `scale(124)`로 패널 폭을 정하면 선택 행이 줄바꿈된다.
      expect(textScaler.scale(16), 32.0);
      expect(textScaler.scale(124), 124.0);

      await _openRegionMenuAtTextScale(
        tester,
        screenSize: _portraitPhone,
        textScaler: textScaler,
        regions: _fiveMetroRegions,
      );

      expect(tester.takeException(), isNull);
      _expectPanelInsideScreen(tester, _portraitPhone);
      _expectEveryRegionLabelFullyVisible(tester, _fiveMetroRegions);
      for (final region in _fiveMetroRegions) {
        _expectRegionLabelOnOneLine(tester, region);
      }
      _expectSelectedCheckmarkVisible(
        tester,
        screenWidth: _portraitPhone.width,
      );
    });

    for (final textScale in const [2.0, 3.1]) {
      testWidgets(
        '폭 320dp 화면·글자 배율 $textScale에서 패널이 화면 밖으로 나가지 않고 권역명이 잘리지 않는다',
        (tester) async {
          const screenSize = Size(320, 640);
          const regions = [
            EasySubwayRegionMenuItem(id: '수도권', label: '수도권'),
            EasySubwayRegionMenuItem(id: '부산', label: '부산'),
            EasySubwayRegionMenuItem(id: '긴이름권역', label: '아주 긴 권역 이름 줄바꿈 확인'),
          ];
          await _openRegionMenuAtTextScale(
            tester,
            screenSize: screenSize,
            textScaler: TextScaler.linear(textScale),
            regions: regions,
          );

          expect(tester.takeException(), isNull);
          _expectPanelInsideScreen(tester, screenSize);
          expect(
            tester.getSize(find.byType(EasySubwayRegionMenuPanel)).width,
            greaterThanOrEqualTo(124.0),
          );
          _expectEveryRegionLabelFullyVisible(tester, regions);
          _expectSelectedCheckmarkVisible(
            tester,
            screenWidth: screenSize.width,
          );
        },
      );
    }

    testWidgets('폭 120dp 창에서는 기본 폭 124보다 화면 폭 상한이 우선해 패널이 창 안에 머문다', (
      tester,
    ) async {
      const screenSize = Size(120, 640);
      await _openRegionMenuAtTextScale(
        tester,
        screenSize: screenSize,
        textScaler: TextScaler.linear(1.0),
        regions: _fiveMetroRegions,
      );

      expect(tester.takeException(), isNull);
      _expectPanelInsideScreen(tester, screenSize);
      _expectEveryRegionLabelFullyVisible(tester, _fiveMetroRegions);
      _expectSelectedCheckmarkVisible(tester, screenWidth: screenSize.width);
    });

    testWidgets(
      '가로 화면(640×360)·글자 배율 2.0에서 패널이 화면 아래로 넘치지 않고 마지막 권역을 스크롤해 누를 수 있다',
      (tester) async {
        const screenSize = Size(640, 360);
        const bottomInset = 20.0;
        String? selected;
        await _openRegionMenuAtTextScale(
          tester,
          screenSize: screenSize,
          bottomInset: bottomInset,
          textScaler: TextScaler.linear(2.0),
          regions: _fiveMetroRegions,
          onRegionSelected: (id) => selected = id,
        );

        expect(tester.takeException(), isNull);
        _expectPanelInsideScreen(tester, screenSize);
        final panelRect = tester.getRect(
          find.byType(EasySubwayRegionMenuPanel),
        );
        expect(
          panelRect.bottom,
          lessThanOrEqualTo(screenSize.height - bottomInset),
          reason: '패널이 하단 시스템 영역을 덮는다',
        );

        final lastRow = find.byKey(
          const ValueKey('networkMapRegionMenuRow_대전'),
        );
        // 전제: 이 배치에서는 마지막 행이 처음에 패널 아래로 가려져 스크롤이 필요하다.
        expect(tester.getRect(lastRow).bottom, greaterThan(panelRect.bottom));

        await tester.ensureVisible(lastRow);
        await tester.pumpAndSettle();
        final lastRowRect = tester.getRect(lastRow);
        expect(lastRowRect.top, greaterThanOrEqualTo(panelRect.top));
        expect(lastRowRect.bottom, lessThanOrEqualTo(panelRect.bottom));

        await tester.tap(lastRow);
        await tester.pumpAndSettle();

        expect(selected, '대전');
        expect(find.byType(EasySubwayRegionMenuPanel), findsNothing);
      },
    );
  });
}

/// 세로 방향 기준 휴대폰 화면(dp).
const _portraitPhone = Size(360, 640);

const _fiveMetroRegions = [
  EasySubwayRegionMenuItem(id: '수도권', label: '수도권'),
  EasySubwayRegionMenuItem(id: '부산', label: '부산'),
  EasySubwayRegionMenuItem(id: '대구', label: '대구'),
  EasySubwayRegionMenuItem(id: '광주', label: '광주'),
  EasySubwayRegionMenuItem(id: '대전', label: '대전'),
];

/// Android 14+ 비선형 글자 배율(200%)을 흉내 낸다. 작은 글자(20 이하)는 2배로
/// 키우고, 큰 글자일수록 덜 키워 100 이상에서는 배율이 1이 된다.
class _AndroidLikeNonlinearTextScaler extends TextScaler {
  const _AndroidLikeNonlinearTextScaler();

  @override
  double scale(double fontSize) {
    if (fontSize <= 20) {
      return fontSize * 2;
    }
    if (fontSize >= 100) {
      return fontSize;
    }
    return 40 + (fontSize - 20) * 0.75;
  }

  @override
  double get textScaleFactor => 2.0;
}

/// 화면 크기를 [screenSize](dp)로, 시스템 글자 배율을 [textScaler]로 명시한 뒤
/// `수도권`을 선택한 채 권역 메뉴를 연다. [bottomInset]은 하단 시스템 영역(dp)이다.
Future<void> _openRegionMenuAtTextScale(
  WidgetTester tester, {
  required Size screenSize,
  required TextScaler textScaler,
  required List<EasySubwayRegionMenuItem> regions,
  double bottomInset = 0,
  ValueChanged<String>? onRegionSelected,
}) async {
  const devicePixelRatio = 2.0;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = screenSize * devicePixelRatio;
  tester.view.padding = FakeViewPadding(bottom: bottomInset * devicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, top: 40),
            child: Builder(
              builder: (ctx) => TextButton(
                key: const Key('openRegionMenuButton'),
                onPressed: () {
                  unawaited(
                    showEasySubwayRegionMenu(
                      triggerContext: ctx,
                      regions: regions,
                      selectedRegion: '수도권',
                      onRegionSelected: onRegionSelected ?? (_) {},
                    ),
                  );
                },
                child: const Text('권역 ⌵'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openRegionMenuButton')));
  await tester.pumpAndSettle();
}

/// 패널이 좌측 벽에 붙고 화면 오른쪽·아래 밖으로 나가지 않는지 확인한다.
/// `Positioned`는 높이 제약을 주지 않아 세로 넘침이 예외 없이 잘리므로 직접 잰다.
void _expectPanelInsideScreen(WidgetTester tester, Size screenSize) {
  final panelRect = tester.getRect(find.byType(EasySubwayRegionMenuPanel));
  expect(panelRect.left, 0.0);
  expect(
    panelRect.right,
    lessThanOrEqualTo(screenSize.width),
    reason: '패널이 화면 오른쪽 밖으로 나간다',
  );
  expect(
    panelRect.bottom,
    lessThanOrEqualTo(screenSize.height),
    reason: '패널이 화면 아래로 넘쳐 아래쪽 권역을 누를 수 없다',
  );
}

/// `Text`는 부모 높이에 잘려도 예외를 던지지 않으므로, 권역명 문단의 실제
/// 텍스트 높이(`textSize`)를 행·문단 크기와 직접 비교해 잘림을 잡는다.
void _expectEveryRegionLabelFullyVisible(
  WidgetTester tester,
  List<EasySubwayRegionMenuItem> regions,
) {
  for (final region in regions) {
    final rowFinder = find.byKey(
      ValueKey('networkMapRegionMenuRow_${region.id}'),
    );
    expect(rowFinder, findsOneWidget);
    final labelFinder = find.descendant(
      of: rowFinder,
      matching: find.text(region.label),
    );
    final rowRect = tester.getRect(rowFinder);
    final labelRect = tester.getRect(labelFinder);
    final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
    final textHeight = paragraph.textSize.height;

    expect(
      rowRect.height,
      greaterThanOrEqualTo(48.0),
      reason: '${region.label} 행은 최소 터치 타깃 48dp를 유지해야 한다',
    );
    expect(
      rowRect.height,
      greaterThanOrEqualTo(textHeight),
      reason:
          '${region.label} 행 높이(${rowRect.height})가 권역명 텍스트 높이'
          '($textHeight)보다 작아 권역명이 잘린다',
    );
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(textHeight),
      reason: '${region.label} 문단이 자기 텍스트 높이보다 작게 잘린다',
    );
    expect(labelRect.top, greaterThanOrEqualTo(rowRect.top));
    expect(labelRect.bottom, lessThanOrEqualTo(rowRect.bottom));
  }
}

/// 권역명이 줄바꿈 없이 한 줄로 그려졌는지 글자 상자들의 줄 위치로 확인한다.
void _expectRegionLabelOnOneLine(
  WidgetTester tester,
  EasySubwayRegionMenuItem region,
) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byKey(ValueKey('networkMapRegionMenuRow_${region.id}')),
      matching: find.text(region.label),
    ),
  );
  final lineTops = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: region.label.length),
      )
      .map((box) => box.top)
      .toSet();
  expect(lineTops, hasLength(1), reason: '${region.label}이 줄바꿈됐다');
}

void _expectSelectedCheckmarkVisible(
  WidgetTester tester, {
  required double screenWidth,
}) {
  final selectedRow = find.byKey(const ValueKey('networkMapRegionMenuRow_수도권'));
  final checkmark = find.descendant(
    of: selectedRow,
    matching: find.byKey(const Key('regionSelectedCheckmark')),
  );
  expect(checkmark, findsOneWidget);
  final rowRect = tester.getRect(selectedRow);
  final checkRect = tester.getRect(checkmark);
  expect(checkRect.width, greaterThan(0));
  expect(checkRect.left, greaterThanOrEqualTo(rowRect.left));
  expect(checkRect.right, lessThanOrEqualTo(rowRect.right));
  expect(checkRect.top, greaterThanOrEqualTo(rowRect.top));
  expect(checkRect.bottom, lessThanOrEqualTo(rowRect.bottom));
  expect(checkRect.right, lessThanOrEqualTo(screenWidth));
}
