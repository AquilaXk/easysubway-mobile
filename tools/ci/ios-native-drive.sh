#!/usr/bin/env bash
# iOS 시뮬레이터 lane 어댑터. 공통 흐름(영수증·재시도·단계)은 native-drive-common.sh가 맡고,
# 여기에는 simctl로 시뮬레이터를 다루는 부분만 둔다. 글꼴 배율은 iOS 동적 글꼴 크기를
# `xcrun simctl ui <기기> content_size <범주>`로 설정하고, 설정값을 다시 읽어 확인한다.
# 배율은 Flutter가 iOS에서 읽는 본문 스타일 배율이다: large 1.0, 최대 접근성 크기 AX5 53/17=3.1176.
# apps/mobile을 작업 디렉터리로 호출한다.
# shellcheck disable=SC2034 # lane은 공통 흐름이 영수증에 쓴다.
lane="ios-native"
evidence="${RUNNER_TEMP:?RUNNER_TEMP가 필요합니다}/mobile-native-ios"
# shellcheck source=native-drive-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/native-drive-common.sh"

# 첫 drive가 만드는 시뮬레이터용 앱. 나머지 배율의 drive가 재사용한다.
app_binary="${APP_BINARY:-build/ios/iphonesimulator/Runner.app}"
simulator="${IOS_SIMULATOR:-iPhone 17 Pro}"
simulator_boot_timeout_seconds="${SIMULATOR_BOOT_TIMEOUT_SECONDS:-300}"

reason_simulator_unavailable="simulator_unavailable"

# perl alarm은 macOS 러너에 기본으로 있는 timeout 대용이다. 시간이 지나면 SIGALRM(종료 코드 142)으로 끝난다.
with_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

# 배율 → iOS 동적 글꼴 크기 범주. 표에 없는 배율은 설정하지 않고 실패한다.
# 3.12는 AX5 배율 53/17=3.1176을 소수 둘째 자리로 줄인 값이며 스모크 테스트의 허용 오차(0.01) 안이다.
# 정본은 apps/mobile/test/support/ios_text_scale.dart의 iosAx5TextScale이고, 계약 테스트가 둘의 일치를 확인한다.
content_size_for_scale() {
  case "$1" in
    1.0) echo "large" ;;
    3.12) echo "accessibility-extra-extra-extra-large" ;;
  esac
}

# bootstatus -b는 꺼진 시뮬레이터를 부팅하고 부팅이 끝날 때까지 기다린다.
platform_await_device() {
  with_timeout "${simulator_boot_timeout_seconds}" xcrun simctl bootstatus "${simulator}" -b > /dev/null
}

platform_set_font_scale() {
  local category
  category="$(content_size_for_scale "$1")"
  if [ -z "${category}" ]; then
    echo "지원하지 않는 iOS 글꼴 배율: $1"
    return 1
  fi
  xcrun simctl ui "${simulator}" content_size "${category}" || return 1
  [ "$(xcrun simctl ui "${simulator}" content_size)" = "${category}" ]
}

platform_drive() {
  with_timeout "${drive_timeout_seconds}" flutter drive --driver=test_driver/integration_test.dart "--target=${entrypoint}" ${drive_reuse_args[@]+"${drive_reuse_args[@]}"} -d "${simulator}" --no-dds
}

platform_collect_failure_log() {
  xcrun simctl spawn "${simulator}" log show --last 5m --style compact > "${evidence}/simulator.log" 2>&1 || true
}

# 시뮬레이터를 끄면 다음 platform_await_device가 다시 부팅한다.
platform_recover() {
  xcrun simctl shutdown "${simulator}" || true
}

platform_infra_reason() {
  if grep -Eq 'CoreSimulatorService connection (became invalid|interrupted)|Unable to boot device|Unable to lookup in current state' "$1"; then
    echo "${reason_simulator_unavailable}"
  fi
}

run_native_drive
