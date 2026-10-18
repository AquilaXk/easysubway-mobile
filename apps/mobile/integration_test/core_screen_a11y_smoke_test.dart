import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/core_screen_sweep_fixtures.dart';
import '../test/support/core_screen_sweep_screens.dart';

/// 핵심 화면의 실기 접근성 스모크(에픽 #3036 4-1).
///
/// 호스트 전수 검사(`core_screen_guideline_sweep_test.dart`)와 같은 화면 표를
/// 에뮬레이터의 실제 화면 크기·밀도로 열어 탭 영역 48dp와 탭 요소 라벨만 검사한다.
/// 글자 대비는 실제 폰트의 안티앨리어싱으로 오탐이 나므로 호스트 전수 검사가 맡는다.
const _smokeScreenNames = <String>{
  '홈(노선도)',
  '좌측 메뉴',
  '역 검색',
  '역 상세(출구 지도 안내)',
  '경로 결과·상세',
  '알림함',
};

/// 화면 표의 `shown` 요소가 실제 기기의 짧은 화면에서는 접힌 목록 아래에 있어 지연
/// 생성되지 않는 화면의 열림 확인 요소. 호스트 전수 검사는 세로 2000dp라 영향이 없다.
final _shownOnDevice = <String, Finder>{
  '역 상세(출구 지도 안내)': find.byKey(const Key('stationDetailSheet')),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final screens = sweepScreens
      .where((screen) => _smokeScreenNames.contains(screen.name))
      .toList();
  test('스모크 대상 화면이 모두 화면 표에 있다', () {
    expect(screens.map((screen) => screen.name).toSet(), _smokeScreenNames);
  });

  // 지도 역 위치가 실행 순서에 따라 달라지지 않도록 오너 노드·라벨 사이드카를 비운다.
  setUp(() {
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheForTest(const {});
  });
  tearDown(() {
    resetNetworkMapOwnerLabelsCacheForTest();
    resetNetworkMapOwnerNodesCacheForTest();
  });

  for (final screen in screens) {
    testWidgets('${screen.name} - 탭 영역 48dp와 탭 요소 라벨', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
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

        expect(_shownOnDevice[screen.name] ?? screen.shown, findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }
}
