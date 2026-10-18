#!/usr/bin/env bash
# Android 에뮬레이터에서 NATIVE_TARGETS의 integration test를 차례로 실행하고 영수증을 쓴다.
# apps/mobile을 작업 디렉터리로 호출한다. 어느 단계든 실패하면 FAIL 영수증에 실패한 대상과
# 단계(boot/format/analyze/drive)를 남기고 즉시 끝내므로, 뒤에 오는 PASS 영수증이 FAIL을 덮어쓸 수 없다.
#
# 재시도: drive가 adb 연결 끊김·기기 없음·설치 실패 같은 인프라 오류로 끝났을 때만 adb를 재연결하고
# 대상당 1회 다시 실행한다. 테스트 assertion 실패는 어떤 경우에도 재시도하지 않는다.
# 재시도한 사실은 영수증 retried 배열에 "단계:사유"로 남긴다.
set -uo pipefail

evidence="${RUNNER_TEMP}/mobile-native-android"
device="emulator-5554"
device_wait_seconds="${DEVICE_WAIT_SECONDS:-60}"
boot_poll_limit="${BOOT_POLL_LIMIT:-60}"
boot_poll_interval_seconds="${BOOT_POLL_INTERVAL_SECONDS:-2}"
drive_timeout="12m"
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

fail() {
  adb logcat -d -b crash > "${evidence}/adb-crash.log" 2>&1 || true
  write_receipt FAIL ",\"target\":\"$1\",\"step\":\"$2\""
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

# 테스트 assertion 실패 흔적. 인프라 오류 문구가 함께 있어도 재시도 대상이 아니다.
is_assertion_failure() {
  grep -Eq 'Some tests failed|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|Test failed\. See exception logs' "$1"
}

# 인프라 일시 오류 사유를 출력한다. 해당하지 않으면 아무것도 출력하지 않는다.
infra_failure_reason() {
  is_assertion_failure "$1" && return
  if grep -Eq 'device offline' "$1"; then
    echo adb_offline
  elif grep -Eq "device '[^']*' not found|no devices/emulators found|device not found" "$1"; then
    echo device_not_found
  elif grep -Eq 'INSTALL_FAILED|adb install failed' "$1"; then
    echo install_failed
  fi
}

run_drive() {
  timeout "${drive_timeout}" flutter drive --driver=test_driver/integration_test.dart "--target=integration_test/$1.dart" -d "${device}" --no-dds > "${evidence}/flutter-drive-$1.log" 2>&1
}

drive_target() {
  local target="$1" reason
  await_device || fail "${target}" boot
  run_drive "${target}" && return
  reason="$(infra_failure_reason "${evidence}/flutter-drive-${target}.log")"
  [ -n "${reason}" ] || fail "${target}" drive
  retried+=("drive:${reason}")
  adb reconnect offline || true
  await_device || fail "${target}" boot
  run_drive "${target}" || fail "${target}" drive
}

sources=()
for target in ${NATIVE_TARGETS}; do
  sources+=("integration_test/${target}.dart")
done

await_device || fail "${NATIVE_TARGETS}" boot
dart format --output=none --set-exit-if-changed "${sources[@]}" || fail "${NATIVE_TARGETS}" format
flutter analyze "${sources[@]}" || fail "${NATIVE_TARGETS}" analyze

for target in ${NATIVE_TARGETS}; do
  drive_target "${target}"
done

write_receipt PASS
