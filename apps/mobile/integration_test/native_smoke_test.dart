import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'core_screen_a11y_smoke_test.dart' as core_screen_a11y_smoke;
import 'native_test.dart' as native_journey;
import 'system_text_scale.dart';

/// native lane의 단일 integration_test 진입점(에픽 #3036 4-27).
///
/// `flutter drive`는 대상마다 앱을 빌드·설치하므로, 대상마다 진입점을 따로 두면 빌드가 대상 수만큼
/// 반복된다. 이 파일은 각 대상의 `main`을 group으로 묶어 한 바이너리로 만든다. group 이름이
/// 곧 `NATIVE_TARGETS`의 대상 이름이고, `tools/ci/native-drive-common.sh`가 로그의 group별
/// 결과를 읽어 대상별 PASS/FAIL을 영수증에 남긴다.
///
/// 시스템 글꼴 배율은 스크립트가 drive 전에 기기에 설정하고 테스트가 실행 시점에 읽으므로
/// 배율마다 바이너리를 다시 빌드하지 않는다. 큰 글자(배율 1.0 초과) 실행에서는 접근성 스모크만 돈다.
/// 여행 검색 스모크는 배율과 무관한 흐름이라 기본 배율에서만 돈다.
///
/// Flutter 공식 문서는 여러 테스트 파일을 하나의 진입점에서 묶어 실행하는 방식을 안내한다.
/// https://docs.flutter.dev/testing/integration-tests
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (!isLargeTextScale(systemTextScale)) {
    group('native_test', native_journey.main);
  }
  group('core_screen_a11y_smoke_test', core_screen_a11y_smoke.main);
}
