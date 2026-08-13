import 'dart:io';

import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_svg_viewport.dart';
import 'package:easysubway_mobile/features/network_map/application/network_map_nearby_panel_state.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_nearby_panel_content.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 420, height: 720, child: child)),
);

const _line = StationSearchLine(
  id: 'line-1',
  name: '수도권 1호선',
  color: '#0052A4',
  stationCode: '101',
);

const _focusedStation = StationSearchResult(
  id: 'station-center',
  nameKo: '가운데',
  nameEn: 'Center',
  region: '수도권',
  dataQualityLevel: 'VERIFIED',
  lastVerifiedAt: '2026-08-13T00:00:00Z',
  lines: [_line],
);

NetworkMapStation _station(String id, String name, int x, int sequence) {
  return NetworkMapStation(
    id: id,
    nameKo: name,
    nameEn: name,
    region: '수도권',
    lineId: 'line-1',
    stationCode: '$sequence',
    sequence: sequence,
    position: NetworkMapPosition(
      x: x,
      y: 200,
      labelDx: 0,
      labelDy: 0,
      upPath: '',
      downPath: '',
      sourceId: 'fixture',
    ),
  );
}

final _mapData = NetworkMapData(
  regions: [NetworkMapRegion(name: '수도권')],
  selectedRegion: '수도권',
  lines: [
    NetworkMapLine(
      id: 'line-1',
      name: '수도권 1호선',
      color: '#0052A4',
      region: '수도권',
    ),
  ],
  stations: [
    _station('station-left', '이전', 100, 1),
    _station('station-center', '가운데', 200, 2),
    _station('station-right', '다음', 300, 3),
  ],
  edges: [
    NetworkMapEdge(
      id: 'left-center',
      lineId: 'line-1',
      fromStationId: 'station-left:line-1',
      toStationId: 'station-center:line-1',
      accessibilityStatus: 'AVAILABLE',
      reliabilityScore: 100,
    ),
    NetworkMapEdge(
      id: 'center-right',
      lineId: 'line-1',
      fromStationId: 'station-center:line-1',
      toStationId: 'station-right:line-1',
      accessibilityStatus: 'AVAILABLE',
      reliabilityScore: 100,
    ),
  ],
  positionSources: [
    NetworkMapPositionSource(
      id: 'fixture',
      name: '주변역 content test fixture',
      licenseStatus: 'fixture-only',
    ),
  ],
);

final class _MapRepository implements NetworkMapRepository {
  const _MapRepository();

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return _mapData;
  }
}

void main() {
  setUp(() {
    debugRouteMapSvgViewportPresentImmediately = true;
    primeNetworkMapOwnerLabelsCacheForTest(const {});
  });
  tearDown(() {
    debugRouteMapSvgViewportPresentImmediately = false;
    resetNetworkMapOwnerLabelsCacheForTest();
  });

  testWidgets('idle·loading은 success builder 없이 132px indicator를 보존한다', (
    tester,
  ) async {
    for (final status in [
      NetworkMapNearbyPanelStatus.idle,
      NetworkMapNearbyPanelStatus.loading,
    ]) {
      var successBuildCount = 0;
      await tester.pumpWidget(
        _host(
          NetworkMapNearbyPanelContent(
            status: status,
            successBuilder: (context) {
              successBuildCount += 1;
              return (
                stationBar: const SizedBox(key: Key('stationBar')),
                dataPanel: const SizedBox(key: Key('dataPanel')),
              );
            },
          ),
        ),
      );

      expect(successBuildCount, 0);
      final content = find.byType(NetworkMapNearbyPanelContent);
      final loadingFinder = find.descendant(
        of: content,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 132,
        ),
      );
      expect(loadingFinder, findsOneWidget);
      final loading = tester.widget<SizedBox>(loadingFinder);
      expect(loading.height, 132);
      expect(
        find.descendant(
          of: content,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('success는 station bar·gap·padded data panel을 한 번 조합한다', (
    tester,
  ) async {
    var successBuildCount = 0;
    await tester.pumpWidget(
      _host(
        NetworkMapNearbyPanelContent(
          status: NetworkMapNearbyPanelStatus.success,
          successBuilder: (context) {
            successBuildCount += 1;
            return (
              stationBar: const SizedBox(key: Key('stationBar'), height: 48),
              dataPanel: const SizedBox(key: Key('dataPanel'), height: 72),
            );
          },
        ),
      ),
    );

    expect(successBuildCount, 1);
    expect(find.byKey(const Key('stationBar')), findsOneWidget);
    expect(find.byKey(const Key('dataPanel')), findsOneWidget);
    final gapFinder = find.descendant(
      of: find.byType(NetworkMapNearbyPanelContent),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 17,
      ),
    );
    expect(gapFinder, findsOneWidget);
    final gap = tester.widget<SizedBox>(gapFinder);
    expect(gap.height, 17);
    final padding = tester.widget<Padding>(
      find.ancestor(
        of: find.byKey(const Key('dataPanel')),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(24, 0, 24, 12));
  });

  test('root는 public content owner를 쓰고 private content class가 없다', () {
    final root = File('lib/app/network_map_screen.dart').readAsStringSync();
    expect(
      root,
      contains(
        "import 'features/network_map/presentation/network_map_nearby_panel_content.dart';",
      ),
    );
    expect(root, contains('NetworkMapNearbyPanelContent('));
    expect(root, isNot(contains('class _NetworkMapNearbyPanelBody')));
    expect(root, isNot(contains('class _NetworkMapNearbySuccessList')));
  });

  testWidgets('root success content는 좌우 인접역 tap callback을 연결한다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final routeDraftController = RouteDraftController();
    addTearDown(routeDraftController.dispose);
    StationSearchResult? focusStationRequest;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return NetworkMapScreen(
              repository: const _MapRepository(),
              routeDraftController: routeDraftController,
              onOpenStationSearch: (_, _) {},
              focusStationRequest: focusStationRequest,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    updateHost(() => focusStationRequest = _focusedStation);
    await tester.pumpAndSettle();

    final left = find.byKey(const Key('nearbyStationLineBarLeftName'));
    final right = find.byKey(const Key('nearbyStationLineBarRightName'));
    expect(left, findsOneWidget);
    expect(right, findsOneWidget);

    await tester.tap(left);
    await tester.pump();
    await tester.tap(right);
    await tester.pump();
  });
}
