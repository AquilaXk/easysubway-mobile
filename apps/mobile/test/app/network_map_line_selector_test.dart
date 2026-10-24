import 'dart:async';

import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/application/network_map_region_bridge.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_viewport.dart';

NetworkMapStation _station(
  String id,
  String lineId,
  int sequence,
  int x,
  int y,
) => NetworkMapStation(
  id: 'station-$id',
  nameKo: id,
  nameEn: id,
  region: '수도권',
  lineId: lineId,
  stationCode: '$sequence',
  sequence: sequence,
  position: NetworkMapPosition(
    x: x,
    y: y,
    labelDx: 0,
    labelDy: 0,
    upPath: '',
    downPath: '',
    sourceId: 'line-selector-fixture',
  ),
);

/// 수도권 노선 셋. 1호선 44역이 지도 가운데를 차지하고(40역이 넘는 지역은 처음에
/// 가운데를 확대해 연다), 우이신설 역은 오른쪽 아래 끝이라 처음 화면 밖이다.
const _seoulLineStationCount = 44;

final _data = NetworkMapData(
  regions: const [NetworkMapRegion(name: '수도권')],
  selectedRegion: '수도권',
  lines: const [
    NetworkMapLine(
      id: 'seoul-1',
      name: '수도권 1호선',
      color: '#0052a4',
      region: '수도권',
    ),
    NetworkMapLine(
      id: 'ui-sinseol',
      name: '수도권 우이신설',
      color: '#b0ce18',
      region: '수도권',
    ),
    NetworkMapLine(
      id: 'airport',
      name: '수도권 공항',
      color: '#0090d2',
      region: '수도권',
    ),
  ],
  stations: [
    for (var index = 0; index < _seoulLineStationCount; index++)
      _station('s$index', 'seoul-1', index + 1, 1000 + index * 45, 1500),
    _station('b1', 'airport', 1, 200, 200),
    _station('b2', 'airport', 2, 400, 260),
    _station('c1', 'ui-sinseol', 1, 3500, 2800),
    _station('c2', 'ui-sinseol', 2, 3650, 2950),
  ],
  edges: const [],
  positionSources: const [],
);

class _Repository implements NetworkMapRepository {
  _Repository([Future<NetworkMapData>? pending]) : _pending = pending;

  final Future<NetworkMapData>? _pending;

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) =>
      _pending ?? Future.value(_data);
}

final _busanData = NetworkMapData(
  regions: const [
    NetworkMapRegion(name: '수도권'),
    NetworkMapRegion(name: '부산'),
  ],
  selectedRegion: '부산',
  lines: const [
    NetworkMapLine(
      id: 'busan-1',
      name: '부산 1호선',
      color: '#f06a00',
      region: '부산',
    ),
  ],
  stations: [
    _station('d1', 'busan-1', 1, 300, 300),
    _station('d2', 'busan-1', 2, 700, 400),
  ],
  edges: const [],
  positionSources: const [],
);

/// 지역 이름으로 수도권과 부산 노선도를 돌려준다.
class _TwoRegionRepository implements NetworkMapRepository {
  @override
  Future<NetworkMapData> getNetworkMap({
    String? region,
    String? lineId,
  }) async => region == '부산'
      ? _busanData
      : _data.copyWith(
          regions: const [
            NetworkMapRegion(name: '수도권'),
            NetworkMapRegion(name: '부산'),
          ],
        );
}

Widget _screen(
  NetworkMapRepository repository, {
  NetworkMapRegionBridge? regionBridge,
}) => MaterialApp(
  home: Scaffold(
    body: NetworkMapScreen(
      repository: repository,
      routeDraftController: RouteDraftController(),
      onOpenStationSearch: (_, _) {},
      regionBridge: regionBridge,
    ),
  ),
);

Finder _chip(String lineId) => find.byKey(Key('routeMapLineChip-$lineId'));
final _strip = find.byKey(const Key('routeMapLineStrip'));

Finder _stationTarget(String id, String lineId) =>
    find.byKey(Key('networkMapStation-$id-$lineId'));

Matcher _selected(bool selected) =>
    isSemantics(isButton: true, isSelected: selected);

Future<void> _pickInSheet(WidgetTester tester, Finder cell) async {
  await tester.tap(find.byKey(const Key('routeMapLineSheetButton')));
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

/// 노선 줄 아래 지도에서 보이는 곳.
Rect _visibleMap(WidgetTester tester) {
  final screen = Offset.zero & tester.view.physicalSize / 3.0;
  return Rect.fromLTRB(
    0,
    tester.getRect(_strip).bottom,
    screen.width,
    screen.height,
  );
}

bool _inView(WidgetTester tester, Finder target) =>
    target.evaluate().isNotEmpty &&
    _visibleMap(tester).contains(tester.getCenter(target));

void main() {
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });

  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  testWidgets('노선도를 불러오는 동안에는 노선 줄을 그리지 않는다', (tester) async {
    final pending = Completer<NetworkMapData>();
    await tester.pumpWidget(_screen(_Repository(pending.future)));
    await tester.pump();

    expect(_strip, findsNothing);

    pending.complete(_data);
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    expect(_chip('seoul-1'), findsOneWidget);
    expect(_chip('airport'), findsOneWidget);
    expect(_chip('ui-sinseol'), findsOneWidget);
  });

  testWidgets('시트에서 고른 노선이 노선 줄에서 선택되고 지도가 그 노선 역을 보인다', (tester) async {
    useLogicalViewport(tester, const Size(393, 852));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_screen(_Repository()));
    await tester.pumpAndSettle();
    expect(
      _inView(tester, _stationTarget('c1', 'ui-sinseol')),
      isFalse,
      reason: '우이신설 역은 처음 화면 밖이다',
    );

    await _pickInSheet(
      tester,
      find.byKey(const Key('routeMapLineSheetCell-ui-sinseol')),
    );

    expect(tester.getSemantics(_chip('ui-sinseol')), _selected(true));
    expect(tester.getSemantics(_chip('seoul-1')), _selected(false));
    expect(_inView(tester, _stationTarget('c1', 'ui-sinseol')), isTrue);
    expect(_inView(tester, _stationTarget('c2', 'ui-sinseol')), isTrue);
    semantics.dispose();
  });

  testWidgets('칩을 누르면 그 노선으로 가고 전체 노선은 고른 노선을 비운다', (tester) async {
    useLogicalViewport(tester, const Size(393, 852));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_screen(_Repository()));
    await tester.pumpAndSettle();

    expect(
      _inView(tester, _stationTarget('b1', 'airport')),
      isFalse,
      reason: '공항 역은 처음 화면 밖이다',
    );

    await tester.tap(_chip('airport'));
    await tester.pumpAndSettle();

    expect(tester.getSemantics(_chip('airport')), _selected(true));
    expect(_inView(tester, _stationTarget('b1', 'airport')), isTrue);
    expect(_inView(tester, _stationTarget('b2', 'airport')), isTrue);

    await _pickInSheet(tester, find.byKey(const Key('routeMapLineSheetAll')));

    expect(tester.getSemantics(_chip('airport')), _selected(false));
    expect(tester.getSemantics(_chip('seoul-1')), _selected(false));
    semantics.dispose();
  });

  testWidgets('지도를 옮긴 뒤 같은 칩을 다시 누르면 그 노선으로 돌아간다', (tester) async {
    useLogicalViewport(tester, const Size(393, 852));
    await tester.pumpWidget(_screen(_Repository()));
    await tester.pumpAndSettle();
    await tester.tap(_chip('airport'));
    await tester.pumpAndSettle();
    expect(_inView(tester, _stationTarget('b1', 'airport')), isTrue);

    await tester.dragFrom(const Offset(200, 500), const Offset(-900, -900));
    await tester.pumpAndSettle();
    expect(
      _inView(tester, _stationTarget('b1', 'airport')),
      isFalse,
      reason: '지도를 옮겨 공항 역이 화면 밖으로 나갔다',
    );

    await tester.tap(_chip('airport'));
    await tester.pumpAndSettle();

    expect(_inView(tester, _stationTarget('b1', 'airport')), isTrue);
    expect(_inView(tester, _stationTarget('b2', 'airport')), isTrue);
  });

  testWidgets('다른 지역에 다녀오면 고른 노선은 비어 있다', (tester) async {
    final semantics = tester.ensureSemantics();
    final bridge = NetworkMapRegionBridge();
    await tester.pumpWidget(
      _screen(_TwoRegionRepository(), regionBridge: bridge),
    );
    await tester.pumpAndSettle();
    await tester.tap(_chip('ui-sinseol'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(_chip('ui-sinseol')), _selected(true));

    bridge.selectRegion('부산');
    await tester.pumpAndSettle();
    expect(_chip('busan-1'), findsOneWidget);
    expect(_chip('ui-sinseol'), findsNothing);

    bridge.selectRegion('수도권');
    await tester.pumpAndSettle();

    expect(tester.getSemantics(_chip('ui-sinseol')), _selected(false));
    semantics.dispose();
  });
}
