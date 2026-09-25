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
                Navigator.of(context).push<void>(
                  PageRouteBuilder<void>(
                    opaque: false,
                    barrierDismissible: true,
                    barrierLabel: '메뉴 닫기',
                    barrierColor: const Color(0x00000000),
                    transitionDuration: const Duration(milliseconds: 320),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 250,
                    ),
                    pageBuilder: (context, animation, secondaryAnimation) {
                      return NetworkMapMenuPanel(
                        onOpenSavedItems: onOpenSavedItems,
                        onOpenTrainSearch: onOpenTrainSearch,
                        onOpenServiceNotices: onOpenServiceNotices,
                        onOpenSettings: onOpenSettings,
                      );
                    },
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          final curvedAnimation = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                            reverseCurve: Curves.easeInCubic,
                          );
                          return Stack(
                            children: [
                              IgnorePointer(
                                child: FadeTransition(
                                  key: const Key('networkMapMenuBackdrop'),
                                  opacity: curvedAnimation,
                                  child: const ColoredBox(
                                    color: Color(0x66000000),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(curvedAnimation),
                                  child: RepaintBoundary(child: child),
                                ),
                              ),
                            ],
                          );
                        },
                  ),
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
  testWidgets('필수·선택 항목과 header·footer chrome을 exact 순서로 렌더한다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await _openMenu(
      tester,
      _menuHost(
        observer: observer,
        onOpenTrainSearch: () {},
        onOpenSavedItems: () {},
        onOpenSettings: () {},
        onOpenServiceNotices: () {},
      ),
    );

    final panel = find.byKey(const Key('networkMapMenuPanel'));
    expect(panel, findsOneWidget);
    expect(
      tester
          .widget<Align>(
            find.ancestor(of: panel, matching: find.byType(Align)).first,
          )
          .alignment,
      Alignment.centerRight,
    );
    expect(tester.getSize(panel).width, 256);

    // 헤더: 앱 아이콘, 앱 명, 버전 배지, 서브 카피 검증
    expect(find.byKey(const Key('networkMapMenuHeader')), findsOneWidget);
    expect(find.text('쉬운 지하철'), findsOneWidget);
    expect(find.text('v4.0.0'), findsWidgets);
    expect(find.text('모두를 위한 쉬운 지하철 길찾기'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('networkMapMenuAppIcon'))),
      const Size(44, 44),
    );
    expect(
      find.byKey(const Key('networkMapMenuHeaderDivider')),
      findsOneWidget,
    );

    // 상단바와 중복되는 역 검색 타일 및 최하단 중복 광고 배너 제거 검증
    expect(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
      findsNothing,
    );
    expect(find.byKey(const Key('networkMapMenuAdBanner')), findsNothing);

    // 쉐브론 '>' 아이콘 일괄 제거 검증 (모던 리스트 스타일)
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    // 푸터: 은은한 앱 정보/라이선스 검증
    expect(find.byKey(const Key('networkMapMenuFooter')), findsOneWidget);

    final orderedKeys = <Key>[
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
    expect(find.bySemanticsLabel('역 검색'), findsNothing);
    expect(find.bySemanticsLabel('기차 검색'), findsOneWidget);
    expect(find.bySemanticsLabel('즐겨찾기'), findsOneWidget);
    expect(find.bySemanticsLabel('설정'), findsOneWidget);
    expect(find.bySemanticsLabel('공지사항'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('null callback 항목은 divider group과 함께 렌더하지 않는다', (tester) async {
    await _openMenu(tester, _menuHost(observer: _MenuNavigatorObserver()));

    expect(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
      findsNothing,
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
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
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
        onOpenTrainSearch: () => record('train'),
        onOpenSavedItems: () => record('saved'),
        onOpenSettings: () => record('settings'),
        onOpenServiceNotices: () => record('notices'),
      ),
    );

    final actions = <(Key, String)>[
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
      final root = File('lib/app/network_map_screen.dart').readAsStringSync();
      expect(
        root,
        contains(
          "import '../features/network_map/presentation/network_map_menu_panel.dart';",
        ),
      );
      expect(root, contains('return NetworkMapMenuPanel('));
      expect(root, isNot(contains('slotKey: Key(\'networkMapMenuAdBanner\')')));
      expect(root, isNot(contains('class _NetworkMapMenuPanel')));
      expect(root, isNot(contains('class _NetworkMapMenuHeader')));
      expect(root, isNot(contains('class _NetworkMapMenuTile')));
    },
  );

  testWidgets('메뉴 열림 애니메이션은 첫 프레임부터 화면 우측 경계에서 부드럽게 진입한다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await tester.pumpWidget(_menuHost(observer: observer));
    await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
    await tester.pump(); // Route begins

    // 80ms 진입 시점: 패널이 이미 화면 우측 경계를 넘어 자연스럽게 들어오는 중이다.
    await tester.pump(const Duration(milliseconds: 80));
    final panelFinder = find.byKey(const Key('networkMapMenuPanel'));
    expect(panelFinder, findsOneWidget);
    final size = tester.getSize(panelFinder);
    expect(size.width, 256);
    final screenWidth = tester.getRect(find.byType(MaterialApp)).width;
    final leftAt80ms = tester.getTopLeft(panelFinder).dx;
    expect(leftAt80ms, lessThan(screenWidth));
    expect(leftAt80ms, greaterThan(screenWidth - 256));

    // 완료 후: 정확히 우측 끝(screenWidth - 256)에 안착한다.
    await tester.pumpAndSettle();
    final leftFinal = tester.getTopLeft(panelFinder).dx;
    expect(leftFinal, equals(screenWidth - 256));
  });

  testWidgets('메뉴 열림 애니메이션은 백드롭 페이드와 패널 슬라이드가 동일 커브로 동기화된다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await tester.pumpWidget(_menuHost(observer: observer));
    await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
    await tester.pump();

    // 80ms: 320ms의 25% 경과 시점
    await tester.pump(const Duration(milliseconds: 80));
    final fadeFinder = find.byKey(const Key('networkMapMenuBackdrop'));
    expect(fadeFinder, findsOneWidget);
    final fade = tester.widget<FadeTransition>(fadeFinder);
    // Curves.easeOutCubic(0.25) = 1 - (1 - 0.25)^3 = 1 - 0.421875 = 0.578125
    expect(fade.opacity.value, moreOrLessEquals(0.578, epsilon: 0.05));

    final slideFinder = find
        .ancestor(
          of: find.byKey(const Key('networkMapMenuPanel')),
          matching: find.byType(SlideTransition),
        )
        .first;
    final slide = tester.widget<SlideTransition>(slideFinder);
    expect(
      slide.position.value.dx,
      moreOrLessEquals(1.0 - fade.opacity.value, epsilon: 0.01),
    );

    await tester.pumpAndSettle();
    expect(fade.opacity.value, equals(1.0));
    expect(slide.position.value, equals(Offset.zero));
  });

  testWidgets('패널 외부 백드롭 영역을 탭하면 메뉴가 정상적으로 닫힌다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await tester.pumpWidget(_menuHost(observer: observer));
    await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapMenuPanel')), findsOneWidget);

    // 패널 외부 좌측 백드롭 영역 탭 (x: 50, y: 300)
    await tester.tapAt(const Offset(50, 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapMenuPanel')), findsNothing);
    expect(observer.popCount, 1);
  });

  testWidgets('패널은 물리적 구분을 위한 좌측 테두리와 그림자를 가진다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await tester.pumpWidget(_menuHost(observer: observer));
    await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
    await tester.pumpAndSettle();

    final decoratedBoxFinder = find
        .ancestor(
          of: find.byKey(const Key('networkMapMenuPanel')),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final box = tester.widget<DecoratedBox>(decoratedBoxFinder);
    final decoration = box.decoration as BoxDecoration;
    final border = decoration.border as Border?;
    expect(border?.left.color, EasySubwayAccessibleColors.line);
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('패널을 우측으로 드래그하면 인터랙티브하게 이동하고 임계값 초과 시 닫힌다', (tester) async {
    final observer = _MenuNavigatorObserver();
    await tester.pumpWidget(_menuHost(observer: observer));
    await tester.tap(find.byKey(const Key('openNetworkMapMenuForTest')));
    await tester.pumpAndSettle();

    final panelFinder = find.byKey(const Key('networkMapMenuPanel'));
    expect(panelFinder, findsOneWidget);
    final initialLeft = tester.getTopLeft(panelFinder).dx;

    // 패널 내부에서 우측으로 40px 미세 드래그 -> 패널이 40px 우측으로 따라 이동해야 함
    final gesture = await tester.startGesture(tester.getCenter(panelFinder));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final draggedLeft = tester.getTopLeft(panelFinder).dx;
    expect(draggedLeft, equals(initialLeft + 40));

    // 손을 떼면 임계값(80px) 미만이므로 원위치로 스프링 복귀
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(panelFinder).dx, equals(initialLeft));

    // 85px 이상 드래그 후 놓으면 닫힘
    final dismissGesture = await tester.startGesture(
      tester.getCenter(panelFinder),
    );
    await dismissGesture.moveBy(const Offset(85, 0));
    await dismissGesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapMenuPanel')), findsNothing);
    expect(observer.popCount, 1);
  });
}
