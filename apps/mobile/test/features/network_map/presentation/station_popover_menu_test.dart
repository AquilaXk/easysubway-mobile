import 'package:easysubway_mobile/design_tokens.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_popover_geometry.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_popover_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

class _Calls {
  final actions = <RouteDraftSlot>[];
  var closes = 0;
  var realtime = 0;
  var timetable = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  double width = 232,
  double textScale = 1,
  Set<RouteDraftSlot> selected = const {},
  Set<RouteDraftSlot> disabled = const {},
  String? stationName = '충무로역',
  bool withStationActions = true,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(412, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: StationPopoverMenu(
              width: width,
              stationName: stationName,
              selectedSlots: selected,
              disabledSlots: disabled,
              onAction: calls.actions.add,
              onClose: () => calls.closes += 1,
              onRealtime: withStationActions ? () => calls.realtime += 1 : null,
              onTimetable: withStationActions
                  ? () => calls.timetable += 1
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  testWidgets('윗줄은 출발·경유·도착, 아랫줄은 실시간·전체 시간표다', (tester) async {
    await _pump(tester);

    for (final label in ['출발', '경유', '도착', '실시간', '전체 시간표']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('닫기'), findsNothing);
    final top = tester.getCenter(find.text('출발')).dy;
    final bottom = tester.getCenter(find.text('실시간')).dy;
    expect(bottom, greaterThan(top));
  });

  testWidgets('역할 핀은 출발 초록, 경유 회색, 도착 빨강이다', (tester) async {
    await _pump(tester);

    Color pinColor(String label) => tester
        .widget<Icon>(
          find.descendant(
            of: find.ancestor(
              of: find.text(label),
              matching: find.byType(InkWell),
            ),
            matching: find.byIcon(Icons.location_on),
          ),
        )
        .color!;

    expect(pinColor('출발'), EasySubwayPopoverColors.originPin);
    expect(pinColor('경유'), EasySubwayPopoverColors.waypointPin);
    expect(pinColor('도착'), EasySubwayPopoverColors.destinationPin);
  });

  testWidgets('각 칸을 누르면 그 동작을 부른다', (tester) async {
    final calls = await _pump(tester);

    await tester.tap(find.text('출발'));
    await tester.tap(find.text('경유'));
    await tester.tap(find.text('도착'));
    await tester.tap(find.text('실시간'));
    await tester.tap(find.text('전체 시간표'));

    expect(calls.actions, [
      RouteDraftSlot.origin,
      RouteDraftSlot.waypoint,
      RouteDraftSlot.destination,
    ]);
    expect(calls.realtime, 1);
    expect(calls.timetable, 1);
  });

  testWidgets('이미 정한 칸은 해제로 쓰고, 누르면 같은 슬롯을 보낸다', (tester) async {
    final handle = tester.ensureSemantics();
    final calls = await _pump(tester, selected: {RouteDraftSlot.origin});

    expect(find.text('출발 해제'), findsOneWidget);
    expect(find.text('출발'), findsNothing);
    expect(find.bySemanticsLabel('출발역 해제'), findsOneWidget);
    await tester.tap(find.text('출발 해제'));
    expect(calls.actions, [RouteDraftSlot.origin]);
    handle.dispose();
  });

  testWidgets('다른 칸에 이미 있는 역의 칸은 비활성이고 누르지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    final calls = await _pump(tester, disabled: {RouteDraftSlot.destination});

    await tester.tap(find.text('도착'), warnIfMissed: false);
    expect(calls.actions, isEmpty);
    expect(
      tester.getSemantics(find.text('도착')),
      isSemantics(label: '도착역으로 설정', isEnabled: false, isButton: true),
    );
    handle.dispose();
  });

  testWidgets('스크린리더는 역 이름 메뉴 안에서 다섯 버튼을 차례로 읽고 닫을 수 있다', (tester) async {
    final handle = tester.ensureSemantics();
    final calls = await _pump(tester);

    for (final label in ['출발역으로 설정', '경유지로 추가', '도착역으로 설정', '실시간', '전체 시간표']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    final group = tester.getSemantics(find.bySemanticsLabel('충무로역 메뉴'));
    expect(group, isSemantics(hasDismissAction: true));
    group.owner!.performAction(group.id, SemanticsAction.dismiss);
    expect(calls.closes, 1);
    handle.dispose();
  });

  testWidgets('역 동작이 없으면 아랫줄을 그리지 않는다', (tester) async {
    await _pump(tester, withStationActions: false);

    expect(find.text('실시간'), findsNothing);
    expect(find.text('전체 시간표'), findsNothing);
    expect(find.text('출발'), findsOneWidget);
  });

  testWidgets('메뉴 크기는 설계 비율 그대로이고 꼬리 끝이 아래 가운데다', (tester) async {
    await _pump(tester, width: 200);

    final size = tester.getSize(find.byType(StationPopoverMenu));
    expect(size.width, 200);
    expect(
      size.height,
      closeTo(
        200 *
            kStationPopoverDesignSize.height /
            kStationPopoverDesignSize.width,
        0.01,
      ),
    );
    expect(kStationPopoverTailTip.dx, kStationPopoverDesignSize.width / 2);
    expect(kStationPopoverTailTip.dy, kStationPopoverDesignSize.height);
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets('글자 $scale배에서도 넘치지 않는다', (tester) async {
      await _pump(tester, textScale: scale, width: 196);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('버튼은 48dp 터치 영역을 가진다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
