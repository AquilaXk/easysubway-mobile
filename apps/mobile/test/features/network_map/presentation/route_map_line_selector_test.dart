import 'dart:math' as math;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_choices.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_line_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/datapack_line_colors.dart';
import '../../../support/host_text_contrast.dart';
import '../../../support/korean_test_font.dart';
import '../../../support/test_viewport.dart';

RouteMapLineChoice _choice(String id, String name, String mark, int argb) =>
    RouteMapLineChoice(
      lineId: id,
      name: name,
      markLabel: mark,
      color: Color(argb),
    );

final _choices = [
  _choice('seoul-1', '1호선', '1', 0xFF0052A4),
  _choice('seoul-2', '2호선', '2', 0xFF00A84D),
  _choice('seoul-9', '9호선', '9', 0xFFBDB092),
  _choice('airport', '공항', '공', 0xFF0090D2),
  _choice('gyeongui', '경의중앙', '경', 0xFF77C4A3),
  _choice('suin', '수인분당', '수', 0xFFF5A200),
  _choice('incheon-2', '인천2', '인', 0xFFED8B00),
  _choice('everline', '에버라인', '에', 0xFF509F22),
  _choice('uijeongbu', '의정부', '의', 0xFFFDA600),
  _choice('ui-sinseol', '우이신설', '우', 0xFFB0CE18),
  _choice('gimpo', '김포골드', '김', 0xFFA17800),
  _choice('gtx-a', 'GTX-A', 'G', 0xFF9F6181),
];

Matcher _selectable(String label, {required bool selected}) => isSemantics(
  label: label,
  isButton: true,
  isSelected: selected,
  hasTapAction: true,
);

Finder _chip(String lineId) => find.byKey(Key('routeMapLineChip-$lineId'));
Finder _cell(String lineId) => find.byKey(Key('routeMapLineSheetCell-$lineId'));
final _allCell = find.byKey(const Key('routeMapLineSheetAll'));
final _sheetButton = find.byKey(const Key('routeMapLineSheetButton'));

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget _app(Widget child, {double textScale = 1.0, String? fontFamily}) =>
    MaterialApp(
      theme: ThemeData(fontFamily: fontFamily),
      builder: (context, home) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: home!,
      ),
      home: Scaffold(body: child),
    );

Widget _strip({
  List<RouteMapLineChoice>? choices,
  String? selectedLineId,
  ValueChanged<String>? onSelected,
  VoidCallback? onOpenSheet,
}) => Align(
  alignment: Alignment.topCenter,
  child: RouteMapLineStrip(
    choices: choices ?? _choices,
    selectedLineId: selectedLineId,
    onSelected: onSelected ?? (_) {},
    onOpenSheet: onOpenSheet ?? () {},
  ),
);

/// 시트를 여는 단추 하나만 둔 화면. 고른 결과를 [picks]에 쌓는다.
Widget _sheetHost({
  required List<String?> picks,
  String? selectedLineId,
  List<RouteMapLineChoice>? choices,
  double textScale = 1.0,
  String? fontFamily,
}) => _app(
  Builder(
    builder: (context) => TextButton(
      onPressed: () => showRouteMapLineSheet(
        context,
        choices: choices ?? _choices,
        selectedLineId: selectedLineId,
        onSelected: picks.add,
      ),
      child: const Text('열기'),
    ),
  ),
  textScale: textScale,
  fontFamily: fontFamily,
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKoreanTestFont);

  group('노선 줄', () {
    testWidgets('노선을 받은 순서대로 칩으로 보이고 고른 칩만 선택 상태다', (tester) async {
      final semantics = tester.ensureSemantics();
      useLogicalViewport(tester, const Size(1600, 800));
      await tester.pumpWidget(_app(_strip(selectedLineId: 'airport')));

      final lefts = [
        for (final choice in _choices)
          tester.getTopLeft(_chip(choice.lineId)).dx,
      ];
      expect(lefts, orderedEquals([...lefts]..sort()));
      expect(
        tester.getSemantics(_chip('airport')),
        _selectable('공항', selected: true),
      );
      expect(
        tester.getSemantics(_chip('seoul-1')),
        _selectable('1호선', selected: false),
      );
      semantics.dispose();
    });

    testWidgets('칩을 누르면 그 노선을 고르고 펼침 단추는 노선 선택 시트를 연다', (tester) async {
      final semantics = tester.ensureSemantics();
      final picked = <String>[];
      var opened = 0;
      await tester.pumpWidget(
        _app(_strip(onSelected: picked.add, onOpenSheet: () => opened++)),
      );

      await tester.tap(_chip('seoul-2'));
      await tester.tap(_sheetButton);

      expect(picked, ['seoul-2']);
      expect(opened, 1);
      expect(
        tester.getSemantics(_sheetButton),
        isSemantics(tooltip: '노선 선택', isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('칩 흰 글자는 데이터팩의 모든 노선색에서 바탕과 4.5:1 이상이다', (tester) async {
      final colors = datapackLineColors.toList();
      final choices = [
        for (var index = 0; index < colors.length; index++)
          RouteMapLineChoice(
            lineId: 'line-$index',
            name: '노선$index',
            markLabel: '노',
            color: colors[index],
          ),
      ];
      await tester.pumpWidget(_app(_strip(choices: choices)));

      for (final choice in choices) {
        final mark = tester.widget<LineMark>(
          find.descendant(
            of: _chip(choice.lineId),
            matching: find.byType(LineMark),
          ),
        );
        expect(mark.label, choice.name);
        expect(
          _contrast(
            mark.color,
            EasySubwayAccessibleColors.interactionOnPrimary,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${choice.color} 노선 칩',
        );
      }
    });

    testWidgets('밝은 노선색 칩 글자 대비를 그려진 화면에서 잰다', (tester) async {
      await expectHostTextContrast(
        tester,
        _strip(
          choices: [
            for (final choice in _choices)
              if ({'seoul-9', 'ui-sinseol', 'gyeongui'}.contains(choice.lineId))
                choice,
          ],
          selectedLineId: 'ui-sinseol',
        ),
      );
    });

    testWidgets('글자 2.0배에서도 넘치지 않고 터치 영역이 48dp다', (tester) async {
      useLogicalViewport(tester, const Size(360, 800));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(_strip(selectedLineId: 'seoul-2'), textScale: 2.0),
      );

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('고른 노선 칩이 줄 밖에 있으면 보이는 곳으로 스크롤한다', (tester) async {
      useLogicalViewport(tester, const Size(360, 800));
      await tester.pumpWidget(_app(_strip()));
      final stripRect = tester.getRect(
        find.byKey(const Key('routeMapLineStrip')),
      );
      expect(
        stripRect.contains(tester.getCenter(_chip('gtx-a'))),
        isFalse,
        reason: '마지막 칩은 처음에 줄 밖에 있다',
      );

      await tester.pumpWidget(_app(_strip(selectedLineId: 'gtx-a')));
      await tester.pumpAndSettle();

      expect(stripRect.contains(tester.getCenter(_chip('gtx-a'))), isTrue);
    });
  });

  group('노선 선택 시트', () {
    testWidgets('제목, 닫기, 전체 노선 줄, 3열 격자와 원형 마크를 보인다', (tester) async {
      useLogicalViewport(tester, const Size(393, 852));
      await tester.pumpWidget(
        _sheetHost(picks: [], fontFamily: koreanTestFontFamily),
      );
      await _openSheet(tester);

      expect(find.text('노선 선택'), findsOneWidget);
      expect(find.byTooltip('닫기'), findsOneWidget);
      expect(
        find.descendant(of: _allCell, matching: find.text('전체 노선')),
        findsOneWidget,
      );
      final tops = [
        for (final choice in _choices.take(4))
          tester.getTopLeft(_cell(choice.lineId)).dy,
      ];
      expect(tops[1], tops[0]);
      expect(tops[2], tops[0]);
      expect(tops[3], greaterThan(tops[0]));
      expect(
        tester.getTopLeft(_cell('seoul-2')).dx,
        greaterThan(tester.getTopLeft(_cell('seoul-1')).dx),
      );
      expect(
        tester.getTopLeft(_allCell).dy,
        lessThan(tester.getTopLeft(_cell('seoul-1')).dy),
      );
      for (final choice in _choices) {
        final mark = tester.widget<LineMark>(
          find.descendant(
            of: _cell(choice.lineId),
            matching: find.byType(LineMark),
          ),
        );
        expect(mark.label, choice.markLabel);
        expect(mark.color, choice.color);
        expect(isLineMarkCircle(mark.label), isTrue);
        expect(
          find.descendant(
            of: _cell(choice.lineId),
            matching: find.text(choice.name),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('고른 노선 칸은 회색 바탕과 강조 굵기, 선택 상태다', (tester) async {
      final semantics = tester.ensureSemantics();
      useLogicalViewport(tester, const Size(393, 852));
      await tester.pumpWidget(
        _sheetHost(picks: [], selectedLineId: 'ui-sinseol'),
      );
      await _openSheet(tester);

      Color background(Finder cell) => tester
          .widget<ColoredBox>(
            find.descendant(of: cell, matching: find.byType(ColoredBox)).first,
          )
          .color;
      FontWeight? weight(String lineId, String name) => tester
          .widget<Text>(
            find.descendant(of: _cell(lineId), matching: find.text(name)),
          )
          .style
          ?.fontWeight;

      expect(
        background(_cell('ui-sinseol')),
        EasySubwayAccessibleColors.surfaceSubtle,
      );
      expect(weight('ui-sinseol', '우이신설'), EasySubwayFontWeight.emphasis);
      expect(
        background(_cell('seoul-1')),
        isNot(background(_cell('ui-sinseol'))),
      );
      expect(weight('seoul-1', '1호선'), EasySubwayFontWeight.regular);
      expect(
        tester.getSemantics(_cell('ui-sinseol')),
        _selectable('우이신설', selected: true),
      );
      expect(
        tester.getSemantics(_allCell),
        _selectable('전체 노선', selected: false),
      );
      semantics.dispose();
    });

    testWidgets('고른 노선이 없으면 전체 노선 줄이 선택 상태다', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_sheetHost(picks: []));
      await _openSheet(tester);

      expect(
        tester.getSemantics(_allCell),
        _selectable('전체 노선', selected: true),
      );
      semantics.dispose();
    });

    testWidgets('칸을 누르면 그 노선을 고르고 시트가 닫힌다', (tester) async {
      final picks = <String?>[];
      useLogicalViewport(tester, const Size(393, 852));
      await tester.pumpWidget(_sheetHost(picks: picks));
      await _openSheet(tester);

      await tester.tap(_cell('ui-sinseol'));
      await tester.pumpAndSettle();

      expect(picks, ['ui-sinseol']);
      expect(find.text('노선 선택'), findsNothing);
    });

    testWidgets('전체 노선을 누르면 고른 노선을 비운다', (tester) async {
      final picks = <String?>[];
      await tester.pumpWidget(
        _sheetHost(picks: picks, selectedLineId: 'seoul-2'),
      );
      await _openSheet(tester);

      await tester.tap(_allCell);
      await tester.pumpAndSettle();

      expect(picks, [null]);
      expect(find.text('노선 선택'), findsNothing);
    });

    testWidgets('닫기는 아무 노선도 고르지 않고 닫는다', (tester) async {
      final picks = <String?>[];
      await tester.pumpWidget(
        _sheetHost(picks: picks, selectedLineId: 'seoul-2'),
      );
      await _openSheet(tester);

      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();

      expect(picks, isEmpty);
      expect(find.text('노선 선택'), findsNothing);
    });

    testWidgets('노선 수가 3의 배수가 아니면 마지막 줄의 남는 칸은 비어 있다', (tester) async {
      await tester.pumpWidget(
        _sheetHost(picks: [], choices: _choices.take(4).toList()),
      );
      await _openSheet(tester);

      expect(find.byType(LineMark), findsNWidgets(4));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'routeMapLineSheetCell-',
              ),
        ),
        findsNWidgets(4),
      );
    });

    // 칸 이름은 사용자의 글자 배율을 그대로 따르고 한 줄에 그린다. 모자란 폭은 배율을
    // 줄여서가 아니라 열 수를 줄여서(3, 2, 1) 채운다. 크기는 Pixel 6(411dp)과 작은
    // 폰(360dp)이다.
    const columnScenarios = [
      (name: '411dp 글자 1.0배', size: Size(411, 914), scale: 1.0, columns: 3),
      (name: '411dp 글자 1.5배', size: Size(411, 914), scale: 1.5, columns: 2),
      (name: '411dp 글자 2.0배', size: Size(411, 914), scale: 2.0, columns: 1),
      (name: '360dp 글자 1.0배', size: Size(360, 800), scale: 1.0, columns: 2),
      (name: '360dp 글자 2.0배', size: Size(360, 800), scale: 2.0, columns: 1),
    ];
    for (final scenario in columnScenarios) {
      testWidgets(
        '${scenario.name}에서 모든 칸 이름이 같은 배율로 한 줄이고 ${scenario.columns}열이다',
        (tester) async {
          useLogicalViewport(tester, scenario.size);
          await tester.pumpWidget(
            _sheetHost(
              picks: [],
              textScale: scenario.scale,
              fontFamily: koreanTestFontFamily,
            ),
          );
          await _openSheet(tester);

          for (final choice in _choices) {
            final name = find.descendant(
              of: _cell(choice.lineId),
              matching: find.text(choice.name),
            );
            final context = tester.element(name);
            final oneLine = TextPainter(
              text: TextSpan(
                text: choice.name,
                style: DefaultTextStyle.of(
                  context,
                ).style.merge(tester.widget<Text>(name).style),
              ),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scenario.scale),
            )..layout();
            final rendered = tester.getSize(name);
            expect(
              rendered.width,
              moreOrLessEquals(oneLine.width, epsilon: 0.01),
              reason: '${choice.name} 폭은 사용자 배율 그대로',
            );
            expect(
              rendered.height,
              moreOrLessEquals(oneLine.height, epsilon: 0.01),
              reason: '${choice.name}은 한 줄',
            );
            oneLine.dispose();
          }
          final firstRowTop = tester.getTopLeft(_cell('seoul-1')).dy;
          final columns = _choices
              .where(
                (choice) =>
                    tester.getTopLeft(_cell(choice.lineId)).dy == firstRowTop,
              )
              .length;
          expect(columns, scenario.columns);
          expect(
            tester.getSize(_allCell).width,
            tester.getSize(find.byType(Table)).width,
            reason: '전체 노선 줄은 열 수와 무관하게 전체 폭',
          );
        },
      );
    }

    testWidgets('글자 2.0배에서도 넘치지 않고 터치 영역이 48dp다', (tester) async {
      useLogicalViewport(tester, const Size(360, 800));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _sheetHost(picks: [], selectedLineId: 'ui-sinseol', textScale: 2.0),
      );
      await _openSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('노선 선택'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    });
  });
}
