import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/ad_slot.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('lookup toast는 exact surface와 2-line message를 렌더한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const NetworkMapLookupToast(message: '가까운 역을 찾지 못했어요')),
    );

    final surface = find.byKey(const Key('networkMapNearbyLookupMessage'));
    expect(surface, findsOneWidget);
    final alignment = tester.widget<Align>(
      find.ancestor(of: surface, matching: find.byType(Align)),
    );
    expect(alignment.alignment, Alignment.center);
    final material = tester.widget<Material>(surface);
    expect(material.color, const Color(0xE62F3437));
    expect(material.elevation, 0);
    expect(material.borderRadius, BorderRadius.circular(8));
    final padding = tester.widget<Padding>(
      find.descendant(of: surface, matching: find.byType(Padding)),
    );
    expect(
      padding.padding,
      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    );

    final message = tester.widget<Text>(find.text('가까운 역을 찾지 못했어요'));
    expect(message.maxLines, 2);
    expect(message.overflow, TextOverflow.ellipsis);
    expect(message.textAlign, TextAlign.center);
    expect(
      message.style?.color,
      EasySubwayAccessibleColors.interactionOnPrimary,
    );
    expect(message.style?.fontSize, 15);
    expect(message.style?.fontWeight, FontWeight.w800);
    expect(message.style?.height, 1.2);
  });

  testWidgets(
    'current-location button은 exact circle·Semantics·callback을 보존한다',
    (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        _host(NetworkMapCurrentLocationButton(onTap: () => tapCount += 1)),
      );

      final button = find.byKey(const Key('nearbyStationButton'));
      expect(button, findsOneWidget);
      expect(tester.getSize(button), const Size(56, 56));
      final material = tester.widget<Material>(button);
      expect(material.color, EasySubwayAccessibleColors.surfaceDefault);
      expect(material.elevation, 0);
      expect(
        material.shape,
        const CircleBorder(
          side: BorderSide(
            color: EasySubwayAccessibleColors.borderSubtle,
            width: 1,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.my_location));
      expect(icon.size, 27);
      expect(icon.color, EasySubwayAccessibleColors.contentSecondary);

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('현재 위치에서 가장 가까운 역 찾기'), findsOneWidget);
      await tester.tap(button);
      expect(tapCount, 1);
      semantics.dispose();
    },
  );

  testWidgets('search-entry button은 visual·Semantics·callback을 보존한다', (
    tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 200,
          child: NetworkMapSearchEntryButton(onTap: () => tapCount += 1),
        ),
      ),
    );

    final button = find.byKey(const Key('stationSearchButton'));
    final surface = find.byKey(const Key('heroStationSearchButton'));
    expect(button, findsOneWidget);
    expect(surface, findsOneWidget);
    expect(tester.getSize(button).height, EasySubwayTouchTarget.general);
    expect(tester.getSize(surface).height, easySubwaySearchFieldVisualHeight);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('지하철역 검색'), findsOneWidget);

    final container = tester.widget<Container>(surface);
    expect(
      container.padding,
      const EdgeInsets.symmetric(
        horizontal: easySubwaySearchFieldHorizontalPadding,
      ),
    );
    expect(
      container.decoration,
      BoxDecoration(
        color: EasySubwayAccessibleColors.searchFieldSurface,
        border: Border.all(
          color: easySubwaySearchFieldBorderColor,
          width: easySubwaySearchFieldBorderWidth,
        ),
        borderRadius: easySubwaySearchFieldRadius,
      ),
    );

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('지하철역 검색'), findsOneWidget);
    await tester.tap(button);
    expect(tapCount, 1);
    semantics.dispose();
  });

  testWidgets('search-entry button은 72px 미만에서 visual만 compact하다', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 71,
          child: NetworkMapSearchEntryButton(onTap: _noop),
        ),
      ),
    );

    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.text('지하철역 검색'), findsNothing);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('지하철역 검색'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('top-bar shell은 idle 지역 chrome과 draft 전환을 보존한다', (tester) async {
    final draftChanges = ValueNotifier<int>(0);
    var draft = const RouteDraft.empty();
    var menuTapCount = 0;
    var searchTapCount = 0;
    String? selectedRegion;

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 520,
          child: NetworkMapTopBar(
            regions: const [
              NetworkMapRegion(name: '수도권'),
              NetworkMapRegion(name: '부산권'),
            ],
            selectedRegion: '부산권',
            notificationAction: const SizedBox(
              key: Key('networkMapNotificationAction'),
            ),
            onMenuTap: () => menuTapCount += 1,
            onSearchTap: () => searchTapCount += 1,
            onRegionSelected: (region) => selectedRegion = region,
            routeDraftListenable: draftChanges,
            routeDraft: () => draft,
            isWaypointRowVisible: () => false,
            onClearDraft: _noop,
            onOpenWaypointSlot: _noop,
            onClearOrigin: _noop,
            onClearDestination: _noop,
            onClearWaypoint: _noop,
            onReorderDraft: (_, _) {},
            roleColorForSlot: (_) => Colors.black,
            lineBadgeBuilder: (_, size) => SizedBox.square(
              key: const Key('networkMapTopBarLineBadge'),
              dimension: size,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('networkMapTopBar')), findsOneWidget);
    expect(find.text('부산'), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNotificationAction')),
      findsOneWidget,
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('지역: 부산, 지역 변경'), findsOneWidget);
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.tap(find.byKey(const Key('networkMapRegionDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('networkMapRegionMenuRow_수도권')));
    await tester.pumpAndSettle();
    expect(menuTapCount, 1);
    expect(searchTapCount, 1);
    expect(selectedRegion, '수도권');

    draft = const RouteDraft(
      origin: RouteDraftStation(
        id: 'station-201',
        nameKo: '시청',
        lineId: 'line-2',
        lineName: '2호선',
        lineColor: '#00A84D',
        stationCode: '201',
      ),
      destination: null,
      lastModifiedAt: null,
    );
    draftChanges.value += 1;
    await tester.pump();

    expect(
      find.byKey(const Key('networkMapRouteDraftOverlay')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('networkMapTopBarLineBadge')), findsWidgets);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);
    semantics.dispose();
    draftChanges.dispose();
  });

  testWidgets('top-bar route draft는 one-sided chrome·callback·잠긴 지역을 보존한다', (
    tester,
  ) async {
    var backCount = 0;
    var addCount = 0;
    var clearOriginCount = 0;
    var pickDestinationCount = 0;
    final badgeSizes = <double>[];

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 520,
          child: NetworkMapTopBarRouteDraft(
            draft: const RouteDraft(
              origin: RouteDraftStation(
                id: 'origin',
                nameKo: '서울',
                lineId: 'line-1',
                lineName: '1호선',
                lineColor: '#0052A4',
                stationCode: '133',
              ),
              destination: null,
              lastModifiedAt: null,
            ),
            showWaypointRow: false,
            regionLabel: '수도권',
            onClearDraft: () => backCount += 1,
            onOpenWaypointSlot: () => addCount += 1,
            onClearOrigin: () => clearOriginCount += 1,
            onClearDestination: _noop,
            onClearWaypoint: _noop,
            onReorderDraft: (_, _) {},
            onPickDestination: () => pickDestinationCount += 1,
            roleColorForSlot: (slot) => switch (slot) {
              RouteDraftSlot.origin => Colors.blue,
              RouteDraftSlot.waypoint => Colors.orange,
              RouteDraftSlot.destination => Colors.red,
            },
            lineBadgeBuilder: (station, size) {
              badgeSizes.add(size);
              return SizedBox(
                key: Key('routeDraftBadge${size.toInt()}'),
                width: size,
                height: size,
              );
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('networkMapRouteDraftOriginRow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftDestinationRow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftWaypointRow')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftAddWaypoint')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('routeDraftBadge26')), findsOneWidget);
    expect(badgeSizes, containsAll(<double>[26, 30]));
    expect(tester.widget<Text>(find.text('출발역')).style?.color, Colors.blue);

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('지역: 수도권, 변경할 수 없음'), findsOneWidget);
    await tester.tap(find.byKey(const Key('networkMapRouteDraftBackButton')));
    await tester.tap(find.byKey(const Key('networkMapRouteDraftAddWaypoint')));
    await tester.tap(find.byKey(const Key('networkMapRouteDraftClearOrigin')));
    await tester.tap(
      find.byKey(const Key('networkMapRouteDraftPickDestination')),
    );
    expect(backCount, 1);
    expect(addCount, 1);
    expect(clearOriginCount, 1);
    expect(pickDestinationCount, 1);
    semantics.dispose();
  });

  testWidgets('top-bar route draft는 waypoint row와 reorder Semantics를 보존한다', (
    tester,
  ) async {
    var clearWaypointCount = 0;
    var pickWaypointCount = 0;
    final reorderPairs = <(RouteDraftSlot, RouteDraftSlot)>[];

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 520,
          child: NetworkMapTopBarRouteDraft(
            draft: const RouteDraft(
              origin: RouteDraftStation(id: 'origin', nameKo: '서울'),
              waypoint: RouteDraftStation(id: 'waypoint', nameKo: '시청'),
              destination: null,
              lastModifiedAt: null,
            ),
            showWaypointRow: true,
            regionLabel: '수도권',
            onClearDraft: _noop,
            onOpenWaypointSlot: _noop,
            onClearOrigin: _noop,
            onClearDestination: _noop,
            onClearWaypoint: () => clearWaypointCount += 1,
            onReorderDraft: (from, to) => reorderPairs.add((from, to)),
            onPickWaypoint: () => pickWaypointCount += 1,
            roleColorForSlot: (_) => Colors.black,
            lineBadgeBuilder: (_, size) => SizedBox.square(dimension: size),
          ),
        ),
      ),
    );

    final originRow = find.byKey(const Key('networkMapRouteDraftOriginRow'));
    expect(originRow, findsOneWidget);
    expect(
      find.byKey(const Key('networkMapRouteDraftWaypointRow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftAddWaypoint')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('networkMapRouteDraftPickWaypoint')));
    await tester.tap(
      find.byKey(const Key('networkMapRouteDraftClearWaypoint')),
    );
    expect(pickWaypointCount, 1);
    expect(clearWaypointCount, 1);

    final reorderSemantics = tester
        .widgetList<Semantics>(
          find.descendant(of: originRow, matching: find.byType(Semantics)),
        )
        .firstWhere(
          (widget) =>
              widget.properties.customSemanticsActions?.keys.any(
                (action) => action.label == '도착역으로 이동',
              ) ??
              false,
        );
    reorderSemantics.properties.customSemanticsActions!.entries
        .firstWhere((entry) => entry.key.label == '도착역으로 이동')
        .value();
    expect(reorderPairs, <(RouteDraftSlot, RouteDraftSlot)>[
      (RouteDraftSlot.origin, RouteDraftSlot.destination),
    ]);
  });

  testWidgets('bottom-ad banner는 공용 슬롯의 안전영역·identity를 보존한다', (tester) async {
    await tester.pumpWidget(
      _host(
        const NetworkMapBottomAdBanner(
          slot: AdBannerSlot(slotKey: Key('networkMapBottomAdBanner')),
        ),
      ),
    );

    final safeArea = tester.widget<SafeArea>(find.byType(SafeArea));
    expect(safeArea.top, isFalse);

    final slot = tester.widget<AdBannerSlot>(find.byType(AdBannerSlot));
    expect(slot.slotKey, const Key('networkMapBottomAdBanner'));
    expect(slot.height, kAdBannerSlotStandardHeight);
    expect(slot.showTopDivider, isTrue);
    expect(slot.child, isNull);
  });

  test('root는 direct owner만 소비하고 private compatibility surface가 없다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    final owner = File(
      'lib/features/network_map/presentation/network_map_chrome_controls.dart',
    ).readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_chrome_controls.dart';",
      ),
    );
    expect(root, contains('NetworkMapLookupToast('));
    expect(root, contains('NetworkMapCurrentLocationButton('));
    expect(root, contains('NetworkMapBottomAdBanner('));
    expect(root, contains('NetworkMapTopBar('));
    expect(root, contains('slot: AdBannerSlot('));
    expect(root, isNot(contains('class _NetworkMapLookupToast')));
    expect(root, isNot(contains('class _NetworkMapCurrentLocationButton')));
    expect(root, isNot(contains('class _NetworkMapSearchField')));
    expect(root, isNot(contains('class _NetworkMapBottomAdBanner')));
    expect(root, isNot(contains('enum _RouteDraftFieldKind')));
    expect(root, isNot(contains('class _NetworkMapTopBarRouteDraft')));
    expect(root, isNot(contains('class _NetworkMapRouteDraftField')));
    expect(root, isNot(contains('class _NetworkMapTopBar')));
    expect(root, isNot(contains('NetworkMapSearchEntryButton(')));
    expect(root, isNot(contains('NetworkMapTopBarRouteDraft(')));
    expect(owner, contains('class NetworkMapTopBar'));
    expect(owner, contains('NetworkMapSearchEntryButton('));
    expect(owner, contains('class NetworkMapTopBarRouteDraft'));
    expect(
      owner,
      contains("import '../../route_draft/domain/route_draft.dart';"),
    );
    expect(owner, isNot(contains('station_line_badges.dart')));
    expect(owner, isNot(contains('route_draft_controller.dart')));
    expect(owner, isNot(contains("import '../../../design_tokens.dart';")));
  });
}

void _noop() {}
