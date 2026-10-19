import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_realtime_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/core_screen_sweep_fixtures.dart';
import '../../../support/core_screen_sweep_screens.dart';
import '../../../support/ios_text_scale.dart';

/// 역 상세의 도착 정보 두 줄(방면·첫차막차 행, 실시간 도착 행)이 기본 글자에서는 한 줄에
/// 우측 정렬로 놓이고, iOS 최대 접근성 글꼴 크기(AX5)에서는 문구를 자르지 않고 줄을 나누는지 검사한다
/// (에픽 #3036 4-25). 번들 폰트가 없어 글자 폭은 Ahem 근사치다.
const _viewport = Size(402, 874);
const _devicePixelRatio = 3.0;
const _detailScreenName = '역 상세(출구 지도 안내)';
const _firstDirectionLastDeparture = '23:52';

/// 줄 바깥 여백: 컨테이너 테두리 1 + 안쪽 여백 14.
const _rowInset = 15.0;
const _positionTolerance = 1.0;
const _scrollStep = 300.0;
const _maxScrollSteps = 20;

void main() {
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });
  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  void useScale(WidgetTester tester, double scale) {
    tester.view.devicePixelRatio = _devicePixelRatio;
    tester.view.physicalSize = _viewport * _devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  Future<void> openStationDetail(WidgetTester tester) async {
    final screen = sweepScreens.singleWhere((s) => s.name == _detailScreenName);
    final navigatorKey = GlobalKey<NavigatorState>();
    const theme = SweepTheme.standard;
    await tester.pumpWidget(
      buildSweepApp(
        navigatorKey: navigatorKey,
        onboardingState: screen.onboardingState(theme),
        stationResults: screen.stationResults,
        inboxLoad: screen.inboxLoad,
      ),
    );
    await tester.pumpAndSettle();
    await screen.open(
      SweepScreenContext(
        tester: tester,
        navigatorKey: navigatorKey,
        theme: theme,
      ),
    );
    // 지연 생성 목록이라 시간표 요약이 만들어질 때까지 위에서부터 조금씩 내린다.
    final sheetScrollable = find
        .descendant(
          of: find.byKey(const Key('stationDetailSheet')),
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < _maxScrollSteps; i++) {
      if (find.text('첫차').evaluate().isNotEmpty) break;
      await tester.drag(sheetScrollable, const Offset(0, -_scrollStep));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('첫차').first);
    await tester.pumpAndSettle();
  }

  /// [text]를 감싼 가장 가까운 컨테이너 [depth]번째(0부터)의 영역.
  Rect containerRect(WidgetTester tester, Finder text, {int depth = 0}) {
    final containers = find.ancestor(
      of: text,
      matching: find.byType(Container),
    );
    return tester.getRect(containers.at(depth));
  }

  group('방면·첫차막차 행', () {
    /// 첫 방향의 행: 방면 이름과 첫차·막차 묶음을 담은 Wrap. 첫차 배지에서 두 번째 Wrap 조상이다.
    Finder firstDirectionRow() => find
        .ancestor(of: find.text('첫차').first, matching: find.byType(Wrap))
        .at(1);

    testWidgets('기본 글자에서는 방면 이름 옆 한 줄에 첫차·막차가 우측 끝에 놓인다', (tester) async {
      useScale(tester, 1.0);
      await openStationDetail(tester);

      final row = firstDirectionRow();
      final name = tester.getRect(
        find.descendant(of: row, matching: find.byType(Text)).first,
      );
      final firstLabel = tester.getRect(find.text('첫차').first);
      final lastTime = tester.getRect(find.text(_firstDirectionLastDeparture));
      final summary = tester.getRect(
        find.ancestor(of: row, matching: find.byType(Container)).first,
      );

      expect(firstLabel.center.dy, closeTo(name.center.dy, 8));
      expect(
        lastTime.right,
        closeTo(summary.right - _rowInset, _positionTolerance),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AX5에서는 첫차·막차가 방면 이름 아래 줄로 내려가고 넘치지 않는다', (tester) async {
      useScale(tester, iosAx5TextScale);
      await openStationDetail(tester);

      final name = tester.getRect(
        find
            .descendant(of: firstDirectionRow(), matching: find.byType(Text))
            .first,
      );
      final firstLabel = tester.getRect(find.text('첫차').first);

      expect(firstLabel.top, greaterThanOrEqualTo(name.bottom));
      expect(find.text(_firstDirectionLastDeparture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('실시간 도착 행', () {
    const shortArrival = RealtimeArrival(
      lineId: 'seoul-2',
      stationName: '강남',
      destination: '성수행',
      direction: '역삼 방면',
      trainNo: '2104',
      message: '곧 도착',
      positionMessage: '',
    );
    const longMessage = '전역 출발 후 세 정거장을 지나 곧 도착 예정입니다';
    const longArrival = RealtimeArrival(
      lineId: 'seoul-2',
      stationName: '강남',
      destination: '신도림행',
      direction: '교대 방면',
      trainNo: '2107',
      message: longMessage,
      positionMessage: '교대 출발',
    );

    Future<void> pumpRealtime(WidgetTester tester, RealtimeArrival arrival) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StationRealtimeSummary(
                snapshot: RealtimeSnapshot(
                  status: RealtimeSnapshotStatus.fresh,
                  arrivals: [arrival],
                ),
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('기본 글자에서는 도착 배지가 줄의 우측 끝에 놓인다', (tester) async {
      useScale(tester, 1.0);
      await pumpRealtime(tester, shortArrival);

      const eta = '곧 도착';
      final badge = containerRect(tester, find.text(eta));
      final row = containerRect(tester, find.text(eta), depth: 1);

      expect(badge.right, closeTo(row.right - _rowInset, _positionTolerance));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AX5에서는 도착 문구 전체를 자르지 않고 배지 안에서 줄바꿈한다', (tester) async {
      useScale(tester, iosAx5TextScale);
      await pumpRealtime(tester, longArrival);

      final eta = find.text(longMessage);
      expect(eta, findsOneWidget);
      final text = tester.widget<Text>(eta);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      expect(
        tester.renderObject<RenderParagraph>(eta).didExceedMaxLines,
        isFalse,
      );
      expect(find.textContaining('신도림'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
