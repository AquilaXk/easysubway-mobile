import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/core_screen_sweep_fixtures.dart';
import 'support/core_screen_sweep_screens.dart';

/// iOS 동적 글꼴의 최대 접근성 크기(AX5)에서 역 상세가 넘치지 않는지 호스트에서 검사한다(#3036 4-25).
///
/// Flutter는 iOS에서 본문 스타일의 배율(AX5 본문 53pt / 기본 17pt)을 글꼴 배율로 읽는다.
/// 실기 시뮬레이터 검사(`core_screen_a11y_smoke_test.dart`, 배율 3.12)에서 역 상세의 방면 이름과
/// 첫차·막차 줄이 한 줄에 들어가지 않아 넘친 회귀를 호스트에서 막는다.
const _iosAccessibilityExtraExtraExtraLargeScale = 53 / 17;
const _viewport = Size(402, 874);
const _devicePixelRatio = 3.0;
const _screenName = '역 상세(출구 지도 안내)';

void main() {
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });
  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  testWidgets('$_screenName은 iOS 최대 접근성 글꼴 크기에서 넘치지 않는다', (tester) async {
    final screen = sweepScreens.singleWhere((s) => s.name == _screenName);
    tester.view.devicePixelRatio = _devicePixelRatio;
    tester.view.physicalSize = _viewport * _devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue =
        _iosAccessibilityExtraExtraExtraLargeScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
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

    // 큰 글자에서는 출구 지도가 접힌 곳에 있어 지연 생성 목록을 스크롤해 연다.
    await scrollStationDetailTo(tester, screen.shown);
    expect(screen.shown, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
