import 'dart:ui' show PlatformDispatcher;

/// 호스트 도구(`tools/ci/native-drive-common.sh`)가 같은 값으로 비교하는 글꼴 배율 허용 오차.
/// 계약 테스트가 두 값의 일치를 확인한다.
const textScaleTolerance = 0.01;

/// 이 배율보다 크면 큰 글자 모드(핵심 화면만 검사)다.
const _largeTextThreshold = 1.0 + textScaleTolerance;

/// 호스트가 기기에 설정한 시스템 글꼴 배율을 앱이 지금 읽은 값.
///
/// 테스트 바이너리를 배율마다 다시 빌드하지 않으므로 배율은 컴파일 시점 값이 아니라
/// 실행 시점에 기기에서 읽는다. 호스트는 [systemTextScaleMarker] 줄로 이 값을 받아 요청한 배율과 비교한다.
double get systemTextScale => PlatformDispatcher.instance.textScaleFactor;

bool isLargeTextScale(double scale) => scale > _largeTextThreshold;

/// 호스트가 로그에서 읽는 줄의 접두어. `tools/ci/native-drive-common.sh`의 `scale_marker`와 같아야 한다.
const systemTextScaleMarker = 'NATIVE_SYSTEM_TEXT_SCALE=';
