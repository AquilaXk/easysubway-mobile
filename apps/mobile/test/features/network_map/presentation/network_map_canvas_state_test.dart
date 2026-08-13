import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_svg_viewport.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
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
    debugRouteMapSvgViewportPresentImmediately = true;
    primeNetworkMapOwnerLabelsCacheForTest(const {});
  });

  tearDown(() {
    debugRouteMapSvgViewportPresentImmediately = false;
    resetNetworkMapOwnerLabelsCacheForTest();
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

      tester.widget<StationFanMenu>(find.byType(StationFanMenu)).onAction(slot);
      await tester.pump();

      expect(waypointClears, slot == RouteDraftSlot.waypoint ? 1 : 0);
      expect(destinationClears, slot == RouteDraftSlot.destination ? 1 : 0);
    });
  }
}
