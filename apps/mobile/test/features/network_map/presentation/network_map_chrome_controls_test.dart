import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
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

  test('root는 direct owner만 소비하고 private compatibility surface가 없다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_chrome_controls.dart';",
      ),
    );
    expect(root, contains('NetworkMapLookupToast('));
    expect(root, contains('NetworkMapCurrentLocationButton('));
    expect(root, contains('NetworkMapSearchEntryButton('));
    expect(root, isNot(contains('class _NetworkMapLookupToast')));
    expect(root, isNot(contains('class _NetworkMapCurrentLocationButton')));
    expect(root, isNot(contains('class _NetworkMapSearchField')));
  });
}

void _noop() {}
