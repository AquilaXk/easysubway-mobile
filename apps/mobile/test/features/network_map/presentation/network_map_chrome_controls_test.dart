import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/features/ads/ad_slot.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(message.style?.fontWeight, EasySubwayFontWeight.regular);
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
    final topBarMaterial = tester.widget<Material>(
      find.byKey(const Key('networkMapTopBar')),
    );
    expect(topBarMaterial.color, EasySubwayAccessibleColors.primary);
    final regionText = tester.widget<Text>(find.text('부산'));
    expect(
      regionText.style?.color,
      EasySubwayAccessibleColors.interactionOnPrimary,
    );
    final dropdownIcon = tester.widget<Icon>(
      find.byIcon(Icons.keyboard_arrow_down_rounded),
    );
    expect(dropdownIcon.color, EasySubwayAccessibleColors.interactionOnPrimary);
    final menuIcon = tester.widget<Icon>(find.byIcon(Icons.menu));
    expect(menuIcon.color, EasySubwayAccessibleColors.interactionOnPrimary);
    expect(find.text('부산'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('networkMapRegionDropdown'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('stationSearchButton'))).dx,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('stationSearchButton'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('networkMapMenuButton'))).dx,
      ),
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

  testWidgets('top-bar searchMode는 뒤로가기 버튼과 검색 입력필드를 렌더한다', (tester) async {
    var searchBackCount = 0;
    var submittedQuery = '';
    var clearCount = 0;
    final controller = TextEditingController(text: '강남');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 520,
          child: NetworkMapTopBar(
            regions: const [NetworkMapRegion(name: '수도권')],
            selectedRegion: '수도권',
            searchMode: true,
            searchQueryController: controller,
            searchFocusNode: focusNode,
            onSearchBack: () => searchBackCount += 1,
            onSearchSubmitted: (q) => submittedQuery = q,
            onSearchClear: () => clearCount += 1,
            onMenuTap: _noop,
            onSearchTap: _noop,
            onRegionSelected: (_) {},
            routeDraftListenable: ValueNotifier(0),
            routeDraft: () => const RouteDraft.empty(),
            isWaypointRowVisible: () => false,
            onClearDraft: _noop,
            onOpenWaypointSlot: _noop,
            onClearOrigin: _noop,
            onClearDestination: _noop,
            onClearWaypoint: _noop,
            onReorderDraft: (_, _) {},
            roleColorForSlot: (_) => Colors.black,
            lineBadgeBuilder: (_, size) => SizedBox.square(dimension: size),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('networkMapSearchBackButton')), findsOneWidget);
    final backIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('networkMapSearchBackButton')),
        matching: find.byIcon(Icons.arrow_back_ios_new),
      ),
    );
    expect(backIcon.color, EasySubwayAccessibleColors.text);
    expect(find.byType(EasySubwaySearchField), findsOneWidget);
    expect(
      tester.widget<Material>(find.byKey(const Key('networkMapTopBar'))).color,
      EasySubwayAccessibleColors.surface,
    );

    await tester.tap(find.byKey(const Key('networkMapSearchBackButton')));
    expect(searchBackCount, 1);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(submittedQuery, '강남');

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('top-bar는 SystemUiOverlayStyle.light 상태바를 지정한다', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 520,
          child: NetworkMapTopBar(
            regions: const [NetworkMapRegion(name: '수도권')],
            selectedRegion: '수도권',
            onMenuTap: _noop,
            onSearchTap: _noop,
            onRegionSelected: (_) {},
            routeDraftListenable: ValueNotifier(0),
            routeDraft: () => const RouteDraft.empty(),
            isWaypointRowVisible: () => false,
            onClearDraft: _noop,
            onOpenWaypointSlot: _noop,
            onClearOrigin: _noop,
            onClearDestination: _noop,
            onClearWaypoint: _noop,
            onReorderDraft: (_, _) {},
            roleColorForSlot: (_) => Colors.black,
            lineBadgeBuilder: (_, size) => SizedBox.square(dimension: size),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is AnnotatedRegion<SystemUiOverlayStyle> &&
            w.value == SystemUiOverlayStyle.light,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'top-bar searchMode는 흰 상단바에 맞춰 SystemUiOverlayStyle.dark 상태바를 지정한다',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 520,
            child: NetworkMapTopBar(
              regions: const [NetworkMapRegion(name: '수도권')],
              selectedRegion: '수도권',
              searchMode: true,
              searchQueryController: TextEditingController(),
              searchFocusNode: FocusNode(),
              onSearchBack: _noop,
              onSearchSubmitted: (_) {},
              onSearchClear: _noop,
              onMenuTap: _noop,
              onSearchTap: _noop,
              onRegionSelected: (_) {},
              routeDraftListenable: ValueNotifier(0),
              routeDraft: () => const RouteDraft.empty(),
              isWaypointRowVisible: () => false,
              onClearDraft: _noop,
              onOpenWaypointSlot: _noop,
              onClearOrigin: _noop,
              onClearDestination: _noop,
              onClearWaypoint: _noop,
              onReorderDraft: (_, _) {},
              roleColorForSlot: (_) => Colors.black,
              lineBadgeBuilder: (_, size) => SizedBox.square(dimension: size),
            ),
          ),
        ),
      );

      final overlayStyles = tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byWidgetPredicate(
              (w) => w is AnnotatedRegion<SystemUiOverlayStyle>,
            ),
          )
          .map((region) => region.value);
      expect(overlayStyles, contains(SystemUiOverlayStyle.dark));
      expect(overlayStyles, isNot(contains(SystemUiOverlayStyle.light)));
    },
  );

  testWidgets('chrome 본문은 idle에서 상단바 아래 10dp 겹쳐 시작하고 검색 모드에서는 옅은 띠 아래서 시작한다', (
    tester,
  ) async {
    const statusBarInset = 24.0;

    Widget shell({required bool searchMode}) {
      return MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: statusBarInset),
        ),
        child: SizedBox(
          width: 400,
          height: 560,
          child: NetworkMapChrome(
            topBar: const SizedBox(height: easySubwayTopBarContentHeight),
            disruptionBanner: null,
            searchMode: searchMode,
            searchBody: const SizedBox(key: Key('mapTopSearchBody')),
            nearbyPanelVisible: false,
            nearbyPanelExpanded: false,
            nearbyPanel: const SizedBox(),
            nearbyLookupMessage: null,
            onCurrentLocationTap: _noop,
            child: const SizedBox(key: Key('mapTopMapBody')),
          ),
        ),
      );
    }

    double topOf(Key key) =>
        tester.getTopLeft(find.byKey(key)).dy -
        tester.getTopLeft(find.byType(NetworkMapChrome)).dy;

    await tester.pumpWidget(_host(shell(searchMode: false)));
    expect(topOf(const Key('mapTopMapBody')), statusBarInset + 60 - 10);

    await tester.pumpWidget(_host(shell(searchMode: true)));
    expect(
      topOf(const Key('mapTopSearchBody')),
      statusBarInset + easySubwayTopBarContentHeight + 8,
    );
  });

  testWidgets('outer chrome shell은 map/search와 overlay 가시성을 보존한다', (
    tester,
  ) async {
    var locationTapCount = 0;

    Widget shell({bool searchMode = false, bool nearbyExpanded = false}) {
      return MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
        child: SizedBox(
          width: 400,
          height: 560,
          child: NetworkMapChrome(
            topBar: const SizedBox(
              key: Key('networkMapOuterChromeTopBar'),
              height: easySubwayTopBarContentHeight,
            ),
            disruptionBanner: const SizedBox(
              key: Key('networkMapOuterChromeDisruption'),
            ),
            searchMode: searchMode,
            searchBody: const SizedBox(
              key: Key('networkMapOuterChromeSearchBody'),
            ),
            nearbyPanelVisible: true,
            nearbyPanelExpanded: nearbyExpanded,
            nearbyPanel: const SizedBox(
              key: Key('networkMapOuterChromeNearbyPanel'),
            ),
            nearbyLookupMessage: '가까운 역을 찾았어요',
            onCurrentLocationTap: () => locationTapCount += 1,
            child: const SizedBox(key: Key('networkMapOuterChromeMapBody')),
          ),
        ),
      );
    }

    await tester.pumpWidget(_host(shell()));

    expect(
      find.byKey(const Key('networkMapOuterChromeMapBody')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapOuterChromeSearchBody')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('networkMapOuterChromeDisruption')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapOuterChromeNearbyPanel')),
      findsOneWidget,
    );
    expect(find.text('가까운 역을 찾았어요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    expect(locationTapCount, 1);

    await tester.pumpWidget(_host(shell(searchMode: true)));

    expect(find.byKey(const Key('networkMapOuterChromeMapBody')), findsNothing);
    expect(
      find.byKey(const Key('networkMapOuterChromeSearchBody')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapOuterChromeDisruption')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('networkMapOuterChromeNearbyPanel')),
      findsNothing,
    );
    expect(find.text('가까운 역을 찾았어요'), findsNothing);
    expect(find.byKey(const Key('nearbyStationButton')), findsNothing);

    await tester.pumpWidget(_host(shell(nearbyExpanded: true)));

    expect(
      find.byKey(const Key('networkMapOuterChromeNearbyPanel')),
      findsOneWidget,
    );
    expect(find.text('가까운 역을 찾았어요'), findsNothing);
    expect(find.byKey(const Key('nearbyStationButton')), findsNothing);
  });

  testWidgets('disruption banner는 실제 상단바의 줄 수와 상관없이 그 바로 아래에 놓인다', (
    tester,
  ) async {
    const statusBarInset = 24.0;
    const originOnly = RouteDraft(
      origin: RouteDraftStation(id: 'origin', nameKo: '서울'),
      destination: null,
      lastModifiedAt: null,
    );
    // 검색 줄은 상단바 기본 높이이고, 경로 입력 줄이 하나 늘 때마다 입력 줄 높이만큼 커진다.
    double heightOfRows(int rows) =>
        statusBarInset +
        easySubwayTopBarContentHeight +
        (rows - 1) * EasySubwayTouchTarget.iconOnly;
    final cases = <({String name, int rows, RouteDraft draft, bool waypoint})>[
      (
        name: '검색 1줄',
        rows: 1,
        draft: const RouteDraft.empty(),
        waypoint: false,
      ),
      (name: '출발·도착 2줄', rows: 2, draft: originOnly, waypoint: false),
      (name: '출발·경유·도착 3줄', rows: 3, draft: originOnly, waypoint: true),
    ];

    for (final c in cases) {
      await tester.pumpWidget(
        _host(
          MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: statusBarInset),
            ),
            child: SizedBox(
              width: 400,
              height: 560,
              child: NetworkMapChrome(
                topBar: NetworkMapTopBar(
                  regions: const [NetworkMapRegion(name: '수도권')],
                  selectedRegion: '수도권',
                  onMenuTap: _noop,
                  onSearchTap: _noop,
                  onRegionSelected: (_) {},
                  routeDraftListenable: ValueNotifier(0),
                  routeDraft: () => c.draft,
                  isWaypointRowVisible: () => c.waypoint,
                  onClearDraft: _noop,
                  onOpenWaypointSlot: _noop,
                  onClearOrigin: _noop,
                  onClearDestination: _noop,
                  onClearWaypoint: _noop,
                  onReorderDraft: (_, _) {},
                  roleColorForSlot: (_) => Colors.black,
                  lineBadgeBuilder: (_, size) =>
                      SizedBox.square(dimension: size),
                ),
                disruptionBanner: const SizedBox(
                  key: Key('chromeSizedBanner'),
                  height: 48,
                ),
                searchMode: false,
                searchBody: null,
                nearbyPanelVisible: false,
                nearbyPanelExpanded: false,
                nearbyPanel: const SizedBox(),
                nearbyLookupMessage: null,
                onCurrentLocationTap: _noop,
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );

      final topBar = tester.getRect(find.byKey(const Key('networkMapTopBar')));
      final banner = tester.getRect(find.byKey(const Key('chromeSizedBanner')));
      expect(topBar.height, heightOfRows(c.rows), reason: c.name);
      expect(banner.top, topBar.bottom, reason: c.name);
    }
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

    final draftBackIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftBackButton')),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    expect(
      draftBackIcon.color,
      EasySubwayAccessibleColors.interactionOnPrimary,
    );
    final draftAddIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftAddWaypoint')),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(draftAddIcon.color, EasySubwayAccessibleColors.interactionOnPrimary);
    final draftRegionText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftRegionLabel')),
        matching: find.text('수도권'),
      ),
    );
    expect(
      draftRegionText.style?.color,
      EasySubwayAccessibleColors.interactionOnPrimary,
    );

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

  // 입력 칸 높이는 48dp(시각 박스 40dp)로 정해져 있어 칸 안 노선 마크는 1.3배에서
  // 멈춘다. 26dp 기본 마크의 한 변은 26, 33.8, 33.8, 33.8이다. 폭이 좁으면 이름을
  // 위해 마크를 감추므로(network_map_route_draft_pill_mark_test) 마크가 모두 들어가는
  // 600dp 폭에서 상한만 본다.
  for (final (scale, side) in [
    (1.0, 26.0),
    (1.3, 33.8),
    (1.5, 33.8),
    (2.0, 33.8),
  ]) {
    testWidgets(
      'top-bar route draft 입력 칸 마크는 글자 $scale배에서 한 변 $side로 칸 안에 든다',
      (tester) async {
        tester.view.physicalSize = const Size(600, 780) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: NetworkMapTopBarRouteDraft(
                draft: const RouteDraft(
                  origin: RouteDraftStation(
                    id: 'origin',
                    nameKo: '서울',
                    lineId: 'seoul-2',
                    lineName: '수도권 2호선',
                    lineColor: '#00A84D',
                    stationCode: '222',
                  ),
                  destination: RouteDraftStation(
                    id: 'destination',
                    nameKo: '강남',
                    lineId: 'seoul-4',
                    lineName: '수도권 4호선',
                    lineColor: '#00A5DE',
                    stationCode: '434',
                  ),
                  lastModifiedAt: null,
                ),
                showWaypointRow: false,
                regionLabel: '수도권',
                onClearDraft: _noop,
                onOpenWaypointSlot: _noop,
                onClearOrigin: _noop,
                onClearDestination: _noop,
                onClearWaypoint: _noop,
                onReorderDraft: (_, _) {},
                roleColorForSlot: (_) => Colors.black,
                lineBadgeBuilder: routeDraftStationLineBadge,
              ),
            ),
          ),
        );

        for (final (rowKey, lineId) in [
          ('networkMapRouteDraftOriginRow', 'seoul-2'),
          ('networkMapRouteDraftDestinationRow', 'seoul-4'),
        ]) {
          final row = tester.getRect(find.byKey(Key(rowKey)));
          final mark = tester.getRect(
            find.descendant(
              of: find.byKey(Key(rowKey)),
              matching: find.byKey(Key('stationLineBadge-$lineId')),
            ),
          );
          expect(mark.width, closeTo(side, 0.001), reason: rowKey);
          expect(mark.height, closeTo(side, 0.001), reason: rowKey);
          expect(row.height, 48);
          expect(mark.top, greaterThanOrEqualTo(row.top));
          expect(mark.bottom, lessThanOrEqualTo(row.bottom));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    final owner = File(
      'lib/features/network_map/presentation/network_map_chrome_controls.dart',
    ).readAsStringSync();
    expect(
      root,
      contains(
        "import '../features/network_map/presentation/network_map_chrome_controls.dart';",
      ),
    );
    expect(root, contains('NetworkMapChrome('));
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
    expect(root, isNot(contains('class _NetworkMapChrome')));
    expect(root, isNot(contains('String _displayRegionName(')));
    expect(root, isNot(contains('NetworkMapSearchEntryButton(')));
    expect(root, isNot(contains('NetworkMapTopBarRouteDraft(')));
    expect(owner, contains('class NetworkMapChrome'));
    expect(owner, contains('NetworkMapLookupToast('));
    expect(owner, contains('NetworkMapCurrentLocationButton('));
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
