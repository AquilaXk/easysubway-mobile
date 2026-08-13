import 'dart:io';

import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_panel_state.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_nearby_panel_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 420, height: 720, child: child)),
);

void main() {
  testWidgets('idle·loading은 success builder 없이 132px indicator를 보존한다', (
    tester,
  ) async {
    for (final status in [
      NetworkMapNearbyPanelStatus.idle,
      NetworkMapNearbyPanelStatus.loading,
    ]) {
      var successBuildCount = 0;
      await tester.pumpWidget(
        _host(
          NetworkMapNearbyPanelContent(
            status: status,
            successBuilder: (context) {
              successBuildCount += 1;
              return (
                stationBar: const SizedBox(key: Key('stationBar')),
                dataPanel: const SizedBox(key: Key('dataPanel')),
              );
            },
          ),
        ),
      );

      expect(successBuildCount, 0);
      final content = find.byType(NetworkMapNearbyPanelContent);
      final loadingFinder = find.descendant(
        of: content,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 132,
        ),
      );
      expect(loadingFinder, findsOneWidget);
      final loading = tester.widget<SizedBox>(loadingFinder);
      expect(loading.height, 132);
      expect(
        find.descendant(
          of: content,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('success는 station bar·gap·padded data panel을 한 번 조합한다', (
    tester,
  ) async {
    var successBuildCount = 0;
    await tester.pumpWidget(
      _host(
        NetworkMapNearbyPanelContent(
          status: NetworkMapNearbyPanelStatus.success,
          successBuilder: (context) {
            successBuildCount += 1;
            return (
              stationBar: const SizedBox(key: Key('stationBar'), height: 48),
              dataPanel: const SizedBox(key: Key('dataPanel'), height: 72),
            );
          },
        ),
      ),
    );

    expect(successBuildCount, 1);
    expect(find.byKey(const Key('stationBar')), findsOneWidget);
    expect(find.byKey(const Key('dataPanel')), findsOneWidget);
    final gapFinder = find.descendant(
      of: find.byType(NetworkMapNearbyPanelContent),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 17,
      ),
    );
    expect(gapFinder, findsOneWidget);
    final gap = tester.widget<SizedBox>(gapFinder);
    expect(gap.height, 17);
    final padding = tester.widget<Padding>(
      find.ancestor(
        of: find.byKey(const Key('dataPanel')),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(24, 0, 24, 12));
  });

  test('root는 public content owner를 쓰고 private content class가 없다', () {
    final root = File('lib/network_map.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_nearby_panel_content.dart';",
      ),
    );
    expect(root, contains('NetworkMapNearbyPanelContent('));
    expect(root, isNot(contains('class _NetworkMapNearbyPanelBody')));
    expect(root, isNot(contains('class _NetworkMapNearbySuccessList')));
  });
}
