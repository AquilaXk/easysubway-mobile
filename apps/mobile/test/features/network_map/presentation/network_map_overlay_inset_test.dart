import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_camera_policy.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_draft_pin.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu_policy.dart';
import 'package:easysubway_mobile/features/notifications/presentation/new_notification_bar.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _statusBarInset = 24.0;
const _screen = Size(360, 640);

NetworkMapStation _station(String id, int y) => NetworkMapStation(
  id: 'station-$id',
  nameKo: id,
  nameEn: id,
  region: '수도권',
  lineId: 'seoul-1',
  stationCode: id,
  sequence: 1,
  position: NetworkMapPosition(
    x: 160,
    y: y,
    labelDx: 0,
    labelDy: 0,
    upPath: '',
    downPath: '',
    sourceId: 'overlay-inset-fixture',
  ),
);

/// 지도 맨 위에 가까운 역과 맨 아래에 가까운 역 하나씩.
final _topStation = _station('top', 0);
final _bottomStation = _station('bottom', 600);

final _data = NetworkMapData(
  regions: const [NetworkMapRegion(name: '수도권')],
  selectedRegion: '수도권',
  lines: const [
    NetworkMapLine(
      id: 'seoul-1',
      name: '수도권 1호선',
      color: '#0052A4',
      region: '수도권',
    ),
  ],
  stations: [_topStation, _bottomStation],
  edges: const [],
  positionSources: const [
    NetworkMapPositionSource(
      id: 'overlay-inset-fixture',
      name: 'Overlay inset fixture',
      licenseStatus: 'fixture-only',
    ),
  ],
);

/// 경유 칸이 열려 상단바가 3줄이 되는 경로 입력.
RouteDraft _threeRowDraft(String? waypointStationId) => RouteDraft(
  origin: const RouteDraftStation(id: 'origin', nameKo: '출발역'),
  waypoint: waypointStationId == null
      ? null
      : RouteDraftStation(id: waypointStationId, nameKo: '경유역'),
  destination: null,
  lastModifiedAt: null,
);

/// 지도 위에 [NetworkMapTopBar](경유 포함 3줄)와 실제 알림 바를 올린 홈 chrome.
Widget _home({
  required String? waypointStationId,
  required bool noticeBar,
  String? selectedStationId,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: _screen,
        padding: const EdgeInsets.only(top: _statusBarInset),
        textScaler: TextScaler.linear(textScale),
      ),
      child: SizedBox.fromSize(
        size: _screen,
        child: NetworkMapChrome(
          topBar: NetworkMapTopBar(
            regions: const [NetworkMapRegion(name: '수도권')],
            selectedRegion: '수도권',
            onMenuTap: () {},
            onSearchTap: () {},
            onRegionSelected: (_) {},
            routeDraftListenable: ValueNotifier(0),
            routeDraft: () => _threeRowDraft(waypointStationId),
            isWaypointRowVisible: () => true,
            onClearDraft: () {},
            onOpenWaypointSlot: () {},
            onClearOrigin: () {},
            onClearDestination: () {},
            onClearWaypoint: () {},
            onReorderDraft: (_, _) {},
            roleColorForSlot: (_) => Colors.black,
            lineBadgeBuilder: (_, size) => SizedBox.square(dimension: size),
          ),
          disruptionBanner: noticeBar
              ? NewNotificationBar(
                  disruptionChanges: null,
                  hasDisruption: null,
                  hasNotificationItems: true,
                  onOpenInbox: () {},
                )
              : null,
          searchMode: false,
          searchBody: null,
          nearbyPanelVisible: false,
          nearbyPanelExpanded: false,
          nearbyPanel: const SizedBox(),
          nearbyLookupMessage: null,
          onCurrentLocationTap: () {},
          child: NetworkMapCanvas(
            data: _data,
            initialViewport: null,
            focusedStationId: null,
            preserveFocusedStationScale: false,
            selectedStationId: selectedStationId,
            selectionClearRevision: 0,
            waypointStationId: waypointStationId,
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
    ),
  );
}

/// 상단바와 알림 바가 지도 위를 덮는 영역의 아래 끝(화면 좌표).
double _overlayBottom(WidgetTester tester) {
  final topBar = tester.getRect(find.byKey(const Key('networkMapTopBar')));
  final noticeBar = find.byKey(const Key('newNotificationBar'));
  return noticeBar.evaluate().isEmpty
      ? topBar.bottom
      : tester.getRect(noticeBar).bottom;
}

void main() {
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });

  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  for (final textScale in [1.0, 1.5]) {
    testWidgets('3줄 상단바 + 알림 바 아래에서 경유 핀이 오버레이에 가려지지 않는다(글자 $textScale배)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _home(
          waypointStationId: _topStation.id,
          noticeBar: true,
          textScale: textScale,
        ),
      );
      await tester.pumpAndSettle();

      final pin = tester.getRect(
        find.byKey(const Key('networkMapDraftPin-waypoint')),
      );
      expect(
        pin.top,
        greaterThanOrEqualTo(_overlayBottom(tester)),
        reason: '경유 핀 $pin이 상단바·알림 바 밑에 가려집니다.',
      );
    });
  }

  testWidgets('경유 핀이 나중에 놓여도 이미 측정된 오버레이 아래에 놓인다', (tester) async {
    await tester.pumpWidget(_home(waypointStationId: null, noticeBar: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('networkMapDraftPin-waypoint')), findsNothing);

    await tester.pumpWidget(
      _home(waypointStationId: _topStation.id, noticeBar: true),
    );
    await tester.pumpAndSettle();

    final pin = tester.getRect(
      find.byKey(const Key('networkMapDraftPin-waypoint')),
    );
    expect(pin.top, greaterThanOrEqualTo(_overlayBottom(tester)));
  });

  testWidgets('알림 바가 나중에 나타나면 핀이 늘어난 오버레이 아래로 다시 내려온다', (tester) async {
    await tester.pumpWidget(
      _home(waypointStationId: _topStation.id, noticeBar: false),
    );
    await tester.pumpAndSettle();
    final withoutNotice = _overlayBottom(tester);
    final pinWithoutNotice = tester.getRect(
      find.byKey(const Key('networkMapDraftPin-waypoint')),
    );
    expect(pinWithoutNotice.top, greaterThanOrEqualTo(withoutNotice));

    await tester.pumpWidget(
      _home(waypointStationId: _topStation.id, noticeBar: true),
    );
    await tester.pumpAndSettle();

    final withNotice = _overlayBottom(tester);
    expect(withNotice, greaterThan(withoutNotice));
    final pin = tester.getRect(
      find.byKey(const Key('networkMapDraftPin-waypoint')),
    );
    expect(pin.top, greaterThanOrEqualTo(withNotice));
  });

  testWidgets('오버레이에 가려지지 않은 핀은 알림 바가 오가도 움직이지 않는다', (tester) async {
    await tester.pumpWidget(
      _home(waypointStationId: _bottomStation.id, noticeBar: false),
    );
    await tester.pumpAndSettle();
    final pinBefore = tester.getRect(
      find.byKey(const Key('networkMapDraftPin-waypoint')),
    );

    await tester.pumpWidget(
      _home(waypointStationId: _bottomStation.id, noticeBar: true),
    );
    await tester.pumpAndSettle();

    final pinAfter = tester.getRect(
      find.byKey(const Key('networkMapDraftPin-waypoint')),
    );
    expect(pinAfter, pinBefore);
    expect(pinAfter.top, greaterThanOrEqualTo(_overlayBottom(tester)));
  });

  testWidgets('3줄 상단바 + 알림 바 아래에서 팬 메뉴가 오버레이에 가려지지 않는다', (tester) async {
    await tester.pumpWidget(
      _home(
        waypointStationId: null,
        noticeBar: true,
        selectedStationId: _topStation.id,
      ),
    );
    await tester.pumpAndSettle();

    final menu = tester.getRect(
      find.byKey(const Key('networkMapStationSheet')),
    );
    expect(
      menu.top,
      greaterThanOrEqualTo(_overlayBottom(tester)),
      reason: '팬 메뉴 $menu가 상단바·알림 바 밑에 가려집니다.',
    );
  });

  group('networkMapRevealOffsetBelowObscuredTop', () {
    double reveal(List<Offset> anchors, {double obscuredTop = 150}) =>
        networkMapRevealOffsetBelowObscuredTop(
          anchorPoints: anchors,
          extentAboveAnchor: NetworkMapDraftPin.extentAboveAnchor,
          viewportHeight: 600,
          obscuredTop: obscuredTop,
        );

    test('가려진 위젯이 없으면 0이다', () {
      expect(reveal(const []), 0);
      expect(reveal(const [Offset(100, 300)]), 0);
      expect(reveal(const [Offset(100, 150 + 62)]), 0);
    });

    test('가장 위 위젯의 위 끝이 오버레이 아래 끝에 닿을 만큼 민다', () {
      expect(reveal(const [Offset(100, 100)]), 150 - (100 - 62));
      expect(
        reveal(const [Offset(100, 100), Offset(100, 400)]),
        150 - (100 - 62),
      );
    });

    test('가장 아래 앵커가 뷰포트 아래 끝을 넘지 않는 만큼만 민다', () {
      expect(reveal(const [Offset(100, 100), Offset(100, 560)]), 40);
      expect(reveal(const [Offset(100, 100), Offset(100, 640)]), 0);
    });
  });

  group('팬 메뉴 topInset', () {
    test('reveal offset은 메뉴 위 끝을 오버레이 아래 여백까지 내린다', () {
      expect(
        fanMenuRevealOffset(
          menuRect: const Rect.fromLTWH(90, 100, 220, 120),
          viewport: const Size(400, 800),
          topInset: 150,
        ),
        const Offset(0, 62),
      );
      expect(
        fanMenuRevealOffset(
          menuRect: const Rect.fromLTWH(90, 200, 220, 120),
          viewport: const Size(400, 800),
          topInset: 150,
        ),
        Offset.zero,
      );
    });

    test('클램프된 배치도 오버레이 아래에 둔다', () {
      final placement = fanMenuPlacement(
        stationPoint: const Offset(200, 20),
        viewport: const Size(400, 800),
        clampPosition: true,
        topInset: 150,
      );
      expect(placement.top, 150 + kFanMenuViewportMargin);
    });
  });
}
