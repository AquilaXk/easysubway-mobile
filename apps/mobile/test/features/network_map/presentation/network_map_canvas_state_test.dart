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

      tester.widget<StationFanMenu>(find.byType(StationFanMenu)).onAction(slot);
      await tester.pump();

      expect(waypointClears, slot == RouteDraftSlot.waypoint ? 1 : 0);
      expect(destinationClears, slot == RouteDraftSlot.destination ? 1 : 0);
    });
  }

  testWidgets(
    '핀치 줌인/줌아웃 제스처 중에는 renderer 카메라를 과도하게 재커밋하지 않고 Transform으로 부드럽게 유지한다',
    (tester) async {
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
          focalPoint: const Offset(160, 160),
          localFocalPoint: const Offset(160, 160),
        ),
      );
      await tester.pump();

      final initialBasemap = tester.widget<RouteMapBasemapView>(
        find.byType(RouteMapBasemapView),
      );
      final initialCameraRevision = initialBasemap.camera.revision;

      // 첫 제스처 프레임에서 overscan baseline이 수립된 후(revision 1),
      // 이후 모든 연속 줌아웃/줌인 제스처 동안에는 revision이 고정 유지되어야 한다.
      mapGesture.onScaleUpdate!(
        ScaleUpdateDetails(
          focalPoint: const Offset(160, 160),
          localFocalPoint: const Offset(160, 160),
          scale: 0.95,
        ),
      );
      await tester.pump();
      final gestureBasemap = tester.widget<RouteMapBasemapView>(
        find.byType(RouteMapBasemapView),
      );
      final gestureCameraRevision = gestureBasemap.camera.revision;
      expect(gestureCameraRevision, equals(initialCameraRevision + 1));

      for (final scale in [0.90, 0.85, 0.80]) {
        mapGesture.onScaleUpdate!(
          ScaleUpdateDetails(
            focalPoint: const Offset(160, 160),
            localFocalPoint: const Offset(160, 160),
            scale: scale,
          ),
        );
        await tester.pump();
        final currentBasemap = tester.widget<RouteMapBasemapView>(
          find.byType(RouteMapBasemapView),
        );
        expect(currentBasemap.camera.revision, equals(gestureCameraRevision));
      }

      for (final scale in [1.05, 1.15, 1.25]) {
        mapGesture.onScaleUpdate!(
          ScaleUpdateDetails(
            focalPoint: const Offset(160, 160),
            localFocalPoint: const Offset(160, 160),
            scale: scale,
          ),
        );
        await tester.pump();
        final currentBasemap = tester.widget<RouteMapBasemapView>(
          find.byType(RouteMapBasemapView),
        );
        expect(currentBasemap.camera.revision, equals(gestureCameraRevision));
      }

      final transformFinder = find
          .ancestor(
            of: find.byType(RouteMapBasemapView),
            matching: find.byType(Transform),
          )
          .first;
      final gestureEndTransform = tester.widget<Transform>(transformFinder);
      expect(
        gestureEndTransform.transform.getMaxScaleOnAxis(),
        moreOrLessEquals(4.28, epsilon: 0.1),
      );

      mapGesture.onScaleEnd!(ScaleEndDetails());
      await tester.pump();

      final finalBasemap = tester.widget<RouteMapBasemapView>(
        find.byType(RouteMapBasemapView),
      );
      expect(finalBasemap.camera.revision, greaterThan(gestureCameraRevision));

      // 제스처 종료 후 WebView가 새 프레임을 렌더링해 onFramePresented 콜백을 호출하기 전까지는
      // Transform이 화면에 유지되어 덜컥거림/스냅백(Jitter)을 방지한다.
      final pendingTransform = tester.widget<Transform>(transformFinder);
      expect(pendingTransform.transform.isIdentity(), isFalse);
      expect(
        pendingTransform.transform.getMaxScaleOnAxis(),
        equals(gestureEndTransform.transform.getMaxScaleOnAxis()),
      );

      // WebView에서 새 프레임 렌더링이 완료되어 onFramePresented가 호출되면
      // _presentedRendererCamera가 갱신되어 Transform이 새 overscan baseline으로 정돈된다.
      finalBasemap.onFramePresented!(finalBasemap.camera.revision);
      await tester.pump();

      final settledTransform = tester.widget<Transform>(transformFinder);
      expect(
        settledTransform.transform.getMaxScaleOnAxis(),
        moreOrLessEquals(3.25, epsilon: 0.05),
      );
    },
  );
}
