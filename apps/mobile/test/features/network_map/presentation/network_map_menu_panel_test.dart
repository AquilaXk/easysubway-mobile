import 'dart:async';
import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MenuNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }
}

Widget _menuHost({
  required _MenuNavigatorObserver observer,
  required VoidCallback onOpenStationSearch,
  VoidCallback? onOpenSavedItems,
  VoidCallback? onOpenTrainSearch,
  VoidCallback? onOpenServiceNotices,
  VoidCallback? onOpenSettings,
}) {
  return MaterialApp(
    navigatorObservers: [observer],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('openNetworkMapMenuForTest'),
            onPressed: () {
              unawaited(
                showGeneralDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: '메뉴 닫기',
                  pageBuilder: (context, animation, secondaryAnimation) {
                    return NetworkMapMenuPanel(
                      bottomBanner: const SizedBox(
                        key: Key('networkMapMenuAdBanner'),
                      ),
                      onOpenStationSearch: onOpenStationSearch,
                      onOpenSavedItems: onOpenSavedItems,
                      onOpenTrainSearch: onOpenTrainSearch,
                      onOpenServiceNotices: onOpenServiceNotices,
                      onOpenSettings: onOpenSettings,
                    );
                  },
                ),
              );
            },
            child: const Text('메뉴 열기'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('필수·선택 항목과 header·ad chrome을 exact 순서로 렌더한다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await _openMenu(
      tester,
      _menuHost(
        observer: observer,
        onOpenStationSearch: () {},
        onOpenTrainSearch: () {},
        onOpenSavedItems: () {},
        onOpenSettings: () {},
        onOpenServiceNotices: () {},
      ),
    );

    final panel = find.byKey(const Key('networkMapMenuPanel'));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, 256);
    expect(
      tester.getSize(find.byKey(const Key('networkMapMenuHeader'))).height,
      easySubwayTopBarContentHeight,
    );
    expect(find.text('쉬운 지하철'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('networkMapMenuAppIcon'))),
      const Size(44, 44),
    );
    expect(
      find.byKey(const Key('networkMapMenuHeaderDivider')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('networkMapMenuAdBanner')), findsOneWidget);

    final orderedKeys = <Key>[
      const Key('networkMapMenuStationSearchButton'),
      const Key('networkMapMenuTrainSearchButton'),
      const Key('networkMapMenuSavedButton'),
      const Key('networkMapMenuSettingsButton'),
      const Key('networkMapMenuServiceNoticesButton'),
    ];
    final topOffsets = [
      for (final key in orderedKeys) tester.getTopLeft(find.byKey(key)).dy,
    ];
    expect(topOffsets, orderedEquals([...topOffsets]..sort()));

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('역 검색'), findsOneWidget);
    expect(find.bySemanticsLabel('기차 검색'), findsOneWidget);
    expect(find.bySemanticsLabel('즐겨찾기'), findsOneWidget);
    expect(find.bySemanticsLabel('설정'), findsOneWidget);
    expect(find.bySemanticsLabel('공지사항'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('null callback 항목은 divider group과 함께 렌더하지 않는다', (tester) async {
    await _openMenu(
      tester,
      _menuHost(observer: _MenuNavigatorObserver(), onOpenStationSearch: () {}),
    );

    expect(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapMenuTrainSearchButton')),
      findsNothing,
    );
    expect(find.byKey(const Key('networkMapMenuSavedButton')), findsNothing);
    expect(find.byKey(const Key('networkMapMenuSettingsButton')), findsNothing);
    expect(
      find.byKey(const Key('networkMapMenuServiceNoticesButton')),
      findsNothing,
    );
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('모든 visible action은 dialog를 pop한 뒤 exact callback을 실행한다', (
    tester,
  ) async {
    final observer = _MenuNavigatorObserver();
    final calls = <String>[];
    final popCountsSeenByCallback = <int>[];
    void record(String action) {
      calls.add(action);
      popCountsSeenByCallback.add(observer.popCount);
    }

    await tester.pumpWidget(
      _menuHost(
        observer: observer,
        onOpenStationSearch: () => record('station'),
        onOpenTrainSearch: () => record('train'),
        onOpenSavedItems: () => record('saved'),
        onOpenSettings: () => record('settings'),
        onOpenServiceNotices: () => record('notices'),
      ),
    );

    final actions = <(Key, String)>[
      (const Key('networkMapMenuStationSearchButton'), 'station'),
      (const Key('networkMapMenuTrainSearchButton'), 'train'),
      (const Key('networkMapMenuSavedButton'), 'saved'),
      (const Key('networkMapMenuSettingsButton'), 'settings'),
      (const Key('networkMapMenuServiceNoticesButton'), 'notices'),
    ];
    for (var index = 0; index < actions.length; index++) {
      await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(actions[index].$1));
      expect(
        calls,
        orderedEquals([for (var i = 0; i <= index; i++) actions[i].$2]),
      );
      expect(popCountsSeenByCallback[index], index + 1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('networkMapMenuPanel')), findsNothing);
    }
  });

  test(
    'root consumes the direct owner without a private compatibility surface',
    () {
      final root = File('lib/network_map.dart').readAsStringSync();
      expect(
        root,
        contains(
          "import 'features/network_map/presentation/network_map_menu_panel.dart';",
        ),
      );
      expect(root, contains('return NetworkMapMenuPanel('));
      expect(
        root,
        contains(
          "bottomBanner: const AdBannerSlot(\n"
          "            slotKey: Key('networkMapMenuAdBanner'),",
        ),
      );
      expect(root, isNot(contains('class _NetworkMapMenuPanel')));
      expect(root, isNot(contains('class _NetworkMapMenuHeader')));
      expect(root, isNot(contains('class _NetworkMapMenuTile')));
    },
  );
}
