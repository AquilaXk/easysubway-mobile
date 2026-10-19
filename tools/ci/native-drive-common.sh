#!/usr/bin/env bash
# Android·iOS native lane이 함께 쓰는 drive 흐름. 어댑터(android-native-drive.sh, ios-native-drive.sh)가
# source해서 쓰며, 단일 진입점(integration_test/native_smoke_test.dart)을 글꼴 배율별로 drive하고 영수증을 쓴다.
#
# NATIVE_TARGETS 항목은 `<대상>` 또는 `<대상>:<글꼴 배율>`이고, 진입점의 group 이름이 곧 대상 이름이다.
# 같은 배율의 항목은 한 번의 drive가 함께 돌고, 항목별 PASS/FAIL은 로그의 group별 결과로 가른다.
# drive 전에 어댑터가 시스템 글꼴 배율을 기기에 설정하고(배율이 없는 항목은 1.0), 테스트가 앱이 읽은 배율을
# `NATIVE_SYSTEM_TEXT_SCALE=` 줄로 남기면 요청한 배율과 같은지 확인한다. 설정이 적용되지 않았다면 FAIL이다.
# 빌드는 첫 drive에서 한 번만 하고, 나머지 배율은 그 산출물(어댑터의 app_binary)을 재사용한다.
#
# 어느 단계든 실패하면 FAIL 영수증에 실패한 대상과 단계(boot/format/analyze/drive/build)를 남기고
# 즉시 끝내므로, 뒤에 오는 PASS 영수증이 FAIL을 덮어쓸 수 없다. 영수증 results에는 대상별
# PASS/FAIL/NOT_RUN(실행하지 않았거나 결과를 확인하지 못함)이 남는다.
#
# 재시도(fail-closed): 재시도 단위는 배율별 drive 한 번이다. drive가 테스트 실행 전에 인프라 오류로 끝났다는
# 긍정 증거(어댑터의 platform_infra_reason이 로그에서 찾는다)가 있고, 테스트 결과 신호가 로그에 전혀 없고,
# timeout이 아닐 때만 기기를 복구해 drive당 1회 다시 실행한다. 판정할 수 없거나 결과 신호가 하나라도 있으면
# 재시도하지 않고 FAIL이다. 재시도했다면 1차 로그를 보존하고 영수증 retried 배열에 "drive:<사유>"를 남긴다.
#
# 어댑터가 source 전에 정할 변수: lane(영수증 lane 이름), evidence(영수증·로그 디렉터리).
# 어댑터가 source 후에 정할 변수: app_binary(첫 drive가 만드는 앱 산출물 경로).
# 어댑터가 정의할 함수:
#   platform_await_device                     기기가 쓸 수 있을 때까지 기다린다. 못 쓰면 실패.
#   platform_set_font_scale <배율>            시스템 글꼴 배율을 설정한다. 실패하면 drive하지 않는다.
#   platform_drive                            flutter drive를 시간 제한 안에서 실행한다. 진입점은 ${entrypoint},
#                                             산출물 재사용 인자는 ${drive_reuse_args[@]}로 넘긴다.
#   platform_collect_failure_log              FAIL 영수증 직전에 기기 쪽 크래시·시스템 로그를 증거 디렉터리에 남긴다.
#   platform_infra_reason <로그>              인프라 오류의 긍정 증거가 있으면 사유 하나를 출력한다.
# 어댑터가 필요하면 덮어쓸 함수(기본은 아무것도 안 함): platform_recover.
# shellcheck disable=SC2154 # lane·evidence·app_binary 등 어댑터가 정하는 변수를 참조한다.
set -uo pipefail

# 첫 drive는 앱 빌드(Xcode·Gradle)를 포함하므로 시간 제한이 넉넉해야 한다.
# shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
drive_timeout_seconds=900
timeout_exit_codes=(124 142) # coreutils timeout 124, perl alarm(SIGALRM) 142

# shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
entrypoint="integration_test/native_smoke_test.dart"
# 포맷·분석 대상: 진입점과 그 helper. 대상별 파일은 run_native_drive가 더한다.
support_sources=("${entrypoint}" "integration_test/system_text_scale.dart")

reason_timeout="timeout"
reason_scale_mismatch="font_scale_mismatch"
reason_group_missing="group_missing"
default_font_scale="1.0"
# apps/mobile/integration_test/system_text_scale.dart의 textScaleTolerance와 같아야 한다(계약 테스트가 확인).
scale_tolerance="0.01"
# apps/mobile/integration_test/system_text_scale.dart의 systemTextScaleMarker와 같아야 한다(계약 테스트가 확인).
scale_marker="NATIVE_SYSTEM_TEXT_SCALE="

# 테스트가 실행되었거나 결과가 나왔다는 신호: 진행 줄(00:03 +1), 통과/실패 요약, integrationDriver 실패 상세.
test_result_signal='[0-9]{2}:[0-9]{2} \+[0-9]+|All tests passed|Failure Details:|Some tests failed|EXCEPTION CAUGHT|Test failed'
# 모든 테스트가 끝났다는 신호. 이 신호가 있어야 group별 PASS를 확정한다.
test_run_complete='All tests passed|Some tests failed'
# 테스트 시작 줄 `00:03 +1: <group> <테스트 이름>`의 앞부분. group 이름을 뒤에 붙여 쓴다.
progress_line_prefix='[0-9]{2}:[0-9]{2} \+[0-9]+( -[0-9]+)?: '
retried=()
drive_reuse_args=()

# NATIVE_TARGETS 항목과 같은 순서의 판정. 값은 PASS, FAIL, NOT_RUN.
read -r -a specs <<< "${NATIVE_TARGETS:?NATIVE_TARGETS가 필요합니다}"
verdicts=()
for _spec in "${specs[@]}"; do verdicts+=(NOT_RUN); done
unset _spec

platform_recover() { :; }

retried_json() {
  [ "${#retried[@]}" -eq 0 ] && return
  local joined
  joined="$(printf '"%s",' "${retried[@]}")"
  printf ',"retried":[%s]' "${joined%,}"
}

results_json() {
  local index entries=""
  for index in "${!specs[@]}"; do
    entries+="\"${specs[index]}\":\"${verdicts[index]}\","
  done
  printf ',"results":{%s}' "${entries%,}"
}

write_receipt() {
  printf '{"schemaVersion":1,"lane":"%s","status":"%s"%s%s%s}\n' "${lane}" "$1" "${2:-}" "$(retried_json)" "$(results_json)" > "${evidence}/receipt.json"
}

# 대상별 판정을 로그와 요약에 한 줄씩 남긴다.
report_verdicts() {
  local index
  for index in "${!specs[@]}"; do
    echo "::notice::${specs[index]} ${verdicts[index]}"
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- ${specs[index]}: ${verdicts[index]}" >> "${GITHUB_STEP_SUMMARY}"
  done
  return 0
}

# fail <대상> <단계> [사유]
fail() {
  platform_collect_failure_log
  report_verdicts
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

# 항목 `<대상>[:<배율>]`에서 대상 이름과 배율을 뽑는다.
spec_target() { echo "${1%%:*}"; }
spec_scale() { [[ "$1" == *:* ]] && echo "${1#*:}" || echo "${default_font_scale}"; }

# 중복 없이 NATIVE_TARGETS에 나온 순서대로의 배율.
distinct_scales() {
  local spec scale seen=" "
  for spec in "${specs[@]}"; do
    scale="$(spec_scale "${spec}")"
    [[ "${seen}" == *" ${scale} "* ]] && continue
    seen+="${scale} "
    echo "${scale}"
  done
}

# 배율이 같은 항목의 NATIVE_TARGETS 인덱스.
indexes_at_scale() {
  local index
  for index in "${!specs[@]}"; do
    [ "$(spec_scale "${specs[index]}")" = "$1" ] && echo "${index}"
  done
}

# 배율이 같은 항목 이름을 공백으로 이어 출력한다. 영수증 target과 알림에 쓴다.
specs_at_scale() {
  local index names=()
  for index in $(indexes_at_scale "$1"); do names+=("${specs[index]}"); done
  echo "${names[*]}"
}

# PASS로 확인되지 않은 항목 이름을 공백으로 이어 출력한다.
unconfirmed_specs_at_scale() {
  local index names=()
  for index in $(indexes_at_scale "$1"); do
    [ "${verdicts[index]}" = PASS ] || names+=("${specs[index]}")
  done
  echo "${names[*]:-}"
}

scale_log() { echo "${evidence}/flutter-drive-scale-$1.log"; }

# 로그의 group별 결과를 verdicts에 반영한다. group 안의 실패는 integrationDriver 실패 상세
# `Failure in method: <group> <테스트 이름>`으로, 실행 여부는 테스트 시작 줄로 가른다.
# 모든 테스트가 끝난 로그(test_run_complete)에서만 실패 없는 group을 PASS로 확정하고, 그 밖에는
# 실패가 확인된 group만 FAIL로 두어 중간에 끊긴 drive의 결과를 PASS로 읽지 않는다.
record_group_verdicts() {
  local scale="$1" log="$2" index group completed=1
  grep -Eq "${test_run_complete}" "${log}" || completed=0
  for index in $(indexes_at_scale "${scale}"); do
    group="$(spec_target "${specs[index]}")"
    if grep -Eq "^Failure in method: ${group} " "${log}"; then
      verdicts[index]=FAIL
    elif [ "${completed}" -eq 1 ]; then
      if grep -Eq "${progress_line_prefix}${group} " "${log}"; then
        verdicts[index]=PASS
      else
        verdicts[index]=FAIL
      fi
    fi
  done
}

observed_scale() { sed -En "s/.*${scale_marker}([0-9.]+).*/\\1/p" "$1" | tail -n 1; }

scale_matches() {
  awk -v observed="$1" -v requested="$2" -v tolerance="${scale_tolerance}" \
    'BEGIN { diff = observed - requested; exit !(diff <= tolerance && diff >= -tolerance) }'
}

# 배율 설정 출력도 drive 로그에 남겨, 설정 중 기기가 끊겨도 retry_reason이 증거를 본다.
run_drive() {
  local scale="$1" log="$2"
  platform_set_font_scale "${scale}" > "${log}" 2>&1 || return 1
  platform_drive >> "${log}" 2>&1
}

report_retry_pass() {
  echo "::warning::${1} drive가 ${2} 때문에 1회 재시도 후 통과했습니다. 1차 로그: $(basename "$3" .log).attempt1.log"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- ${1}: drive 재시도 후 통과 (${2})" >> "${GITHUB_STEP_SUMMARY}"
  return 0
}

# drive가 실패로 끝났을 때: 확인된 group 실패를 대상으로 FAIL을 남긴다.
# group을 가르지 못하면(결과 없이 끊김) 이 drive의 모든 항목이 대상이다.
fail_drive() {
  local scale="$1" exit_code="$2" log="$3" targets
  record_group_verdicts "${scale}" "${log}"
  targets="$(unconfirmed_specs_at_scale "${scale}")"
  : "${targets:=$(specs_at_scale "${scale}")}"
  is_timeout_exit "${exit_code}" && fail "${targets}" drive "${reason_timeout}"
  fail "${targets}" drive
}

# drive가 성공으로 끝났을 때: 앱이 읽은 배율이 요청한 배율과 같고 대상 group이 모두 통과했는지 확인한다.
confirm_drive() {
  local scale="$1" log="$2" observed unconfirmed
  observed="$(observed_scale "${log}")"
  if [ -z "${observed}" ] || ! scale_matches "${observed}" "${scale}"; then
    fail "$(specs_at_scale "${scale}")" drive "${reason_scale_mismatch}"
  fi
  record_group_verdicts "${scale}" "${log}"
  unconfirmed="$(unconfirmed_specs_at_scale "${scale}")"
  [ -z "${unconfirmed}" ] || fail "${unconfirmed}" drive "${reason_group_missing}"
}

drive_scale() {
  local scale="$1" label log exit_code reason
  label="$(specs_at_scale "${scale}")"
  log="$(scale_log "${scale}")"
  ensure_device "${label}"
  run_drive "${scale}" "${log}"
  exit_code=$?
  if [ "${exit_code}" -ne 0 ]; then
    reason="$(retry_reason "${exit_code}" "${log}")"
    [ -n "${reason}" ] || fail_drive "${scale}" "${exit_code}" "${log}"
    cp "${log}" "${log%.log}.attempt1.log"
    retried+=("drive:${reason}")
    platform_recover
    ensure_device "${label}"
    run_drive "${scale}" "${log}"
    exit_code=$?
    [ "${exit_code}" -eq 0 ] || fail_drive "${scale}" "${exit_code}" "${log}"
    report_retry_pass "${label}" "${reason}" "${log}"
  fi
  confirm_drive "${scale}" "${log}"
}

# 첫 drive가 만든 앱 산출물을 나머지 배율의 drive가 재사용하도록 한다. 산출물이 없으면 빌드 실패로 끝낸다.
reuse_built_app() {
  [ -e "${app_binary}" ] || fail "$1" build
  drive_reuse_args=("--use-application-binary=${app_binary}")
}

run_native_drive() {
  local sources=("${support_sources[@]}") spec scales=() scale index started
  for spec in "${specs[@]}"; do
    sources+=("integration_test/$(spec_target "${spec}").dart")
  done
  while IFS= read -r scale; do scales+=("${scale}"); done < <(distinct_scales)

  ensure_device "${NATIVE_TARGETS}"
  dart format --output=none --set-exit-if-changed "${sources[@]}" || fail "${NATIVE_TARGETS}" format
  flutter analyze "${sources[@]}" || fail "${NATIVE_TARGETS}" analyze

  for index in "${!scales[@]}"; do
    started="${SECONDS}"
    drive_scale "${scales[index]}"
    echo "::notice::글꼴 배율 ${scales[index]} drive($(specs_at_scale "${scales[index]}")) ${SECONDS}s 시점 종료, 소요 $((SECONDS - started))초"
    if [ "${#drive_reuse_args[@]}" -eq 0 ] && [ "$((index + 1))" -lt "${#scales[@]}" ]; then
      reuse_built_app "$(specs_at_scale "${scales[index]}")"
    fi
  done

  report_verdicts
  write_receipt PASS
}
