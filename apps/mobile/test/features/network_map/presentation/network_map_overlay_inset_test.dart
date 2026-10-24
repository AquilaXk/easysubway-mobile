import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_camera_policy.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_chrome_controls.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_draft_pin.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_overlay_inset.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu_policy.dart';
import 'package:easysubway_mobile/features/notifications/presentation/new_notification_bar.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/network_map_visible_center.dart';

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

final _data = _dataWith([_topStation, _bottomStation]);

NetworkMapData _dataWith(List<NetworkMapStation> stations) => NetworkMapData(
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
  stations: stations,
  edges: const [],
  positionSources: const [
    NetworkMapPositionSource(
      id: 'overlay-inset-fixture',
      name: 'Overlay inset fixture',
      licenseStatus: 'fixture-only',
    ),
  ],
);

/// 화면보다 큰 지도라 카메라가 경계에 걸리지 않고 가운데 역을 중앙에 둘 수 있다.
/// 저장 viewport 복원 조건(지도 폭의 2배 이내)을 넘지 않을 만큼만 크다.
final _middleStation = _station('middle', 700);
final _tallData = _dataWith([
  _topStation,
  _middleStation,
  _station('end', 1400),
]);

/// 경유 칸이 열려 상단바가 3줄이 되는 경로 입력.
RouteDraft _threeRowDraft(String? waypointStationId) => RouteDraft(
  origin: const RouteDraftStation(id: 'origin', nameKo: '출발역'),
  waypoint: waypointStationId == null
      ? null
      : RouteDraftStation(id: waypointStationId, nameKo: '경유역'),
  destination: null,
  lastModifiedAt: null,
);

/// 지도 위에 [NetworkMapTopBar]와 알림 바를 올린 홈 chrome.
///
/// [threeRows]가 거짓이면 상단바는 검색 1줄이다. [noticeBarHeight]를 주면 실제 알림
/// 바 대신 그 높이의 막대를 쓴다(큰 글자에서 알림 바가 커지는 경우를 흉내 낸다).
Widget _home({
  String? waypointStationId,
  bool noticeBar = true,
  bool threeRows = true,
  String? selectedStationId,
  double textScale = 1.0,
  double? noticeBarHeight,
  String? focusedStationId,
  bool preserveFocusedStationScale = false,
  NetworkMapData? data,
  Rect? initialViewport,
  ValueChanged<Rect>? onViewportChanged,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
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
            routeDraft: () => threeRows
                ? _threeRowDraft(waypointStationId)
                : const RouteDraft.empty(),
            isWaypointRowVisible: () => threeRows,
            onClearDraft: () {},
            onOpenWaypointSlot: () {},
            onClearOrigin: () {},
            onClearDestination: () {},
            onClearWaypoint: () {},
            onReorderDraft: (_, _) {},
            roleColorForSlot: (_) => Colors.black,
          ),
          disruptionBanner: !noticeBar
              ? null
              : noticeBarHeight != null
              ? SizedBox(
                  key: const Key('newNotificationBar'),
                  height: noticeBarHeight,
                )
              : NewNotificationBar(
                  disruptionChanges: null,
                  hasDisruption: null,
                  hasNotificationItems: true,
                  onOpenInbox: () {},
                ),
          searchMode: false,
          searchBody: null,
          nearbyPanelVisible: false,
          nearbyPanelExpanded: false,
          nearbyPanel: const SizedBox(),
          nearbyLookupMessage: null,
          onCurrentLocationTap: () {},
          child: NetworkMapCanvas(
            data: data ?? _data,
            initialViewport: initialViewport,
            focusedStationId: focusedStationId,
            preserveFocusedStationScale: preserveFocusedStationScale,
            selectedStationId: selectedStationId,
            selectionClearRevision: 0,
            waypointStationId: waypointStationId,
            onSetOrigin: (_) {},
            onSetWaypoint: (_) {},
            onSetDestination: (_) {},
            onClearOrigin: () {},
            onClearWaypoint: () {},
            onClearDestination: () {},
            onViewportChanged: onViewportChanged ?? (_) {},
            onSelectionDismissed: () {},
            onStationTapped: (_) {},
          ),
        ),
      ),
    ),
  );
}

const _waypointPin = Key('networkMapDraftPin-waypoint');

/// [home]을 그리고 모든 프레임이 끝날 때까지 기다린다.
Future<void> _show(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(home);
  await tester.pumpAndSettle();
}

Rect _pinRect(WidgetTester tester) => tester.getRect(find.byKey(_waypointPin));

void _expectPinBelowOverlay(WidgetTester tester) {
  final pin = _pinRect(tester);
  expect(
    pin.top,
    greaterThanOrEqualTo(networkMapOverlayBottomOf(tester)),
    reason: '경유 핀 $pin이 상단바·알림 바 밑에 가려집니다.',
  );
}

/// 지도 위쪽(핀이 없는 빈 곳)에서 손가락을 대고 [by]만큼 끌어 제스처를 시작한다.
/// 반환된 제스처를 놓기 전까지 지도는 제스처 중이다.
Future<TestGesture> _startMapDrag(WidgetTester tester, Offset by) async {
  final gesture = await tester.startGesture(const Offset(300, 400));
  await gesture.moveBy(by);
  await tester.pump();
  return gesture;
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

  group('지정한 대상은 오버레이 아래에 놓인다', () {
    for (final textScale in [1.0, 1.5]) {
      testWidgets('경유 핀을 지정하면 3줄 상단바 + 알림 바 아래로 내려온다(글자 $textScale배)', (
        tester,
      ) async {
        await _show(tester, _home(textScale: textScale));
        expect(find.byKey(_waypointPin), findsNothing);

        await _show(
          tester,
          _home(waypointStationId: _topStation.id, textScale: textScale),
        );

        _expectPinBelowOverlay(tester);
      });
    }

    testWidgets('역 말풍선을 열면 3줄 상단바 + 알림 바 아래로 내려온다', (tester) async {
      await _show(tester, _home(selectedStationId: _topStation.id));

      final menu = tester.getRect(
        find.byKey(const Key('networkMapStationSheet')),
      );
      expect(menu.top, greaterThanOrEqualTo(networkMapOverlayBottomOf(tester)));
    });

    testWidgets('가려지지 않는 핀은 지정해도 카메라가 움직이지 않는다', (tester) async {
      await _show(tester, _home());
      await _show(tester, _home(waypointStationId: _bottomStation.id));
      final pin = _pinRect(tester);

      await _show(tester, _home(waypointStationId: _bottomStation.id));

      expect(_pinRect(tester), pin);
      _expectPinBelowOverlay(tester);
    });
  });

  group('오버레이가 커지면 마지막 지정 핀을 따라 내려온다', () {
    /// 1줄 상단바(알림 바 없음)에서 경유 핀을 지정한 상태.
    Future<void> designateUnderOneRowBar(WidgetTester tester) async {
      await _show(tester, _home(threeRows: false, noticeBar: false));
      await _show(
        tester,
        _home(
          waypointStationId: _topStation.id,
          threeRows: false,
          noticeBar: false,
        ),
      );
    }

    testWidgets('알림 바가 나타나면 사용자가 지도를 움직이지 않은 핀이 내려온다', (tester) async {
      await designateUnderOneRowBar(tester);
      final before = _pinRect(tester);

      await _show(
        tester,
        _home(
          waypointStationId: _topStation.id,
          threeRows: false,
          noticeBar: true,
        ),
      );

      expect(_pinRect(tester).top, greaterThan(before.top));
      _expectPinBelowOverlay(tester);
    });

    testWidgets('상단바가 1줄에서 3줄로 늘어도 같은 규칙으로 내려온다', (tester) async {
      await designateUnderOneRowBar(tester);
      final before = _pinRect(tester);

      await _show(
        tester,
        _home(waypointStationId: _topStation.id, noticeBar: false),
      );

      expect(_pinRect(tester).top, greaterThan(before.top));
      _expectPinBelowOverlay(tester);
    });

    testWidgets('사용자가 지도를 움직인 뒤에는 오버레이가 커져도 그 위치를 존중한다', (tester) async {
      await designateUnderOneRowBar(tester);
      final gesture = await _startMapDrag(tester, const Offset(0, 40));
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = _pinRect(tester);

      await _show(tester, _home(waypointStationId: _topStation.id));

      expect(_pinRect(tester), moved);
      expect(
        moved.top,
        lessThan(networkMapOverlayBottomOf(tester)),
        reason: '움직인 핀은 가려진 채 둔다',
      );
    });

    testWidgets('알림 바가 깜빡여도 카메라가 한쪽으로 쌓이지 않는다', (tester) async {
      await designateUnderOneRowBar(tester);
      await _show(tester, _home(waypointStationId: _topStation.id));
      final settled = _pinRect(tester);

      for (var i = 0; i < 2; i++) {
        await _show(
          tester,
          _home(waypointStationId: _topStation.id, noticeBar: false),
        );
        await _show(tester, _home(waypointStationId: _topStation.id));
      }

      expect(_pinRect(tester).top, closeTo(settled.top, 0.01));
    });
  });

  group('오버레이가 줄어들거나 처음 측정될 때는 움직이지 않는다', () {
    testWidgets('알림 바가 사라져도 카메라가 그대로다', (tester) async {
      await _show(tester, _home());
      await _show(tester, _home(waypointStationId: _topStation.id));
      final pin = _pinRect(tester);

      await _show(
        tester,
        _home(waypointStationId: _topStation.id, noticeBar: false),
      );

      expect(_pinRect(tester), pin);
    });

    testWidgets('상단바가 3줄에서 1줄로 줄어도 카메라가 그대로다', (tester) async {
      await _show(tester, _home());
      await _show(tester, _home(waypointStationId: _topStation.id));
      final pin = _pinRect(tester);

      await _show(
        tester,
        _home(
          waypointStationId: _topStation.id,
          threeRows: false,
          noticeBar: false,
        ),
      );

      expect(_pinRect(tester), pin);
    });

    testWidgets('핀이 있는 채 처음 열릴 때(저장 위치 복원)는 첫 측정으로 움직이지 않는다', (tester) async {
      await tester.pumpWidget(_home(waypointStationId: _topStation.id));
      await tester.pump(); // 측정 전 첫 프레임에는 지도를 그리지 않는다.
      final firstFrame = _pinRect(tester);
      await tester.pumpAndSettle();

      expect(_pinRect(tester), firstFrame);
    });
  });

  group('제스처와 클램프', () {
    testWidgets('제스처 중에 핀을 지정해도 카메라를 움직이지 않는다', (tester) async {
      await _show(tester, _home());
      final gesture = await _startMapDrag(tester, const Offset(0, 40));

      await tester.pumpWidget(_home(waypointStationId: _topStation.id));
      await tester.pumpAndSettle();

      expect(
        _pinRect(tester).top,
        lessThan(networkMapOverlayBottomOf(tester)),
        reason: '제스처 중에는 사용자가 조작한 위치를 우선한다',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        _pinRect(tester).top,
        lessThan(networkMapOverlayBottomOf(tester)),
        reason: '제스처가 끝나도 다시 시도하지 않는다',
      );
    });

    testWidgets('제스처 중에 지정한 핀은 제스처가 끝난 뒤 오버레이가 커져도 움직이지 않는다', (tester) async {
      await _show(tester, _home(threeRows: false, noticeBar: false));
      final gesture = await _startMapDrag(tester, const Offset(0, 40));
      await tester.pumpWidget(
        _home(
          waypointStationId: _topStation.id,
          threeRows: false,
          noticeBar: false,
        ),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      await _show(tester, _home(waypointStationId: _topStation.id));

      expect(_pinRect(tester).top, lessThan(networkMapOverlayBottomOf(tester)));
    });

    testWidgets('reveal이 옮긴 카메라를 이어지는 드래그가 되돌려 핀을 다시 가리지 않는다', (tester) async {
      // 큰 글자에서 알림 바가 커진 상황. 핀을 내리는 거리가 기본 여유(220dp)를 넘는다.
      const tallNoticeBar = 300.0;
      await _show(tester, _home(noticeBarHeight: tallNoticeBar));
      await _show(
        tester,
        _home(
          waypointStationId: _topStation.id,
          noticeBarHeight: tallNoticeBar,
        ),
      );
      _expectPinBelowOverlay(tester);

      final gesture = await _startMapDrag(tester, const Offset(0, 60));
      await gesture.up();
      await tester.pumpAndSettle();
      _expectPinBelowOverlay(tester);
    });
  });

  testWidgets('측정이 한 프레임 늦어도 몇 프레임 안에 핀이 오버레이 아래로 내려온다', (tester) async {
    await _show(tester, _home());

    await tester.pumpWidget(_home(waypointStationId: _topStation.id));
    var framesUntilVisible = 0;
    while (_pinRect(tester).top < networkMapOverlayBottomOf(tester)) {
      await tester.pump();
      framesUntilVisible++;
      expect(framesUntilVisible, lessThan(4), reason: '핀이 계속 가려져 있습니다');
    }

    expect(framesUntilVisible, greaterThan(0), reason: '지정한 프레임에는 아직 가려져 있다');
  });

  group('초기 카메라와 포커스는 오버레이 아래 보이는 영역을 기준으로 한다', () {
    /// 폰 크기(360x640) 화면에서 실행한다. 테스트 기본 화면(800x600)은 지도가 너무
    /// 작게 그려져 저장 viewport 복원 조건을 넘는다.
    void testPhone(
      String name,
      Future<void> Function(WidgetTester tester) body,
    ) => testWidgets(name, (tester) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(tester);
    });

    /// 포커스한 역이 놓인 화면 y. 핀 끝이 역 중심이다.
    double stationY(WidgetTester tester) => _pinRect(tester).bottom;

    Widget focusMiddle({
      bool noticeBar = true,
      bool threeRows = true,
      double textScale = 1.0,
      Rect? initialViewport,
      ValueChanged<Rect>? onViewportChanged,
    }) => _home(
      data: _tallData,
      waypointStationId: _middleStation.id,
      focusedStationId: _middleStation.id,
      noticeBar: noticeBar,
      threeRows: threeRows,
      textScale: textScale,
      initialViewport: initialViewport,
      onViewportChanged: onViewportChanged,
    );

    for (final textScale in [1.0, 1.5]) {
      testPhone('포커스 역이 3줄 상단바 + 알림 바 아래 보이는 영역 중앙에 놓인다(글자 $textScale배)', (
        tester,
      ) async {
        await _show(tester, focusMiddle(textScale: textScale));

        expect(
          stationY(tester),
          closeTo(networkMapVisibleCenterYOf(tester), 1.0),
        );
      });
    }

    for (final (name, threeRows, noticeBar) in [
      ('1줄 상단바, 알림 바 없음', false, false),
      ('1줄 상단바 + 알림 바', false, true),
      ('3줄 상단바, 알림 바 없음', true, false),
    ]) {
      testPhone('포커스 역이 보이는 영역 중앙에 놓인다($name)', (tester) async {
        await _show(
          tester,
          focusMiddle(threeRows: threeRows, noticeBar: noticeBar),
        );

        expect(
          stationY(tester),
          closeTo(networkMapVisibleCenterYOf(tester), 1.0),
        );
      });
    }

    testPhone('오버레이가 없는 지도는 지도 본문 전체의 중앙에 놓는다', (tester) async {
      await _show(
        tester,
        MaterialApp(
          home: SizedBox.fromSize(
            size: _screen,
            child: NetworkMapCanvas(
              data: _tallData,
              initialViewport: null,
              focusedStationId: _middleStation.id,
              preserveFocusedStationScale: false,
              selectedStationId: null,
              selectionClearRevision: 0,
              waypointStationId: _middleStation.id,
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

      final surface = tester.getRect(
        find.byKey(const Key('networkMapSurface')),
      );
      expect(stationY(tester), closeTo(surface.center.dy, 1.0));
    });

    testPhone('측정 전 첫 프레임에는 지도를 그리지 않고, 측정 뒤 한 번에 제자리에 그린다', (tester) async {
      await tester.pumpWidget(focusMiddle());
      expect(
        find.byKey(_waypointPin),
        findsNothing,
        reason: '측정 전에는 카메라를 확정하지 않는다',
      );

      await tester.pump();
      final firstDrawn = stationY(tester);
      expect(firstDrawn, closeTo(networkMapVisibleCenterYOf(tester), 1.0));

      await tester.pumpAndSettle();
      expect(stationY(tester), firstDrawn, reason: '첫 그림 이후 점프하지 않는다');
    });

    testPhone('오버레이 높이가 바뀌어도 카메라를 다시 설정하지 않는다', (tester) async {
      await _show(tester, focusMiddle());
      final settled = stationY(tester);

      await _show(tester, focusMiddle(noticeBar: false));
      expect(stationY(tester), settled);

      await _show(tester, focusMiddle(textScale: 1.5));
      expect(stationY(tester), settled);
    });

    testPhone('배율을 유지하며 포커스한 맨 위 역이 큰 알림 바 아래에 남고 드래그가 되돌리지 않는다', (
      tester,
    ) async {
      // 큰 글자에서 알림 바가 커진 상황. 중심을 올리는 거리가 기본 여유(220dp)를 넘는다.
      await _show(
        tester,
        _home(
          data: _tallData,
          waypointStationId: _topStation.id,
          focusedStationId: _topStation.id,
          preserveFocusedStationScale: true,
          noticeBarHeight: 130,
        ),
      );
      _expectPinBelowOverlay(tester);

      final gesture = await _startMapDrag(tester, const Offset(0, 60));
      await gesture.up();
      await tester.pumpAndSettle();

      _expectPinBelowOverlay(tester);
    });

    testWidgets('오버레이가 지도 높이 이상이어도 지도를 비우지 않고 이후에도 복구된다', (tester) async {
      tester.view.physicalSize = const Size(640, 160);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget home({required bool noticeBar}) => _home(
        data: _tallData,
        waypointStationId: _middleStation.id,
        focusedStationId: _middleStation.id,
        textScale: 1.5,
        noticeBar: noticeBar,
      );

      // 빈 카메라는 핀을 왼쪽 위 모서리(x≈43)에 붙인다. 제대로 그린 핀은 가운데 열에 온다.
      void expectPinInMapCenterColumn(WidgetTester tester, Rect surface) {
        expect(find.byKey(_waypointPin), findsOneWidget);
        expect(
          (_pinRect(tester).center.dx - surface.center.dx).abs(),
          lessThan(surface.width / 4),
        );
      }

      await _show(tester, home(noticeBar: true));
      final surface = tester.getRect(
        find.byKey(const Key('networkMapSurface')),
      );
      expect(
        networkMapOverlayBottomOf(tester) - surface.top,
        greaterThanOrEqualTo(surface.height),
        reason: '전제: 오버레이가 지도 본문 전체를 덮는다',
      );
      expectPinInMapCenterColumn(tester, surface);

      await _show(tester, home(noticeBar: false));
      expectPinInMapCenterColumn(tester, surface);
    });

    group('저장 viewport 복원', () {
      testPhone('마지막으로 본 화면과 같은 지점이 같은 화면 위치에 온다', (tester) async {
        Rect? saved;
        await _show(tester, focusMiddle(onViewportChanged: (v) => saved = v));
        final seen = stationY(tester);
        await tester.pumpWidget(const SizedBox());
        expect(saved, isNotNull);

        await _show(
          tester,
          _home(
            data: _tallData,
            waypointStationId: _middleStation.id,
            initialViewport: saved,
          ),
        );

        expect(stationY(tester), closeTo(seen, 0.5));
      });

      testPhone('저장 때와 오버레이 높이가 달라도 마지막 화면 그대로 복원한다', (tester) async {
        Rect? saved;
        await _show(tester, focusMiddle(onViewportChanged: (v) => saved = v));
        final seen = stationY(tester);
        await tester.pumpWidget(const SizedBox());

        await _show(
          tester,
          _home(
            data: _tallData,
            waypointStationId: _middleStation.id,
            initialViewport: saved,
            threeRows: false,
            noticeBar: false,
          ),
        );

        expect(stationY(tester), closeTo(seen, 0.5));
      });
    });
  });

  test('측정된 오버레이 상태는 높이가 같으면 같은 값이라 의존 위젯을 다시 build하지 않는다', () {
    const measured = NetworkMapTopInsetMeasured(120);

    expect(measured, const NetworkMapTopInsetMeasured(120));
    expect(measured.hashCode, const NetworkMapTopInsetMeasured(120).hashCode);
    expect(measured, isNot(const NetworkMapTopInsetMeasured(121)));
    expect(measured, isNot(const NetworkMapTopInsetUnmeasured()));
  });

  group('networkMapCameraForBounds obscuredTop', () {
    const source = Rect.fromLTWH(0, 0, 2000, 3000);
    const bounds = Rect.fromLTWH(500, 1000, 400, 600);
    const viewport = BoxConstraints.tightFor(width: 360, height: 640);

    MapCameraState camera(double obscuredTop) => networkMapCameraForBounds(
      bounds,
      viewport,
      sourceBounds: source,
      contain: true,
      minScale: 0.05,
      obscuredTop: obscuredTop,
    );

    test('가리는 높이가 0이면 기존 contain-fit과 같다', () {
      final base = camera(0);

      expect(base.center, bounds.center);
      expect(base.scale, closeTo(360 / 400, 1e-9));
    });

    test('bounds를 가려지지 않는 영역에 contain-fit하고 그 중앙에 둔다', () {
      final fitted = camera(160);

      expect(fitted.scale, closeTo((640 - 160) / 600, 1e-9));
      final onScreen = fitted.sourceToViewportPoint(bounds.center);
      expect(onScreen.dy, closeTo(160 + (640 - 160) / 2, 1e-6));
      expect(fitted.viewportSize, const Size(360, 640));
    });

    test('가려지지 않는 영역이 없으면 뷰포트 전체 기준으로 fit하고 빈 카메라를 만들지 않는다', () {
      for (final covered in [640.0, 900.0]) {
        final fitted = camera(covered);

        expect(fitted.viewportSize, const Size(360, 640));
        expect(fitted.scale, camera(0).scale);
        expect(fitted.center, camera(0).center);
      }
    });
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

  group('역 말풍선 topInset', () {
    test('reveal offset은 메뉴 위 끝을 오버레이 아래 여백까지 내린다', () {
      expect(
        stationPopoverRevealOffset(
          menuRect: const Rect.fromLTWH(90, 100, 220, 120),
          viewport: const Size(400, 800),
          topInset: 150,
        ),
        const Offset(0, 62),
      );
      expect(
        stationPopoverRevealOffset(
          menuRect: const Rect.fromLTWH(90, 200, 220, 120),
          viewport: const Size(400, 800),
          topInset: 150,
        ),
        Offset.zero,
      );
    });

    test('클램프된 배치도 오버레이 아래에 둔다', () {
      final placement = stationPopoverPlacement(
        stationPoint: const Offset(200, 20),
        viewport: const Size(400, 800),
        clampPosition: true,
        topInset: 150,
      );
      expect(placement.top, 150 + kStationPopoverViewportMargin);
    });
  });
}
