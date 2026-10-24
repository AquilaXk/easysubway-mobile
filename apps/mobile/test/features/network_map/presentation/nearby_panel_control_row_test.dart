import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/app/network_map_nearby_panel_composition.dart';
import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_panel_state.dart';
import 'package:easysubway_mobile/features/network_map/domain/nearby_adjacent_stations.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_data_source_toggle.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _line = StationSearchLine(
  id: 'seoul-3',
  name: '수도권 3호선',
  color: '#EF7C1C',
  stationCode: '321',
);

const _station = StationSearchResult(
  id: 'station-chungmuro',
  nameKo: '충무로',
  nameEn: 'Chungmuro',
  region: '수도권',
  dataQualityLevel: 'VERIFIED',
  lastVerifiedAt: '2026-10-24T00:00:00Z',
  lines: [_line],
);

RealtimeSnapshot _snapshot(String receivedAt) => RealtimeSnapshot(
  status: RealtimeSnapshotStatus.fresh,
  receivedAt: receivedAt,
  arrivals: const [],
);

Widget _controlRow({
  required NetworkMapNearbyPanelDataSource dataSource,
  String receivedAt = '2026-10-23T15:37:00Z',
  VoidCallback? onRefresh,
}) {
  final content = buildNetworkMapNearbyPanelSuccessContent(
    results: const [_station],
    realtime: _snapshot(receivedAt),
    selectedLineId: _line.id,
    dataSource: dataSource,
    timetable: null,
    adjacentStations: const NearbyAdjacentStations(
      leftName: '을지로3가',
      rightName: '동대입구',
    ),
    dataSourceToggle: NearbyDataSourceToggle(
      isRealtime: dataSource == NetworkMapNearbyPanelDataSource.realtime,
      enabled: true,
      onToggle: () {},
    ),
    onRefreshRealtime: onRefresh == null ? null : (_, _) => onRefresh(),
  );
  return MaterialApp(home: Scaffold(body: content.controlRow));
}

void main() {
  testWidgets('실시간 줄은 토글, 받은 시각, 새로고침을 한 줄에 둔다', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _controlRow(
        dataSource: NetworkMapNearbyPanelDataSource.realtime,
        onRefresh: () => refreshes += 1,
      ),
    );

    expect(find.byType(NearbyDataSourceToggle), findsOneWidget);
    final time = tester.widget<Text>(find.text('오전 12:37'));
    expect(time.style!.color, EasySubwayAccessibleColors.contentSecondary);
    expect(
      tester.getCenter(find.text('오전 12:37')).dx,
      greaterThan(tester.getCenter(find.byType(NearbyDataSourceToggle)).dx),
    );
    await tester.tap(find.byTooltip('새로고침'));
    expect(refreshes, 1);
  });

  testWidgets('받은 시각을 해석할 수 없으면 시각만 숨긴다', (tester) async {
    await tester.pumpWidget(
      _controlRow(
        dataSource: NetworkMapNearbyPanelDataSource.realtime,
        receivedAt: '방금',
        onRefresh: () {},
      ),
    );

    expect(find.textContaining('오전'), findsNothing);
    expect(find.textContaining('오후'), findsNothing);
    expect(find.text('방금'), findsNothing);
    expect(find.byTooltip('새로고침'), findsOneWidget);
  });

  testWidgets('시간표일 때는 받은 시각과 새로고침이 없다', (tester) async {
    await tester.pumpWidget(
      _controlRow(
        dataSource: NetworkMapNearbyPanelDataSource.timetable,
        onRefresh: () {},
      ),
    );

    expect(find.byType(NearbyDataSourceToggle), findsOneWidget);
    expect(find.text('오전 12:37'), findsNothing);
    expect(find.byTooltip('새로고침'), findsNothing);
  });

  testWidgets('받은 시각은 스크린리더가 읽는 시각으로 알린다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _controlRow(
        dataSource: NetworkMapNearbyPanelDataSource.realtime,
        onRefresh: () {},
      ),
    );

    expect(find.bySemanticsLabel('오전 12시 37분 기준'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('글자 2.0배에서도 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _controlRow(
          dataSource: NetworkMapNearbyPanelDataSource.realtime,
          onRefresh: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('글자 1.5배, 412dp에서 받은 시각을 자르지 않고 한 줄로 쓴다', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 800),
          textScaler: TextScaler.linear(1.5),
        ),
        child: _controlRow(
          dataSource: NetworkMapNearbyPanelDataSource.realtime,
          onRefresh: () {},
        ),
      ),
    );

    final time = tester.renderObject<RenderParagraph>(find.text('오전 12:37'));
    expect(time.didExceedMaxLines, isFalse);
    expect(time.size.height, lessThan(15 * 1.5 * 2));
  });
}
