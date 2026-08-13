import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_nearby_panel_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(NetworkMapNearbyPanelShell shell) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 420, height: 720, child: shell)),
);

void main() {
  testWidgets('collapsed shell은 border·tabs·toggle·close·body를 보존한다', (
    tester,
  ) async {
    var toggleCount = 0;
    var closeCount = 0;
    await tester.pumpWidget(
      _host(
        NetworkMapNearbyPanelShell(
          expanded: false,
          lineTabs: const [
            SizedBox(key: Key('lineTab1'), width: 48, height: 48),
          ],
          isRealtime: true,
          dataSourceToggleEnabled: true,
          onDataSourceToggle: () => toggleCount += 1,
          onClose: () => closeCount += 1,
          body: const SizedBox(key: Key('nearbyBody'), height: 132),
        ),
      ),
    );

    final panel = find.byKey(const Key('networkMapNearbyStationPanel'));
    expect(panel, findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanelExpanded')),
      findsNothing,
    );
    final safeArea = tester.widget<SafeArea>(
      find.descendant(of: panel, matching: find.byType(SafeArea)).first,
    );
    expect(safeArea.top, isFalse);
    expect(safeArea.bottom, isTrue);
    final decoration = tester
        .widget<DecoratedBox>(
          find.descendant(of: panel, matching: find.byType(DecoratedBox)).first,
        )
        .decoration as BoxDecoration;
    expect(
      decoration.border,
      const Border(
        top: BorderSide(color: EasySubwayAccessibleColors.borderSubtle),
      ),
    );
    expect(find.byKey(const Key('lineTab1')), findsOneWidget);
    expect(find.byKey(const Key('nearbyBody')), findsOneWidget);
    expect(find.bySemanticsLabel('실시간 선택됨'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('시간표로 전환'));
    await tester.tap(
      find.byKey(const Key('networkMapNearbyPanelCloseButton')),
    );
    expect(toggleCount, 1);
    expect(closeCount, 1);
  });

  testWidgets('expanded shell은 top safe-area와 detail placement를 보존한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        NetworkMapNearbyPanelShell(
          expanded: true,
          lineTabs: const [
            SizedBox(key: Key('lineTab1'), width: 48, height: 48),
            SizedBox(key: Key('lineTab2'), width: 48, height: 48),
          ],
          isRealtime: false,
          dataSourceToggleEnabled: false,
          onDataSourceToggle: () {},
          onClose: () {},
          body: const SizedBox(key: Key('nearbyBody'), height: 132),
          expandedDetail: const SizedBox(key: Key('nearbyDetail')),
        ),
      ),
    );

    final expanded = find.byKey(
      const Key('networkMapNearbyStationPanelExpanded'),
    );
    expect(expanded, findsOneWidget);
    final safeArea = tester.widget<SafeArea>(
      find.descendant(of: expanded, matching: find.byType(SafeArea)).first,
    );
    expect(safeArea.top, isTrue);
    expect(safeArea.bottom, isTrue);
    final decoration = tester
        .widget<DecoratedBox>(
          find
              .descendant(of: expanded, matching: find.byType(DecoratedBox))
              .first,
        )
        .decoration as BoxDecoration;
    expect(decoration.border, isNull);
    expect(find.byKey(const Key('lineTab1')), findsOneWidget);
    expect(find.byKey(const Key('lineTab2')), findsOneWidget);
    expect(find.byKey(const Key('nearbyBody')), findsOneWidget);
    expect(find.byKey(const Key('nearbyDetail')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('nearbyDetail')),
        matching: find.byType(Expanded),
      ),
      findsOneWidget,
    );
  });

  test('root는 public nearby panel shell을 사용하고 private shell이 없다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_nearby_panel_shell.dart';",
      ),
    );
    expect(root, contains('NetworkMapNearbyPanelShell('));
    expect(root, isNot(contains('class _NetworkMapNearbyStationPanel')));
  });
}
