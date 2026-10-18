import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/core_screen_sweep_fixtures.dart';
import '../test/support/core_screen_sweep_screens.dart';

/// 화면 표 접근성 스모크(에픽 #3036 4-1, 4-24).
///
/// 호스트 전수 검사(`core_screen_guideline_sweep_test.dart`)와 같은 화면 표를
/// 에뮬레이터의 실제 화면 크기·밀도로 열어 탭 영역 48dp, 탭 요소 라벨, 렌더 예외(overflow)만
/// 검사한다. 글자 대비는 실제 폰트의 안티앨리어싱으로 오탐이 나므로 호스트 전수 검사가 맡는다.
///
/// 시스템 글꼴 배율은 `--dart-define=A11Y_FONT_SCALE`로 받는다. 값은 드라이브 스크립트가
/// `adb shell settings put system font_scale`로 기기에 설정한 배율과 같아야 하며, 테스트는 앱이
/// 실제로 읽은 배율이 이 값과 같은지 먼저 확인한다. 배율이 1.0보다 크면 핵심 화면만 검사한다.
/// 배율 최대치(2.0)는 Android 14 이상이 지원하는 최대 글꼴 크기 200%다.
/// https://developer.android.com/about/versions/14/features#non-linear-font-scaling
enum _FontMode { normal, largeText }

const _bothModes = {_FontMode.normal, _FontMode.largeText};
const _normalOnly = {_FontMode.normal};

/// 화면별로 검사할 글꼴 모드. 핵심 6화면은 두 모드 모두, 표에 있으나 여기 없는 화면은
/// 기본 배율만 검사한다.
const _modesByScreen = <String, Set<_FontMode>>{
  '홈(노선도)': _bothModes,
  '좌측 메뉴': _bothModes,
  '역 검색': _bothModes,
  '역 상세(출구 지도 안내)': _bothModes,
  '경로 결과·상세': _bothModes,
  '알림함': _bothModes,
};

final _fontScale = double.parse(
  const String.fromEnvironment('A11Y_FONT_SCALE', defaultValue: '1.0'),
);

final _runMode = _fontScale > 1.0 ? _FontMode.largeText : _FontMode.normal;

/// 실제 기기의 짧은 화면에서는 지연 생성 목록 아래에 있어 열린 직후 만들어지지 않는
/// `shown` 요소를 스크롤로 올리는 화면. 호스트 전수 검사는 세로 2000dp라 필요 없다.
final _revealShownOnDevice =
    <String, Future<void> Function(WidgetTester tester, Finder shown)>{
      '역 상세(출구 지도 안내)': scrollStationDetailTo,
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final screens = sweepScreens
      .where(
        (screen) =>
            (_modesByScreen[screen.name] ?? _normalOnly).contains(_runMode),
      )
      .toList();
  test('모드 표의 화면이 모두 화면 표에 있고 선택이 비지 않는다', () {
    final tableNames = sweepScreens.map((screen) => screen.name).toSet();
    expect(tableNames.containsAll(_modesByScreen.keys), isTrue);
    expect(screens, isNotEmpty);
  });

  testWidgets('앱이 읽은 시스템 글꼴 배율이 요청한 배율과 같다', (tester) async {
    expect(
      tester.platformDispatcher.textScaleFactor,
      closeTo(_fontScale, 0.01),
    );
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
    testWidgets('${screen.name} - 글자 $_fontScale배 탭 영역 48dp와 탭 요소 라벨', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final reportedErrors = <FlutterErrorDetails>[];
      Future<void> checkScreen() async {
        final navigatorKey = GlobalKey<NavigatorState>();
        const theme = SweepTheme.standard;
        await tester.pumpWidget(
          buildSweepApp(
            navigatorKey: navigatorKey,
            onboardingState: screen.onboardingState(theme),
            stationResults: screen.stationResults,
            inboxLoad: screen.inboxLoad,
            realtimeRepository: SweepRealtimeRepository(),
          ),
        );
        await tester.pumpAndSettle();
        await screen.open(
          SweepScreenContext(
            tester: tester,
            navigatorKey: navigatorKey,
            theme: theme,
            onDevice: true,
          ),
        );

        await _revealShownOnDevice[screen.name]?.call(tester, screen.shown);
        expect(screen.shown, findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.takeException(), isNull);
      }

      try {
        if (screen.inboxLoad != SweepInboxLoad.normal) {
          // 조회 실패는 화면에 오류 상태로 드러나고 오류 보고로도 남아야 한다(호스트 전수 검사와 같다).
          // 주입한 실패가 프레임워크 예외로 새어 나오므로 가로채 모으고, 그 안에 overflow가 없는지 본다.
          await _collectingFlutterErrors(reportedErrors, () {
            return runWithMobileErrorReporter(reportedErrors.add, checkScreen);
          });
          expect(reportedErrors, isNotEmpty);
          expect(
            reportedErrors.where(
              (details) => details.exceptionAsString().contains('overflowed'),
            ),
            isEmpty,
          );
        } else {
          await checkScreen();
        }
      } finally {
        semantics.dispose();
      }
    });
  }
}

/// [body]가 도는 동안 프레임워크가 보고하는 예외를 [sink]에 모은다. 끝나면 원래 핸들러를 되돌린다.
Future<void> _collectingFlutterErrors(
  List<FlutterErrorDetails> sink,
  Future<void> Function() body,
) async {
  final original = FlutterError.onError;
  FlutterError.onError = sink.add;
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}
