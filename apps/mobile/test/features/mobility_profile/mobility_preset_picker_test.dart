import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_picker.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showMobilityPresetSheet은 바텀시트 헤더로 걷는 속도 대신 이동 조건을 표기한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                key: const Key('openPresetSheetButton'),
                onPressed: () => showMobilityPresetSheet(
                  context,
                  current: MobilityPreset.standard,
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('openPresetSheetButton')));
    await tester.pumpAndSettle();

    // 헤더가 '이동 조건'으로 표기되어야 한다.
    expect(find.text('이동 조건'), findsOneWidget);
    // '걷는 속도'는 헤더로 노출되지 않아야 한다.
    expect(find.text('걷는 속도'), findsNothing);
  });
}
