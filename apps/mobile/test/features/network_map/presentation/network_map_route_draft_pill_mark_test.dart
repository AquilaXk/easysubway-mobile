import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/korean_test_font.dart';

const _stationName = '홍대입구역';
const _originRow = Key('networkMapRouteDraftOriginRow');

RouteDraftStation _origin(String lineId, String lineName) => RouteDraftStation(
  id: 'origin',
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
  required RouteDraftStation origin,
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
            destination: null,
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
          roleColorForSlot: (_) => Colors.black,
          lineBadgeBuilder: routeDraftStationLineBadge,
        ),
      ),
    ),
  );
}

double _nameWidth(WidgetTester tester) => tester
    .getSize(
      find.descendant(
        of: find.byKey(_originRow),
        matching: find.text(_stationName),
      ),
    )
    .width;

Size _markSize(WidgetTester tester, String lineId) =>
    tester.getSize(find.byKey(Key('stationLineBadge-$lineId')));

void main() {
  setUpAll(loadKoreanTestFont);

  // 알약 노선은 마크가 4글자라 입력 칸 안에서 이름 폭을 깎는다. 하한은 알약
  // 마크가 더 좁았던 기준선(c7dbe6b6)에서 잰 이름 폭이다(360dp 56, 320dp 16).
  // 테스트 글꼴(NanumGothic)에서 이름 폭은 360dp 100.3, 320dp 60.3이다.
  final baseNameWidth = {360.0: 56.0, 320.0: 16.0};
  final pillLines = [
    ('gyeongui-jungang', '수도권 경의중앙선'),
    ('airport-railroad', '수도권 공항철도'),
    ('suin-bundang', '수도권 수인분당선'),
  ];

  for (final (lineId, lineName) in pillLines) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          '알약 노선 $lineName ${width}dp 글자 $scale배: 이름이 먼저고 넘치지 않으며 마크는 칸 안에 든다',
          (tester) async {
            await _pumpDraft(
              tester,
              width: width,
              scale: scale,
              origin: _origin(lineId, lineName),
            );

            expect(
              tester.takeException(),
              isNull,
              reason: 'RenderFlex overflow',
            );
            final name = _nameWidth(tester);
            if (scale == 1.0) {
              expect(
                name,
                greaterThanOrEqualTo(baseNameWidth[width]!),
                reason: '1.0배 이름 폭은 기준선 이상',
              );
            }
            expect(
              _markSize(tester, lineId),
              Size.zero,
              reason: '이 폭에서 알약은 이름 앞에서 감춘다',
            );
          },
        );
      }
    }
  }

  // 테스트 글꼴(NanumGothic)에서 알약 마크 폭은 74.86dp다. 마크 묶음 예산은 이름
  // 줄 폭의 45%라 426dp까지는 감추고 427dp부터 보인다. 예산 비율이 커지면 이
  // 폭보다 훨씬 좁은 화면에서도 보이므로 426dp가 감춤으로 남는지가 비율을 지킨다.
  for (final (lineId, lineName) in pillLines) {
    for (final (width, visible) in [(426.0, false), (427.0, true)]) {
      testWidgets(
        '알약 노선 $lineName ${width}dp 1.0배: 마크는 ${visible ? '보인다' : '감춘다'}',
        (tester) async {
          await _pumpDraft(
            tester,
            width: width,
            scale: 1.0,
            origin: _origin(lineId, lineName),
          );

          expect(
            _markSize(tester, lineId).width,
            visible ? closeTo(74.86, 0.01) : 0,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('칸이 넉넉하면 같은 알약 마크를 감추지 않고 이름 앞 칸 안에 둔다', (tester) async {
    await _pumpDraft(
      tester,
      width: 600,
      scale: 1.0,
      origin: _origin('gyeongui-jungang', '수도권 경의중앙선'),
    );

    final mark = tester.getRect(
      find.byKey(const Key('stationLineBadge-gyeongui-jungang')),
    );
    final name = tester.getRect(
      find.descendant(
        of: find.byKey(_originRow),
        matching: find.text(_stationName),
      ),
    );
    final row = tester.getRect(find.byKey(_originRow));
    expect(mark.height, 26);
    expect(mark.width, greaterThan(26));
    expect(mark.left, greaterThanOrEqualTo(row.left));
    expect(mark.top, greaterThanOrEqualTo(row.top));
    expect(mark.bottom, lessThanOrEqualTo(row.bottom));
    expect(mark.right + 8, name.left, reason: '마크가 이름 앞에 놓이고 사이는 8dp');
    expect(name.width, greaterThanOrEqualTo(85));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('끌기 그림자도 알약 노선에서 글자 $scale배에 이름 폭을 지키고 넘치지 않는다', (
      tester,
    ) async {
      await _pumpDraft(
        tester,
        width: 360,
        scale: scale,
        origin: _origin('gyeongui-jungang', '수도권 경의중앙선'),
      );

      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_originRow)),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'RenderFlex overflow');
      final feedbackName = find.text(_stationName).last;
      expect(tester.getSize(feedbackName).width, greaterThanOrEqualTo(56));
      await drag.up();
    });
  }

  testWidgets('원 마크는 360dp 1.0배에서 이름 폭을 그대로 지킨 채 보인다', (tester) async {
    await _pumpDraft(
      tester,
      width: 360,
      scale: 1.0,
      origin: _origin('seoul-2', '수도권 2호선'),
    );

    expect(_markSize(tester, 'seoul-2'), const Size.square(26));
    expect(_nameWidth(tester), closeTo(66.3, 0.5));
  });
}
