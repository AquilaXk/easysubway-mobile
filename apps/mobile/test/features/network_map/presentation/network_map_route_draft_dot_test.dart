import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/core/ui/route_role_dot.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/korean_test_font.dart';

const _stationName = '홍대입구역';
const _originRow = Key('networkMapRouteDraftOriginRow');
const _destinationRow = Key('networkMapRouteDraftDestinationRow');

RouteDraftStation _station(String id, String lineId, String lineName) =>
    RouteDraftStation(
      id: id,
      nameKo: _stationName,
      lineId: lineId,
      lineName: lineName,
      lineColor: '#77C4A3',
      stationCode: 'K314',
    );

Future<void> _pumpDraft(
  WidgetTester tester, {
  required double width,
  required double scale,
  RouteDraftStation? origin,
  RouteDraftStation? destination,
}) async {
  tester.view.physicalSize = Size(width, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: koreanTestFontFamily),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: NetworkMapTopBarRouteDraft(
          draft: RouteDraft(
            origin: origin,
            destination: destination,
            lastModifiedAt: null,
          ),
          showWaypointRow: false,
          regionLabel: '수도권',
          onClearDraft: () {},
          onOpenWaypointSlot: () {},
          onClearOrigin: () {},
          onClearDestination: () {},
          onClearWaypoint: () {},
          onReorderDraft: (_, _) {},
          roleColorForSlot: routeDraftRoleDotColor,
          onPickOrigin: () {},
          onPickDestination: () {},
        ),
      ),
    ),
  );
}

Color _dotColor(WidgetTester tester, Key row) => tester
    .widget<RouteRoleDot>(
      find.descendant(of: find.byKey(row), matching: find.byType(RouteRoleDot)),
    )
    .color;

void main() {
  setUpAll(loadKoreanTestFont);

  // 상용 지하철 서비스의 입력 칸은 어느 폭에서도 노선 마크 없이 역할 점과 역 이름만
  // 보여 준다(#509, epic 7-46). 같은 이름 역의 구분은 검색 결과에서 고르는 단계가 맡는다.
  final pillLines = [
    ('gyeongui-jungang', '수도권 경의중앙선'),
    ('airport-railroad', '수도권 공항철도'),
    ('line-2', '2호선'),
  ];
  for (final (lineId, lineName) in pillLines) {
    for (final width in [320.0, 411.0, 600.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          '$lineName ${width}dp 글자 $scale배: 노선 마크 없이 점과 역 이름만 넘치지 않게 둔다',
          (tester) async {
            await _pumpDraft(
              tester,
              width: width,
              scale: scale,
              origin: _station('origin', lineId, lineName),
            );

            expect(
              tester.takeException(),
              isNull,
              reason: 'RenderFlex overflow',
            );
            final row = find.byKey(_originRow);
            expect(
              find.descendant(of: row, matching: find.byType(LineMark)),
              findsNothing,
            );
            expect(find.byKey(Key('stationLineBadge-$lineId')), findsNothing);
            expect(
              find.descendant(of: row, matching: find.text(_stationName)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: row, matching: find.text('출발역')),
              findsNothing,
              reason: '역할 글자 대신 점으로 구분한다',
            );
            final dot = tester.getRect(
              find.descendant(of: row, matching: find.byType(RouteRoleDot)),
            );
            final name = tester.getRect(
              find.descendant(of: row, matching: find.text(_stationName)),
            );
            expect(dot.right, lessThan(name.left), reason: '점이 이름 앞에 놓인다');
          },
        );
      }
    }
  }

  testWidgets('출발은 초록 점, 도착은 빨강 점이고 빈 칸도 점과 안내 문구를 보인다', (tester) async {
    await _pumpDraft(
      tester,
      width: 411,
      scale: 1.0,
      origin: _station('origin', 'line-2', '2호선'),
    );

    expect(_dotColor(tester, _originRow), EasySubwayRouteDotColors.origin);
    expect(
      _dotColor(tester, _destinationRow),
      EasySubwayRouteDotColors.destination,
    );
    expect(
      find.descendant(
        of: find.byKey(_destinationRow),
        matching: find.text('도착역 입력'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('스크린리더는 점 대신 역할과 노선, 역 이름을 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDraft(
      tester,
      width: 411,
      scale: 1.0,
      origin: _station('origin', 'line-2', '2호선'),
    );

    expect(
      find.bySemanticsLabel('출발역 2호선 $_stationName, 출발역 검색'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('도착역, 도착역 입력, 도착역 검색'), findsOneWidget);
    semantics.dispose();
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('끌기 그림자도 글자 $scale배에서 노선 마크 없이 넘치지 않는다', (tester) async {
      await _pumpDraft(
        tester,
        width: 360,
        scale: scale,
        origin: _station('origin', 'gyeongui-jungang', '수도권 경의중앙선'),
      );

      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_originRow)),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'RenderFlex overflow');
      expect(find.byType(LineMark), findsNothing);
      expect(find.text(_stationName), findsNWidgets(2));
      await drag.up();
    });
  }
}
