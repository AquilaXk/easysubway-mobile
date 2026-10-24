import 'dart:io' show Platform;

import 'package:easysubway_mobile/features/network_map/presentation/station_popover_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/korean_test_font.dart';

const _menuBoundaryKey = ValueKey('station-popover-golden-boundary');
const _menuWidth = 232.0;
const _injectVisualMutation = bool.fromEnvironment(
  'EASYSUBWAY_GOLDEN_MUTATION',
);
const _goldenBackground = Color(0xFFF4F7F7);
const _mutationBackground = Color(0xFF004D40);

Future<void> _pumpMenu(
  WidgetTester tester, {
  Set<RouteDraftSlot> selected = const {},
  Set<RouteDraftSlot> disabled = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: koreanTestFontFamily),
      home: Scaffold(
        backgroundColor: _goldenBackground,
        body: Center(
          child: RepaintBoundary(
            key: _menuBoundaryKey,
            child: ColoredBox(
              // CI의 mutation probe만 알려진 픽셀 차이를 넣는다. 일반 골든 비교에는
              // define을 넘기지 않아 기준 렌더는 같다.
              color: _injectVisualMutation
                  ? _mutationBackground
                  : _goldenBackground,
              child: StationPopoverMenu(
                width: _menuWidth,
                stationName: '강남역',
                selectedSlots: selected,
                disabledSlots: disabled,
                onAction: (_) {},
                onClose: () {},
                onRealtime: () {},
                onTimetable: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKoreanTestFont);

  // 골든 비교는 macOS 호스트 래스터라이저에서만 한다(CI 크로스플랫폼 오탐 방지).
  final skipReason = !Platform.isMacOS;

  testWidgets('기본 상태', (tester) async {
    await _pumpMenu(tester);
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_popover_menu_default.png'),
    );
  }, skip: skipReason);

  testWidgets('출발 해제와 도착 비활성', (tester) async {
    await _pumpMenu(
      tester,
      selected: const {RouteDraftSlot.origin},
      disabled: const {RouteDraftSlot.destination},
    );
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_popover_menu_selected_disabled.png'),
    );
  }, skip: skipReason);
}
