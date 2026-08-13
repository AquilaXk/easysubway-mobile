import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_unavailable_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('load failure는 exact accessible state와 retry action을 보존한다', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      _host(NetworkMapLoadFailure(onRetry: () => retryCount += 1)),
    );

    final stateCard = tester.widget<AccessibleStateCard>(
      find.byType(AccessibleStateCard),
    );
    expect(stateCard.icon, Icons.map_outlined);
    expect(stateCard.title, '노선도를 불러오지 못했어요');
    expect(stateCard.subtitle, '네트워크 상태를 확인한 뒤 다시 시도하거나 역명으로 검색해 주세요.');
    expect(stateCard.actions, hasLength(1));

    final padding = tester.widget<Padding>(
      find.ancestor(
        of: find.byType(AccessibleStateCard),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.all(24));
    final retry = find.byKey(const Key('networkMapRetryButton'));
    expect(retry, findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    await tester.tap(retry);
    expect(retryCount, 1);
  });

  testWidgets('original map unavailable은 exact neutral surface를 보존한다', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const OriginalRouteMapUnavailable()));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color == EasySubwayAccessibleColors.surfaceDefault,
      ),
      findsOneWidget,
    );
    final message = tester.widget<Text>(find.text('노선도를 불러오지 못했어요'));
    expect(message.style?.fontSize, 16);
    expect(message.style?.fontWeight, FontWeight.w700);
  });

  test('screen과 canvas는 unavailable-state owner만 소비하고 private duplicate가 없다', () {
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    final canvas = File(
      'lib/features/network_map/presentation/network_map_canvas.dart',
    ).readAsStringSync();
    expect(
      root,
      contains(
        "import '../features/network_map/presentation/network_map_unavailable_states.dart';",
      ),
    );
    expect(root, contains('NetworkMapLoadFailure('));
    expect(canvas, contains("import 'network_map_unavailable_states.dart';"));
    expect(canvas, contains('OriginalRouteMapUnavailable('));
    expect(root, isNot(contains('class _NetworkMapLoadFailure')));
    expect(root, isNot(contains('class _OriginalRouteMapUnavailable')));
    expect(canvas, isNot(contains('class _NetworkMapLoadFailure')));
    expect(canvas, isNot(contains('class _OriginalRouteMapUnavailable')));
  });
}
