#!/usr/bin/env bash
# Android·iOS native lane이 함께 쓰는 drive 흐름. 어댑터(android-native-drive.sh, ios-native-drive.sh)가
# source해서 쓰며, NATIVE_TARGETS의 integration test를 차례로 실행하고 영수증을 쓴다.
# NATIVE_TARGETS 항목은 `<대상>` 또는 `<대상>:<글꼴 배율>`이다. 배율이 있으면 drive 전에 시스템 글꼴 배율을
# 어댑터가 기기에 설정하고 테스트에 A11Y_FONT_SCALE로 넘기며, 배율이 없는 항목은 1.0으로 되돌려 실행한다.
# 어느 단계든 실패하면 FAIL 영수증에 실패한 대상과 단계(boot/format/analyze/drive)를 남기고
# 즉시 끝내므로, 뒤에 오는 PASS 영수증이 FAIL을 덮어쓸 수 없다.
#
# 재시도(fail-closed): drive가 테스트 실행 전에 인프라 오류로 끝났다는 긍정 증거(어댑터의
# platform_infra_reason이 로그에서 찾는다)가 있고, 테스트 결과 신호가 로그에 전혀 없고, timeout이 아닐 때만
# 기기를 복구해 대상당 1회 다시 실행한다. 판정할 수 없거나 결과 신호가 하나라도 있으면 재시도하지 않고 FAIL이다.
# 재시도했다면 1차 로그를 보존하고 영수증 retried 배열에 "drive:<사유>"를 남긴다.
#
# 어댑터가 source 전에 정할 변수: lane(영수증 lane 이름), evidence(영수증·로그 디렉터리).
# 어댑터가 정의할 함수:
#   platform_await_device                     기기가 쓸 수 있을 때까지 기다린다. 못 쓰면 실패.
#   platform_set_font_scale <배율>            시스템 글꼴 배율을 설정한다. 실패하면 drive하지 않는다.
#   platform_drive <대상> <배율>              flutter drive를 시간 제한 안에서 실행한다.
#   platform_collect_failure_log              FAIL 영수증 직전에 기기 쪽 크래시·시스템 로그를 증거 디렉터리에 남긴다.
#   platform_infra_reason <로그>              인프라 오류의 긍정 증거가 있으면 사유 하나를 출력한다.
# 어댑터가 필요하면 덮어쓸 함수(기본은 아무것도 안 함): platform_recover.
# shellcheck disable=SC2154 # lane·evidence 등 어댑터가 정하는 변수를 참조한다.
set -uo pipefail

# shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
drive_timeout_seconds=720
timeout_exit_codes=(124 142) # coreutils timeout 124, perl alarm(SIGALRM) 142

reason_timeout="timeout"
default_font_scale="1.0"

# 테스트가 실행되었거나 결과가 나왔다는 신호: 진행 줄(00:03 +1), 통과/실패 요약, integrationDriver 실패 상세.
test_result_signal='[0-9]{2}:[0-9]{2} \+[0-9]+|All tests passed|Failure Details:|Some tests failed|EXCEPTION CAUGHT|Test failed'
retried=()

platform_recover() { :; }

retried_json() {
  [ "${#retried[@]}" -eq 0 ] && return
  local joined
  joined="$(printf '"%s",' "${retried[@]}")"
  printf ',"retried":[%s]' "${joined%,}"
}

write_receipt() {
  printf '{"schemaVersion":1,"lane":"%s","status":"%s"%s%s}\n' "${lane}" "$1" "${2:-}" "$(retried_json)" > "${evidence}/receipt.json"
}

# fail <대상> <단계> [사유]
fail() {
  platform_collect_failure_log
  write_receipt FAIL ",\"target\":\"$1\",\"step\":\"$2\"${3:+,\"reason\":\"$3\"}"
  exit 1
}

is_timeout_exit() {
  local code
  for code in "${timeout_exit_codes[@]}"; do
    [ "$1" -eq "${code}" ] && return 0
  done
  return 1
}

ensure_device() {
  platform_await_device || fail "$1" boot
}

# 재시도 사유를 출력한다. 아무것도 출력하지 않으면 재시도 불가(fail-closed).
retry_reason() {
  local exit_code="$1" log="$2"
  is_timeout_exit "${exit_code}" && return
  grep -Eq "${test_result_signal}" "${log}" && return
  platform_infra_reason "${log}"
}

# 항목 `<대상>[:<배율>]`에서 대상 이름, 배율, 로그 이름(콜론 대신 하이픈)을 뽑는다.
spec_target() { echo "${1%%:*}"; }
spec_scale() { [[ "$1" == *:* ]] && echo "${1#*:}" || echo "${default_font_scale}"; }
spec_log_name() { echo "${1//:/-}"; }

# 배율 설정 출력도 대상 로그에 남겨, 설정 중 기기가 끊겨도 retry_reason이 증거를 본다.
run_drive() {
  local target scale log
  target="$(spec_target "$1")"
  scale="$(spec_scale "$1")"
  log="${evidence}/flutter-drive-$(spec_log_name "$1").log"
  platform_set_font_scale "${scale}" > "${log}" 2>&1 || return 1
  platform_drive "${target}" "${scale}" >> "${log}" 2>&1
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
    is_timeout_exit "${exit_code}" && fail "${target}" drive "${reason_timeout}"
    fail "${target}" drive
  fi
  cp "${log}" "${evidence}/flutter-drive-$(spec_log_name "${target}").attempt1.log"
  retried+=("drive:${reason}")
  platform_recover
  ensure_device "${target}"
  run_drive "${target}" || fail "${target}" drive
  report_retry_pass "${target}" "${reason}"
}

run_native_drive() {
  local sources=() target
  for target in ${NATIVE_TARGETS}; do
    sources+=("integration_test/$(spec_target "${target}").dart")
  done

  ensure_device "${NATIVE_TARGETS}"
  dart format --output=none --set-exit-if-changed "${sources[@]}" || fail "${NATIVE_TARGETS}" format
  flutter analyze "${sources[@]}" || fail "${NATIVE_TARGETS}" analyze

  for target in ${NATIVE_TARGETS}; do
    local started="${SECONDS}"
    drive_target "${target}"
    echo "::notice::${target} drive ${SECONDS}s 시점 종료, 소요 $((SECONDS - started))초"
  done

  write_receipt PASS
}
