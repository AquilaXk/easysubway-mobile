import 'package:integration_test/integration_test_driver.dart';

/// `native_smoke_test.dart`의 host driver. 테스트가 `reportData`에 담은 group별 결과를 실패했을 때도
/// `integration_response_data.json`으로 남긴다(기본 driver는 성공했을 때만 쓴다).
/// 스크립트(`tools/ci/native-drive-common.sh`)가 이 파일을 읽어 대상별 PASS/FAIL을 판정한다.
Future<void> main() => integrationDriver(writeResponseOnFailure: true);
