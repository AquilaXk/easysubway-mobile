import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart' show Failure;
import 'package:integration_test/integration_test.dart';

import 'core_screen_a11y_smoke_test.dart' as core_screen_a11y_smoke;
import 'native_test.dart' as native_journey;
import 'system_text_scale.dart';

/// `reportData`에서 group별 결과를 담는 키. `tools/ci/native-drive-common.sh`의 `results_key`와 같아야 한다.
const _resultsKey = 'nativeGroups';

/// native lane의 단일 integration_test 진입점(에픽 #3036 4-27).
///
/// `flutter drive`는 대상마다 앱을 빌드·설치하므로, 대상마다 진입점을 따로 두면 빌드가 대상 수만큼
/// 반복된다. 이 파일은 각 대상의 `main`을 group으로 묶어 한 바이너리로 만든다. group 이름이
/// 곧 `NATIVE_TARGETS`의 대상 이름이다.
///
/// 대상별 결과는 로그 문자열이 아니라 구조화된 결과로 낸다. integration_test 바인딩이 모은 테스트별 결과
/// (`results`)를 group이 끝날 때 group 몫만 떼어 `reportData`에 담으면, `flutter drive`의 host driver가
/// `integration_response_data.json`으로 쓴다(공개 API: `reportData`, `integrationDriver`의
/// `writeResponseOnFailure`). 바인딩은 `testWidgets`의 결과만 알기 때문에 대상 suite는 `test()`를 쓰지
/// 않는다(계약 테스트가 확인).
///
/// 시스템 글꼴 배율은 스크립트가 drive 전에 기기에 설정하고 테스트가 실행 시점에 읽으므로
/// 배율마다 바이너리를 다시 빌드하지 않는다. 큰 글자(배율 1.0 초과) 실행에서는 접근성 스모크만 돈다.
/// 여행 검색 스모크는 배율과 무관한 흐름이라 기본 배율에서만 돈다.
///
/// Flutter 공식 문서는 여러 테스트 파일을 하나의 진입점에서 묶어 실행하는 방식을 직접 안내하지 않는다.
/// 묶음은 `package:test`의 `group`/`main` 합성이다. https://docs.flutter.dev/testing/integration-tests
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // ignore: avoid_print
  print('CACHE_PROBE_DART_v1');
  final recordedDescriptions = <String>{};

  // 배율 줄은 대상과 무관한 진입점 공통 위치에서 한 번만 남긴다. 어느 대상 조합으로 돌아도 스크립트가 읽을 수 있다.
  setUpAll(() {
    // ignore: avoid_print
    print('$systemTextScaleMarker$systemTextScale');
  });

  /// [body]의 테스트를 [name] group으로 묶고, group이 끝나면 그 사이 늘어난 결과를 이 group 몫으로 기록한다.
  void resultGroup(String name, void Function() body) {
    group(name, () {
      body();
      tearDownAll(() {
        final results = Map<String, Object>.of(binding.results)
          ..removeWhere(
            (description, _) => recordedDescriptions.contains(description),
          );
        recordedDescriptions.addAll(results.keys);
        final failed = results.entries
            .where((entry) => entry.value is Failure)
            .map((entry) => entry.key)
            .toList();
        final groups =
            (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
                  _resultsKey,
                  () => <String, dynamic>{},
                )
                as Map<String, dynamic>;
        groups[name] = <String, Object>{
          'passed': results.length - failed.length,
          'failed': failed,
        };
      });
    });
  }

  if (!isLargeTextScale(systemTextScale)) {
    resultGroup('native_test', native_journey.main);
  }
  resultGroup('core_screen_a11y_smoke_test', core_screen_a11y_smoke.main);
}
