#!/usr/bin/env bash
# Android 에뮬레이터에서 NATIVE_TARGETS의 integration test를 차례로 실행하고 영수증을 쓴다.
# NATIVE_TARGETS 항목은 `<대상>` 또는 `<대상>:<글꼴 배율>`이다. 배율이 있으면 drive 전에 시스템 글꼴 배율을
# adb로 설정하고 테스트에 A11Y_FONT_SCALE로 넘기며, 배율이 없는 항목은 1.0으로 되돌려 실행한다.
# apps/mobile을 작업 디렉터리로 호출한다. 어느 단계든 실패하면 FAIL 영수증에 실패한 대상과
# 단계(boot/format/analyze/drive)를 남기고 즉시 끝내므로, 뒤에 오는 PASS 영수증이 FAIL을 덮어쓸 수 없다.
#
# 재시도(fail-closed): drive가 테스트 실행 전에 인프라 오류로 끝났다는 긍정 증거(adb offline·기기 없음·
# 설치 실패 로그)가 있고, 테스트 결과 신호가 로그에 전혀 없고, timeout(124)이 아닐 때만 adb를 재연결해
# 대상당 1회 다시 실행한다. 판정할 수 없거나 결과 신호가 하나라도 있으면 재시도하지 않고 FAIL이다.
# 재시도했다면 1차 로그를 보존하고 영수증 retried 배열에 "drive:<사유>"를 남긴다.
set -uo pipefail

evidence="${RUNNER_TEMP}/mobile-native-android"
device="emulator-5554"
device_wait_seconds="${DEVICE_WAIT_SECONDS:-60}"
boot_poll_limit="${BOOT_POLL_LIMIT:-60}"
boot_poll_interval_seconds="${BOOT_POLL_INTERVAL_SECONDS:-2}"
drive_timeout="12m"
timeout_exit_code=124

reason_adb_offline="adb_offline"
reason_device_not_found="device_not_found"
reason_install_failed="install_failed"
reason_timeout="timeout"
default_font_scale="1.0"

# 테스트가 실행되었거나 결과가 나왔다는 신호: 진행 줄(00:03 +1), 통과/실패 요약, integrationDriver 실패 상세.
test_result_signal='[0-9]{2}:[0-9]{2} \+[0-9]+|All tests passed|Failure Details:|Some tests failed|EXCEPTION CAUGHT|Test failed'
retried=()

retried_json() {
  [ "${#retried[@]}" -eq 0 ] && return
  local joined
  joined="$(printf '"%s",' "${retried[@]}")"
  printf ',"retried":[%s]' "${joined%,}"
}

write_receipt() {
  printf '{"schemaVersion":1,"lane":"android-native","status":"%s"%s%s}\n' "$1" "${2:-}" "$(retried_json)" > "${evidence}/receipt.json"
}

# fail <대상> <단계> [사유]
fail() {
  adb logcat -d -b crash > "${evidence}/adb-crash.log" 2>&1 || true
  write_receipt FAIL ",\"target\":\"$1\",\"step\":\"$2\"${3:+,\"reason\":\"$3\"}"
  exit 1
}

# adb 연결과 sys.boot_completed를 함께 확인한다.
await_device() {
  timeout "${device_wait_seconds}" adb -s "${device}" wait-for-device || return 1
  local poll
  for ((poll = 0; poll < boot_poll_limit; poll++)); do
    [ "$(adb -s "${device}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && return 0
    sleep "${boot_poll_interval_seconds}"
  done
  return 1
}

ensure_device() {
  await_device || fail "$1" boot
}

# 재시도 사유를 출력한다. 아무것도 출력하지 않으면 재시도 불가(fail-closed).
retry_reason() {
  local exit_code="$1" log="$2"
  [ "${exit_code}" -eq "${timeout_exit_code}" ] && return
  grep -Eq "${test_result_signal}" "${log}" && return
  if grep -Eq 'device offline' "${log}"; then
    echo "${reason_adb_offline}"
  elif grep -Eq "device '[^']*' not found|no devices/emulators found|device not found" "${log}"; then
    echo "${reason_device_not_found}"
  elif grep -Eq 'INSTALL_FAILED' "${log}"; then
    echo "${reason_install_failed}"
  fi
}

# 항목 `<대상>[:<배율>]`에서 대상 이름, 배율, 로그 이름(콜론 대신 하이픈)을 뽑는다.
spec_target() { echo "${1%%:*}"; }
spec_scale() { [[ "$1" == *:* ]] && echo "${1#*:}" || echo "${default_font_scale}"; }
spec_log_name() { echo "${1//:/-}"; }

# 배율 설정 출력도 대상 로그에 남겨, 설정 중 adb가 offline이어도 retry_reason이 증거를 본다.
run_drive() {
  local target scale log
  target="$(spec_target "$1")"
  scale="$(spec_scale "$1")"
  log="${evidence}/flutter-drive-$(spec_log_name "$1").log"
  adb -s "${device}" shell settings put system font_scale "${scale}" > "${log}" 2>&1 || return 1
  timeout "${drive_timeout}" flutter drive --driver=test_driver/integration_test.dart "--target=integration_test/${target}.dart" "--dart-define=A11Y_FONT_SCALE=${scale}" -d "${device}" --no-dds >> "${log}" 2>&1
}

report_retry_pass() {
  echo "::warning::${1} drive가 ${2} 때문에 1회 재시도 후 통과했습니다. 1차 로그: flutter-drive-$(spec_log_name "$1").attempt1.log"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- ${1}: drive 재시도 후 통과 (${2})" >> "${GITHUB_STEP_SUMMARY}"
  return 0
}

drive_target() {
  local target="$1" log exit_code reason
  log="${evidence}/flutter-drive-$(spec_log_name "${target}").log"
  ensure_device "${target}"
  run_drive "${target}" && return
  exit_code=$?
  reason="$(retry_reason "${exit_code}" "${log}")"
  if [ -z "${reason}" ]; then
    [ "${exit_code}" -eq "${timeout_exit_code}" ] && fail "${target}" drive "${reason_timeout}"
    fail "${target}" drive
  fi
  cp "${log}" "${evidence}/flutter-drive-$(spec_log_name "${target}").attempt1.log"
  retried+=("drive:${reason}")
  adb reconnect offline || true
  ensure_device "${target}"
  run_drive "${target}" || fail "${target}" drive
  report_retry_pass "${target}" "${reason}"
}

sources=()
for target in ${NATIVE_TARGETS}; do
  sources+=("integration_test/$(spec_target "${target}").dart")
done

ensure_device "${NATIVE_TARGETS}"
dart format --output=none --set-exit-if-changed "${sources[@]}" || fail "${NATIVE_TARGETS}" format
flutter analyze "${sources[@]}" || fail "${NATIVE_TARGETS}" analyze

for target in ${NATIVE_TARGETS}; do
  drive_target "${target}"
done

write_receipt PASS
