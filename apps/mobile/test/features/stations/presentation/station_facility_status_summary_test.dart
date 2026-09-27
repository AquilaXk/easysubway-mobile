import 'package:easysubway_mobile/features/stations/presentation/station_facility_status_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StationFacilityStatusSummary renders text and semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StationFacilityStatusSummary(
            text: '시설 점검 중',
            semanticLabel: '시설 점검 중 안내',
          ),
        ),
      ),
    );

    expect(find.text('시설 점검 중'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '시설 점검 중 안내',
      ),
      findsOneWidget,
    );
    semanticsHandle.dispose();
  });
}
