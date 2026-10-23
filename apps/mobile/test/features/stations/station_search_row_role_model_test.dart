import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/stations/application/station_search_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_line_badges.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_search_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StationSearchLine _line(String id, String name, String color, String code) =>
    StationSearchLine(id: id, name: name, color: color, stationCode: code);

StationSearchResult _station(
  String id,
  String name,
  List<StationSearchLine> lines,
) => StationSearchResult(
  id: id,
  nameKo: name,
  nameEn: '',
  region: '수도권',
  dataQualityLevel: 'LEVEL_1',
  lastVerifiedAt: '2026-06-13',
  lines: lines,
);

Color _markTextColor(WidgetTester tester, String lineId) {
  final text = find.descendant(
    of: find.byKey(Key('stationLineBadge-$lineId')),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(text).style!.color!;
}

void main() {
  group('노선 마크 글자색', () {
    const cases = [
      ('airport', '수도권 공항', '#0090D2'),
      ('busan-5', '부산 5호선', '#00A84D'),
      ('suin-bundang', '수도권 수인분당', '#F5A200'),
    ];

    for (final (id, name, color) in cases) {
      testWidgets('$name($color) 마크 글자는 흰색이다', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StationLineBadge(
                line: _line(id, name, color, ''),
                size: 20,
              ),
            ),
          ),
        );

        expect(_markTextColor(tester, id), Colors.white);
      });
    }
  });

  group('역 검색 결과 행', () {
    late StationSearchState state;

    setUp(() {
      state = StationSearchState(
        status: StationSearchStatus.success,
        results: [
          _station('noryangjin', '노량진', [
            _line('seoul-1', '수도권 1호선', '#0052A4', '136'),
            _line('line-f0e747248a31', '수도권 9호선', '#BDB092', '917'),
          ]),
          _station('incheon-nonhyeon', '인천논현', [
            _line('line-558d0bd8312d', '수도권 수인분당', '#F5A200', 'K262'),
          ]),
        ],
      );
    });

    Future<void> pumpBody(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StationSearchBody(
              state: state,
              query: '노',
              onResultTap: (_, _) {},
            ),
          ),
        ),
      ),
    );

    testWidgets('역·호선 쌍마다 한 행이고 역명과 노선 마크만 담는다', (tester) async {
      await pumpBody(tester);

      final rows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'stationSearchResult-',
            ),
      );
      expect(rows, findsNWidgets(3));

      final noryangjin1 = find.byKey(
        const Key('stationSearchResult-noryangjin-seoul-1'),
      );
      expect(
        find.descendant(
          of: noryangjin1,
          matching: find.byType(StationLineBadge),
        ),
        findsOneWidget,
      );
    });

    testWidgets('호선이 없는 역은 노선 마크 없이 한 행이고 탭하면 호선 없이 선택된다', (tester) async {
      final tapped = <(String, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StationSearchBody(
              state: StationSearchState(
                status: StationSearchStatus.success,
                results: [_station('no-line', '무호선', const [])],
              ),
              query: '무',
              onResultTap: (result, line) => tapped.add((result.id, line?.id)),
            ),
          ),
        ),
      );

      final row = find.byKey(const Key('stationSearchResult-no-line-none'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(StationLineBadge)),
        findsNothing,
      );
      expect(find.bySemanticsLabel('무호선역, 선택'), findsOneWidget);

      await tester.tap(row);
      expect(tapped, [('no-line', null)]);
    });

    testWidgets('즐겨찾기 별과 토글 버튼이 없다', (tester) async {
      await pumpBody(tester);

      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('역명은 레귤러 굵기이고 일치한 글자만 강조색이다', (tester) async {
      await pumpBody(tester);

      final row = find.byKey(
        const Key('stationSearchResult-noryangjin-seoul-1'),
      );
      final name = tester.widget<RichText>(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith('노량진'),
          ),
        ),
      );
      final spans = <TextSpan>[];
      name.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          spans.add(span);
        }
        return true;
      });

      expect(spans.first.text, '노');
      expect(spans.first.style!.fontWeight, EasySubwayFontWeight.regular);
      expect(spans.last.text, '량진역');
      expect(spans.last.style!.fontWeight, EasySubwayFontWeight.regular);
      expect(spans.first.style!.color, isNot(spans.last.style!.color));
    });
  });

  testWidgets('행 구분선은 1 논리 픽셀 선이라 소수점 위치에서도 남는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationSearchBody(
            state: StationSearchState(
              status: StationSearchStatus.success,
              results: [
                _station('a', '가', const []),
                _station('b', '나', const []),
              ],
            ),
            query: '',
            onResultTap: (_, _) {},
          ),
        ),
      ),
    );

    final borders = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const Key('stationSearchResult-a-none')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>()
        .toList();
    expect(borders.first.bottom.width, 1);
    expect(borders.first.bottom.color, EasySubwayAccessibleColors.line);
  });
}
