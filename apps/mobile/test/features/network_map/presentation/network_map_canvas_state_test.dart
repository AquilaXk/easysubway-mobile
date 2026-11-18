import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_popover_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _station = NetworkMapStation(
  id: 'station-canvas',
  nameKo: '캔버스',
  nameEn: 'Canvas',
  region: '수도권',
  lineId: 'seoul-1',
  stationCode: '100',
  sequence: 1,
  position: NetworkMapPosition(
    x: 160,
    y: 160,
    labelDx: 0,
    labelDy: 0,
    upPath: '',
    downPath: '',
    sourceId: 'canvas-state-fixture',
  ),
);

const _data = NetworkMapData(
  regions: [NetworkMapRegion(name: '수도권')],
  selectedRegion: '수도권',
  lines: [
    NetworkMapLine(
      id: 'seoul-1',
      name: '수도권 1호선',
      color: '#0052A4',
      region: '수도권',
    ),
  ],
  stations: [_station],
  edges: [],
  positionSources: [
    NetworkMapPositionSource(
      id: 'canvas-state-fixture',
      name: 'Canvas state fixture',
      licenseStatus: 'fixture-only',
    ),
  ],
  stationLineMemberships: [
    NetworkMapStationLineMembership(
      stationId: 'station-canvas',
      lineId: 'seoul-1',
    ),
  ],
);

const _emptyData = NetworkMapData(
  regions: [NetworkMapRegion(name: '수도권')],
  selectedRegion: '수도권',
  lines: [],
  stations: [],
  edges: [],
  positionSources: [],
);

Widget _host({
  required NetworkMapData data,
  String? selectedStationId,
  String? originStationId,
  String? waypointStationId,
  String? destinationStationId,
  ValueChanged<Rect>? onViewportChanged,
  VoidCallback? onClearOrigin,
  VoidCallback? onClearWaypoint,
  VoidCallback? onClearDestination,
}) => MaterialApp(
  home: Scaffold(
    body: NetworkMapCanvas(
      data: data,
      initialViewport: null,
      focusedStationId: null,
      preserveFocusedStationScale: false,
      selectedStationId: selectedStationId,
      selectionClearRevision: 0,
      originStationId: originStationId,
      waypointStationId: waypointStationId,
      destinationStationId: destinationStationId,
      onSetOrigin: (_) {},
      onSetWaypoint: (_) {},
      onSetDestination: (_) {},
      onClearOrigin: onClearOrigin ?? () {},
      onClearWaypoint: onClearWaypoint ?? () {},
      onClearDestination: onClearDestination ?? () {},
      onViewportChanged: onViewportChanged ?? (_) {},
      onSelectionDismissed: () {},
      onStationTapped: (_) {},
    ),
  ),
);

void main() {
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });

  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  testWidgets('오너 노드 sidecar 로드 실패 시 캐시 무효화 및 에러 리포트를 수행한다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];
    primeNetworkMapOwnerNodesCacheErrorForTest(Exception('오너 노드 로드 실패'));

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(_host(data: _data));
      await tester.pumpAndSettle();
    });

    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, isA<Exception>());
  });

  testWidgets('empty 뒤 같은 크기 non-empty data를 받으면 renderer를 다시 연다', (
    tester,
  ) async {
    await tester.pumpWidget(_host(data: _emptyData));
    await tester.pumpAndSettle();
    expect(find.byType(RouteMapBasemapView), findsNothing);

    await tester.pumpWidget(_host(data: _data));
    await tester.pumpAndSettle();

    expect(find.byType(RouteMapBasemapView), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapStation-canvas-seoul-1')),
      findsOneWidget,
    );
  });

  testWidgets('pointer cancel은 현재 viewport를 flush한다', (tester) async {
    final viewports = <Rect>[];
    await tester.pumpWidget(
      _host(data: _data, onViewportChanged: viewports.add),
    );
    await tester.pumpAndSettle();
    viewports.clear();

    final mapListener = tester
        .widgetList<Listener>(find.byType(Listener))
        .singleWhere(
          (listener) =>
              listener.onPointerCancel != null &&
              listener.child is GestureDetector,
        );
    mapListener.onPointerCancel!(const PointerCancelEvent(pointer: 1));
    await tester.pump();

    expect(viewports, hasLength(1));
  });

  testWidgets('dispose 뒤 cached pointer cancel은 setState 예외를 내지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(_host(data: _data));
    await tester.pumpAndSettle();

    final mapListener = tester
        .widgetList<Listener>(find.byType(Listener))
        .singleWhere(
          (listener) =>
              listener.onPointerCancel != null &&
              listener.child is GestureDetector,
        );
    final mapGesture = mapListener.child! as GestureDetector;
    mapGesture.onScaleStart!(
      ScaleStartDetails(
        focalPoint: Offset(160, 160),
        localFocalPoint: Offset(160, 160),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    mapListener.onPointerCancel!(const PointerCancelEvent(pointer: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  for (final slot in [RouteDraftSlot.waypoint, RouteDraftSlot.destination]) {
    testWidgets('선택된 ${slot.name} 재탭은 exact clear callback만 실행한다', (
      tester,
    ) async {
      var waypointClears = 0;
      var destinationClears = 0;
      await tester.pumpWidget(
        _host(
          data: _data,
          selectedStationId: _station.id,
          waypointStationId: slot == RouteDraftSlot.waypoint
              ? _station.id
              : null,
          destinationStationId: slot == RouteDraftSlot.destination
              ? _station.id
              : null,
          onClearWaypoint: () => waypointClears += 1,
          onClearDestination: () => destinationClears += 1,
        ),
      );
      await tester.pumpAndSettle();

      tester
          .widget<StationPopoverMenu>(find.byType(StationPopoverMenu))
          .onAction(slot);
      await tester.pump();

      expect(waypointClears, slot == RouteDraftSlot.waypoint ? 1 : 0);
      expect(destinationClears, slot == RouteDraftSlot.destination ? 1 : 0);
    });
  }

  testWidgets('확대된 상태에서 focusedStationId를 받으면 scale을 유지하며 포커스한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkMapCanvas(
            data: _data,
            initialViewport: const Rect.fromLTWH(155, 155, 10, 10),
            focusedStationId: null,
            preserveFocusedStationScale: false,
            selectedStationId: null,
            selectionClearRevision: 0,
            originStationId: null,
            waypointStationId: null,
            destinationStationId: null,
            onSetOrigin: (_) {},
            onSetWaypoint: (_) {},
            onSetDestination: (_) {},
            onClearOrigin: () {},
            onClearWaypoint: () {},
            onClearDestination: () {},
            onViewportChanged: (_) {},
            onSelectionDismissed: () {},
            onStationTapped: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkMapCanvas(
            data: _data,
            initialViewport: const Rect.fromLTWH(155, 155, 10, 10),
            focusedStationId: _station.id,
            preserveFocusedStationScale: false,
            selectedStationId: null,
            selectionClearRevision: 0,
            originStationId: null,
            waypointStationId: null,
            destinationStationId: null,
            onSetOrigin: (_) {},
            onSetWaypoint: (_) {},
            onSetDestination: (_) {},
            onClearOrigin: () {},
            onClearWaypoint: () {},
            onClearDestination: () {},
            onViewportChanged: (_) {},
            onSelectionDismissed: () {},
            onStationTapped: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('역 말풍선이 열리거나 대상 역이 바뀌면 liveRegion 시맨틱이 선택 역 메뉴로 갱신된다', (
    tester,
  ) async {
    const secondStation = NetworkMapStation(
      id: 'station-city-hall',
      nameKo: '시청',
      nameEn: 'City Hall',
      region: '수도권',
      lineId: 'seoul-1',
      stationCode: '101',
      sequence: 2,
      position: NetworkMapPosition(
        x: 220,
        y: 160,
        labelDx: 0,
        labelDy: 0,
        upPath: '',
        downPath: '',
        sourceId: 'canvas-state-fixture',
      ),
    );
    const twoStationData = NetworkMapData(
      regions: [NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: [
        NetworkMapLine(
          id: 'seoul-1',
          name: '수도권 1호선',
          color: '#0052A4',
          region: '수도권',
        ),
      ],
      stations: [_station, secondStation],
      edges: [],
      positionSources: [
        NetworkMapPositionSource(
          id: 'canvas-state-fixture',
          name: 'Canvas state fixture',
          licenseStatus: 'fixture-only',
        ),
      ],
      stationLineMemberships: [
        NetworkMapStationLineMembership(
          stationId: 'station-canvas',
          lineId: 'seoul-1',
        ),
        NetworkMapStationLineMembership(
          stationId: 'station-city-hall',
          lineId: 'seoul-1',
        ),
      ],
    );

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(data: twoStationData, selectedStationId: _station.id),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stationPopoverMenu-station-canvas')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('캔버스역 메뉴')),
      isSemantics(hasDismissAction: true, isLiveRegion: true),
    );

    await tester.pumpWidget(
      _host(data: twoStationData, selectedStationId: secondStation.id),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stationPopoverMenu-station-city-hall')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('캔버스역 메뉴'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('시청역 메뉴')),
      isSemantics(hasDismissAction: true, isLiveRegion: true),
    );
    handle.dispose();
  });
}
