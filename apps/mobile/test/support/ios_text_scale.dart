/// iOS 동적 글꼴의 최대 접근성 크기(AX5, `accessibility-extra-extra-extra-large`)에서
/// Flutter가 글꼴 배율로 읽는 값.
///
/// iOS는 본문 스타일 글자가 기본 17pt에서 AX5의 53pt로 커진다(Apple HIG Typography의 Dynamic Type 표).
/// Flutter 엔진은 이 비율을 `textScaleFactor`로 넘기므로 53 / 17 = 3.1176...이다. 실기 시뮬레이터에서
/// 읽은 값이 3.1176470588이었다.
///
/// 시뮬레이터 lane(`tools/ci/ios-native-drive.sh`의 배율 표, `mobile-native-integration.yml`의
/// `NATIVE_TARGETS`)은 이 값을 소수 둘째 자리로 줄인 `3.12`를 쓴다. 스모크 테스트가 읽은 배율과
/// 요청 배율을 0.01 오차로 비교하므로 3.12가 허용되며, 두 값이 어긋나지 않는다는 것은
/// `tools/ci/mobile-native-integration-workflow.test.mjs`가 이 파일을 읽어 확인한다.
const iosAx5TextScale = 53 / 17;
