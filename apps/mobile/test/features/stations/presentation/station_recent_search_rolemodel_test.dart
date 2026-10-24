import 'package:clock/clock.dart';
import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_recent_search_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _line1 = StationSearchLine(
  id: 'seoul-1',
  name: '수도권 1호선',
  color: '#0052A4',
  stationCode: '100',
);
const _line4 = StationSearchLine(
  id: 'seoul-4',
  name: '수도권 4호선',
  color: '#00A5DE',
  stationCode: '450',
);

final _today = DateTime(2026, 10, 24, 12, 40);

List<RecentSearchEntry> _entries() => [
  RecentRouteSearchEntry(
    originStationId: 'station-soyosan',
    originStationName: '소요산',
    destinationStationId: 'station-sangnoksu',
    destinationStationName: '상록수',
    region: '수도권',
    searchedAt: DateTime(2026, 10, 24, 12, 30),
    originLines: const [_line1],
    destinationLines: const [_line4],
  ),
  RecentStationSearchEntry(
    query: '충무로',
    region: '수도권',
    searchedAt: DateTime(2026, 10, 23, 9),
    lines: const [_line4],
  ),
  RecentStationSearchEntry(
    query: '부평',
    region: '수도권',
    searchedAt: DateTime(2025, 12, 31, 9),
  ),
];

Future<void> _pump(WidgetTester tester, {double textScale = 1}) async {
  await withClock(Clock.fixed(_today), () async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: StationRecentSearchSection(
                entries: _entries(),
                enabled: true,
                onStationSelected: (_) {},
                onRouteSelected: (_) {},
                onRemove: (_) {},
                onClearAll: () {},
              ),
            ),
          ),
        ),
      ),
    );
  });
}

void main() {
  testWidgets('행마다 검색한 날짜를 지우기 버튼 왼쪽에 쓴다', (tester) async {
    await _pump(tester);

    expect(find.text('10. 24.'), findsOneWidget);
    expect(find.text('10. 23.'), findsOneWidget);
    expect(find.text('2025. 12. 31.'), findsOneWidget);
    final date = tester.widget<Text>(find.text('10. 24.')).style!;
    expect(date.color, EasySubwayAccessibleColors.contentMuted);
    final remove = find.byKey(
      const Key('recentRouteSearchRemove-station-soyosan--station-sangnoksu'),
    );
    expect(
      tester.getCenter(find.text('10. 24.')).dx,
      lessThan(tester.getCenter(remove).dx),
    );
  });

  testWidgets('행 사이와 머리 아래에 얇은 구분선을 둔다', (tester) async {
    await _pump(tester);

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(3));
    for (final divider in dividers) {
      expect(divider.thickness, 1);
      expect(divider.color, EasySubwayAccessibleColors.borderSubtle);
    }
  });

  testWidgets('스크린리더는 검색한 날짜도 함께 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      find.bySemanticsLabel('최근 경로 소요산역 → 상록수역 다시 찾기, 10월 24일 검색'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('최근 검색어 충무로 검색, 10월 23일 검색'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('글자 2.0배에서는 날짜를 역 이름 아래로 내리고 넘치지 않는다', (tester) async {
    await _pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    final name = tester.getRect(find.text('충무로'));
    final date = tester.getRect(find.text('10. 23.'));
    expect(date.top, greaterThanOrEqualTo(name.bottom));
    expect(date.left, lessThan(name.right));
  });
}
