import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_camera_policy.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _initialBounds = Rect.fromLTWH(1000, 800, 1200, 900);
const _sourceWidth = 3688.0;
const _sourceHeight = 2972.0;

Rect? _focus(List<Offset> centers) => networkMapLineFocusBounds(
  stationCenters: centers,
  initialBounds: _initialBounds,
  sourceWidth: _sourceWidth,
  sourceHeight: _sourceHeight,
);

const _station = NetworkMapStation(
  id: 'station-focus',
  nameKo: '포커스',
  nameEn: 'Focus',
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
    sourceId: 'line-focus-fixture',
  ),
);

Widget _canvas({
  required NetworkMapLineFocusRequest? focusedLine,
  required ValueChanged<Rect> onViewportChanged,
}) => MaterialApp(
  home: Scaffold(
    body: NetworkMapCanvas(
      data: const NetworkMapData(
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
        positionSources: [],
      ),
      initialViewport: null,
      focusedStationId: null,
      preserveFocusedStationScale: false,
      selectedStationId: null,
      selectionClearRevision: 0,
      focusedLine: focusedLine,
      onSetOrigin: (_) {},
      onSetWaypoint: (_) {},
      onSetDestination: (_) {},
      onClearOrigin: () {},
      onClearWaypoint: () {},
      onClearDestination: () {},
      onViewportChanged: onViewportChanged,
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

  testWidgets('지도에 역이 없는 노선을 고르면 카메라를 옮기지 않는다', (tester) async {
    final viewports = <Rect>[];
    await tester.pumpWidget(
      _canvas(focusedLine: null, onViewportChanged: viewports.add),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _canvas(
        focusedLine: (lineId: 'missing', revision: 1),
        onViewportChanged: viewports.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(viewports, isEmpty);

    await tester.pumpWidget(
      _canvas(
        focusedLine: (lineId: 'seoul-1', revision: 2),
        onViewportChanged: viewports.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(viewports, hasLength(1), reason: '역이 있는 노선은 카메라를 옮긴다');
  });

  test('고른 노선의 모든 역이 여백을 두고 화면 범위 안에 든다', () {
    const centers = [
      Offset(400, 600),
      Offset(1800, 700),
      Offset(2600, 2100),
      Offset(900, 1500),
    ];

    final bounds = _focus(centers)!;

    for (final center in centers) {
      expect(bounds.contains(center), isTrue, reason: '$center');
      expect(
        bounds.deflate(50).contains(center),
        isTrue,
        reason: '$center 가 가장자리에 붙는다',
      );
    }
  });

  test('역이 몰린 짧은 노선은 역 하나를 고를 때보다 더 확대하지 않는다', () {
    const centers = [Offset(2000, 1500), Offset(2060, 1530)];
    final stationFocus = networkMapStationFocusBounds(
      initialBounds: _initialBounds,
      center: const Offset(2030, 1515),
      sourceWidth: _sourceWidth,
      sourceHeight: _sourceHeight,
    );

    final bounds = _focus(centers)!;

    expect(bounds.width, greaterThanOrEqualTo(stationFocus.width));
    expect(bounds.height, greaterThanOrEqualTo(stationFocus.height));
    expect(bounds.contains(centers.first), isTrue);
    expect(bounds.contains(centers.last), isTrue);
  });

  test('지도 가장자리 노선도 지도 밖으로 범위를 잡지 않는다', () {
    const centers = [Offset(10, 20), Offset(300, 40)];

    final bounds = _focus(centers)!;

    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.contains(centers.first), isTrue);
  });

  test('역이 없는 노선은 범위가 없다', () {
    expect(_focus(const []), isNull);
  });
}
