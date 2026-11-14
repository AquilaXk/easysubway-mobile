import 'dart:async';

import 'package:easysubway_mobile/features/home_widget/home_widget_link_handler.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_configuration_screen.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('시간표가 있는 즐겨찾기를 선택하면 해당 widget을 구성한다', (tester) async {
    WidgetStationSelection? configured;
    await tester.pumpWidget(
      MaterialApp(
        home: NextTrainWidgetConfigurationScreen(
          loadSelections: () async => const [_selection],
          configure: (selection) async => configured = selection,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('사당'));
    await tester.pumpAndSettle();

    expect(configured, same(_selection));
  });

  testWidgets('지원 시간표가 없으면 선택지를 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NextTrainWidgetConfigurationScreen(
          loadSelections: () async => const [],
          configure: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('시간표가 있는 즐겨찾기 역이 없어요.'), findsOneWidget);
  });

  testWidgets('configuration 화면 dispose 뒤 load가 끝나도 resource를 한 번 닫는다', (
    tester,
  ) async {
    final selections = Completer<List<WidgetStationSelection>>();
    var closeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NextTrainWidgetConfigurationScreen(
          loadSelections: () => runNextTrainWidgetConfigurationOperation(
            operation: () => selections.future,
            close: () async => closeCount += 1,
          ),
          configure: (_) async {},
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    selections.complete(const []);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('widget deep link는 같은 station 상세를 연다', (tester) async {
    final clicks = StreamController<Uri?>();
    addTearDown(clicks.close);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: HomeWidgetLinkHandler(
          clicks: clicks.stream,
          navigatorKey: navigatorKey,
          stationDetailBuilder: (stationId) => Scaffold(body: Text(stationId)),
          child: const Scaffold(body: Text('홈')),
        ),
      ),
    );

    clicks.add(
      Uri.parse(
        'easysubway://station/detail?stationId=station-sadang&lineId=seoul-4',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('station-sadang'), findsOneWidget);
  });

  testWidgets('cold start async initial URI는 첫 station 상세를 연다', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final initialUri = Future<Uri?>.value(
      Uri.parse(
        'easysubway://station/detail?stationId=station-sadang&lineId=seoul-4',
      ),
    );

    await tester.pumpWidget(
      HomeWidgetLinkHandler(
        clicks: initialUri.asStream(),
        navigatorKey: navigatorKey,
        stationDetailBuilder: (stationId) => Scaffold(body: Text(stationId)),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('홈')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('station-sadang'), findsOneWidget);
  });

  test('stationIdFromHomeWidgetUri는 유효하지 않거나 조작된 deep link를 거부한다', () {
    expect(
      stationIdFromHomeWidgetUri(
        Uri.parse(
          'easysubway://station/detail?stationId=KRIC_123:A.1&lineId=seoul-4',
        ),
      ),
      'KRIC_123:A.1',
    );
    for (final badUri in [
      null,
      Uri.parse('https://station/detail?stationId=station-sadang'),
      Uri.parse('easysubway://other/detail?stationId=station-sadang'),
      Uri.parse('easysubway://station/other?stationId=station-sadang'),
      Uri.parse('easysubway://user@station/detail?stationId=station-sadang'),
      Uri.parse('easysubway://station:8080/detail?stationId=station-sadang'),
      Uri.parse('easysubway://station/detail?stationId=station-sadang#frag'),
      Uri.parse('easysubway://station/detail?stationId=../sadang'),
      Uri.parse('easysubway://station/detail?stationId=station%20sadang'),
      Uri.parse('easysubway://station/detail?stationId=${'a' * 65}'),
      Uri.parse(
        'easysubway://station/detail?stationId=station-sadang&lineId=../bad',
      ),
      Uri.parse('easysubway://station/detail?stationId=station-sadang&extra=1'),
    ]) {
      expect(stationIdFromHomeWidgetUri(badUri), isNull, reason: '$badUri');
    }
  });
}

const _selection = WidgetStationSelection(
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  stationName: '사당',
  lineName: '수도권 4호선',
);
