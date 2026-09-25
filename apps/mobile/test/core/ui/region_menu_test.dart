import 'dart:async';

import 'package:easysubway_mobile/core/ui/region_menu.dart';
import 'package:flutter/material.dart';
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
}
