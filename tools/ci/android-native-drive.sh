#!/usr/bin/env bash
# Android 에뮬레이터 lane 어댑터. 공통 흐름(영수증·재시도·단계)은 native-drive-common.sh가 맡고,
# 여기에는 adb로 기기를 다루는 부분만 둔다. 글꼴 배율은 `adb shell settings put system font_scale`로 설정한다.
# apps/mobile을 작업 디렉터리로 호출한다.
# shellcheck disable=SC2034 # lane은 공통 흐름이 영수증에 쓴다.
lane="android-native"
evidence="${RUNNER_TEMP:?RUNNER_TEMP가 필요합니다}/mobile-native-android"
# shellcheck source=native-drive-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/native-drive-common.sh"

# 첫 drive가 만드는 디버그 APK. 나머지 배율의 drive가 재사용한다.
app_binary="${APP_BINARY:-build/app/outputs/flutter-apk/app-debug.apk}"
device="emulator-5554"
device_wait_seconds="${DEVICE_WAIT_SECONDS:-60}"
boot_poll_limit="${BOOT_POLL_LIMIT:-60}"
boot_poll_interval_seconds="${BOOT_POLL_INTERVAL_SECONDS:-2}"

reason_adb_offline="adb_offline"
reason_device_not_found="device_not_found"
reason_install_failed="install_failed"

# adb 연결과 sys.boot_completed를 함께 확인한다.
platform_await_device() {
  timeout "${device_wait_seconds}" adb -s "${device}" wait-for-device || return 1
  local poll
  for ((poll = 0; poll < boot_poll_limit; poll++)); do
    [ "$(adb -s "${device}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && return 0
    sleep "${boot_poll_interval_seconds}"
  done
  return 1
}

platform_set_font_scale() {
  adb -s "${device}" shell settings put system font_scale "$1"
}

platform_drive() {
  timeout "${drive_timeout_seconds}s" flutter drive --driver=test_driver/integration_test.dart "--target=${entrypoint}" ${drive_reuse_args[@]+"${drive_reuse_args[@]}"} -d "${device}" --no-dds
}

platform_collect_failure_log() {
  adb logcat -d -b crash > "${evidence}/adb-crash.log" 2>&1 || true
}

platform_recover() {
  adb reconnect offline || true
}

platform_infra_reason() {
  local log="$1"
  if grep -Eq 'device offline' "${log}"; then
    echo "${reason_adb_offline}"
  elif grep -Eq "device '[^']*' not found|no devices/emulators found|device not found" "${log}"; then
    echo "${reason_device_not_found}"
  elif grep -Eq 'INSTALL_FAILED' "${log}"; then
    echo "${reason_install_failed}"
  fi
}

run_native_drive
