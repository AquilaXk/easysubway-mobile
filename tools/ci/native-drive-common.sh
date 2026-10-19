#!/usr/bin/env bash
# Android·iOS native lane이 함께 쓰는 drive 흐름. 어댑터(android-native-drive.sh, ios-native-drive.sh)가
# source해서 쓰며, 단일 진입점(integration_test/native_smoke_test.dart)을 글꼴 배율별로 drive하고 영수증을 쓴다.
#
# NATIVE_TARGETS 항목은 `<대상>` 또는 `<대상>:<글꼴 배율>`이고, 진입점의 group 이름이 곧 대상 이름이다.
# 같은 배율의 항목은 한 번의 drive가 함께 돈다.
#
# 대상별 PASS/FAIL 판정(2차 신호는 보조이며, 둘이 어긋나면 FAIL):
#   1차: 구조화 결과. 진입점이 group별 결과를 reportData에 담고 host driver(test_driver/native_smoke_driver.dart)가
#        integration_response_data.json으로 쓴다. 스크립트는 이 파일을 results-scale-<배율>.json으로 남긴다.
#   보조: 로그. 실패한 테스트 줄([E]), 실패 카운터(+N -M), "Some tests failed."가 있으면 실패다. 바인딩은 testWidgets의
#        결과만 알기 때문에 test() 실패는 구조화 결과에 나타나지 않고, drive가 종료 코드 0으로 끝난다(CI에서 확인).
# drive 전에 어댑터가 시스템 글꼴 배율을 기기에 설정하고(배율이 없는 항목은 1.0), 진입점이 앱이 읽은 배율을
# `NATIVE_SYSTEM_TEXT_SCALE=` 줄로 정확히 한 번 남기면 요청한 배율과 같은지 확인한다. 줄이 없거나 여러 개이거나
# 배율이 다르면 FAIL이다.
# 빌드는 첫 drive에서 한 번만 하고, 나머지 배율은 그 산출물(어댑터의 app_binary)을 재사용한다. 첫 drive 전에
# 산출물을 지우므로, 재사용 시점에 있는 산출물은 이번 실행이 만든 것이다.
#
# 어느 단계든 실패하면 FAIL 영수증에 실패한 대상과 단계(boot/format/analyze/drive/build)를 남기고
# 즉시 끝내므로, 뒤에 오는 PASS 영수증이 FAIL을 덮어쓸 수 없다. 영수증 results에는 대상별
# PASS/FAIL/NOT_RUN(실행하지 않았거나 결과를 확인하지 못함)이 남고, PASS 영수증은 모든 대상이 PASS일 때만 쓴다.
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
#                                             host driver는 ${driver}, 산출물 재사용 인자는 ${drive_reuse_args[@]}.
#   platform_collect_failure_log              FAIL 영수증 직전에 기기 쪽 크래시·시스템 로그를 증거 디렉터리에 남긴다.
#   platform_infra_reason <로그>              인프라 오류의 긍정 증거가 있으면 사유 하나를 출력한다.
# 어댑터가 필요하면 덮어쓸 함수(기본은 아무것도 안 함): platform_recover.
# shellcheck disable=SC2154 # lane·evidence·app_binary 등 어댑터가 정하는 변수를 참조한다.
set -uo pipefail

# 첫 drive는 패키지 내려받기와 앱 빌드(Xcode·Gradle)를 포함하므로 시간 제한이 넉넉해야 한다. 산출물을 재사용하는
# drive는 설치·실행·테스트만 하므로(CI 실측 1~2분) 제한을 짧게 둬, 앱 실행 뒤 멈춘 drive를 오래 붙들지 않는다.
build_drive_timeout_seconds=900
reuse_drive_timeout_seconds=300
# shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
drive_timeout_seconds="${build_drive_timeout_seconds}"
timeout_exit_codes=(124 142) # coreutils timeout 124, perl alarm(SIGALRM) 142

# shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
entrypoint="integration_test/native_smoke_test.dart"
# shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
driver="test_driver/native_smoke_driver.dart"
# 포맷·분석 대상: 진입점과 그 helper, host driver. 대상별 파일은 run_native_drive가 더한다.
support_sources=("${entrypoint}" "${driver}" "integration_test/system_text_scale.dart")

reason_timeout="timeout"
reason_scale_mismatch="font_scale_mismatch"
reason_group_missing="group_missing"
reason_verdict_not_pass="verdict_not_pass"
default_font_scale="1.0"
# apps/mobile/integration_test/system_text_scale.dart의 textScaleTolerance와 같아야 한다(계약 테스트가 확인).
scale_tolerance="0.01"
# apps/mobile/integration_test/system_text_scale.dart의 systemTextScaleMarker와 같아야 한다(계약 테스트가 확인).
scale_marker="NATIVE_SYSTEM_TEXT_SCALE="
# apps/mobile/integration_test/native_smoke_test.dart의 _resultsKey와 같아야 한다(계약 테스트가 확인).
results_key="nativeGroups"
# integrationDriver가 reportData를 쓰는 파일 이름. 쓰는 디렉터리는 FLUTTER_TEST_OUTPUTS_DIR로 정한다.
driver_results_file="integration_response_data.json"

# 테스트가 실행되었거나 결과가 나왔다는 신호: 진행 줄(00:03 +1), 통과/실패 요약, integrationDriver 실패 상세.
test_result_signal='[0-9]{2}:[0-9]{2} \+[0-9]+|All tests passed|Failure Details:|Some tests failed|EXCEPTION CAUGHT|Test failed'
# 모든 테스트가 끝났다는 신호.
test_run_complete='All tests passed|Some tests failed'
# 테스트 시작 줄 `00:03 +1: <group> <테스트 이름>`의 앞부분. group 이름을 뒤에 붙여 쓴다.
progress_line_prefix='[0-9]{2}:[0-9]{2} \+[0-9]+( -[0-9]+)?: '
# 실패한 테스트 줄 `00:03 +1 -1: <group> <테스트 이름> [E]`의 끝부분.
failed_line_suffix=' \[E\][[:space:]]*$'
# 로그가 실패를 알리는 신호: 실패 요약, 0보다 큰 실패 카운터(+N -M), 실패한 테스트 줄, 실패 상세.
failure_signal="Some tests failed|[0-9]{2}:[0-9]{2} \\+[0-9]+ -[1-9][0-9]*: |${failed_line_suffix}|Failure Details:"
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

# 공백으로 이은 인덱스 목록 중 PASS가 아닌 항목 이름을 공백으로 이어 출력한다.
unconfirmed_among() {
  local index names=()
  for index in $1; do
    [ "${verdicts[index]}" = PASS ] || names+=("${specs[index]}")
  done
  echo "${names[*]:-}"
}

scale_log() { echo "${evidence}/flutter-drive-scale-$1.log"; }
scale_results() { echo "${evidence}/results-scale-$1.json"; }

# 구조화 결과 파일에서 group 하나의 상태를 출력한다: 실패한 테스트가 있으면 FAIL, 통과한 테스트가 하나도 없으면 EMPTY,
# 그 밖에는 PASS. 파일이 없거나 group이 없으면 아무것도 출력하지 않는다.
structured_group_status() {
  [ -s "$1" ] || return 0
  jq -r --arg key "${results_key}" --arg group "$2" \
    '.[$key][$group] | if . == null then empty elif (.failed | length) > 0 then "FAIL" elif .passed > 0 then "PASS" else "EMPTY" end' "$1" 2>/dev/null
  return 0
}

log_completed() { grep -Eq "${test_run_complete}" "$1"; }
log_reports_failure() { grep -Eq "${failure_signal}" "$1"; }
group_started_in_log() { grep -Eq "${progress_line_prefix}$2 " "$1"; }
group_failed_in_log() { grep -Eq "${progress_line_prefix}$2 .*${failed_line_suffix}" "$1"; }

# 구조화 결과(1차)와 로그(보조)로 group별 판정을 verdicts에 반영한다. 구조화 결과가 PASS여도 로그가 실패를
# 알리거나 group 시작 줄이 없으면 FAIL이다. 모든 테스트가 끝난 로그에서 확인 가능한 결과가 없는 group도 FAIL이고,
# 끊긴 로그에서는 실패가 확인된 group만 FAIL로 두어 중간에 끊긴 drive의 결과를 PASS로 읽지 않는다.
record_group_verdicts() {
  local scale="$1" log="$2" results="$3" index group status
  for index in $(indexes_at_scale "${scale}"); do
    group="$(spec_target "${specs[index]}")"
    status="$(structured_group_status "${results}" "${group}")"
    if [ "${status}" = FAIL ] || group_failed_in_log "${log}" "${group}"; then
      verdicts[index]=FAIL
    elif [ "${status}" = PASS ] && group_started_in_log "${log}" "${group}"; then
      verdicts[index]=PASS
    elif log_completed "${log}"; then
      verdicts[index]=FAIL
    fi
  done
}

# 로그에 배율 줄이 정확히 하나 있고 요청한 배율과 같은지 본다. 허용 오차 경계는 정수(1e-4 단위)로 비교해 부동소수 오차를 피한다.
scale_applied() {
  local log="$1" requested="$2" observed
  [ "$(grep -c -- "${scale_marker}" "${log}")" -eq 1 ] || return 1
  observed="$(sed -En "s/.*${scale_marker}([0-9.]+).*/\\1/p" "${log}" | head -n 1)"
  [ -n "${observed}" ] || return 1
  awk -v observed="${observed}" -v requested="${requested}" -v tolerance="${scale_tolerance}" \
    'BEGIN { diff = observed - requested; if (diff < 0) diff = -diff; exit !(int(diff * 10000 + 0.5) <= int(tolerance * 10000 + 0.5)) }'
}

# 배율 설정 출력도 drive 로그에 남겨, 설정 중 기기가 끊겨도 retry_reason이 증거를 본다.
# host driver가 쓰는 구조화 결과는 배율별 파일로 옮겨 남긴다.
run_drive() {
  local scale="$1" log="$2" outputs="${evidence}/outputs-$1" status
  rm -rf "${outputs}" "$(scale_results "${scale}")"
  platform_set_font_scale "${scale}" > "${log}" 2>&1 || return 1
  FLUTTER_TEST_OUTPUTS_DIR="${outputs}" platform_drive >> "${log}" 2>&1
  status=$?
  if [ -f "${outputs}/${driver_results_file}" ]; then
    mv "${outputs}/${driver_results_file}" "$(scale_results "${scale}")"
  fi
  rm -rf "${outputs}"
  return "${status}"
}

report_retry_pass() {
  echo "::warning::${1} drive가 ${2} 때문에 1회 재시도 후 통과했습니다. 1차 로그: $(basename "$3" .log).attempt1.log"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- ${1}: drive 재시도 후 통과 (${2})" >> "${GITHUB_STEP_SUMMARY}"
  return 0
}

# 이 배율의 항목 중 구조화 결과에 group이 없는 것이 있는지.
lacks_structured_result() {
  local index
  for index in $(indexes_at_scale "$1"); do
    case "$(structured_group_status "$2" "$(spec_target "${specs[index]}")")" in
      "" | EMPTY) return 0 ;;
    esac
  done
  return 1
}

# 이 배율에서 FAIL로 확인된 항목이 하나라도 있는지.
has_failed_verdict() {
  local index
  for index in $(indexes_at_scale "$1"); do
    [ "${verdicts[index]}" = FAIL ] && return 0
  done
  return 1
}

# drive 한 번의 결과를 확정한다(재시도까지 마친 뒤). 이 배율의 모든 항목이 PASS가 아니면 FAIL 영수증으로 끝낸다.
# drive가 실패했는데 어느 group의 실패인지 가르지 못하면(끝난 로그인데 실패한 group이 없음) 이 배율의 모든 항목이 대상이다.
settle_drive() {
  local scale="$1" exit_code="$2" log="$3" results="$4" drive_failed=0 index unconfirmed reason=""
  if [ "${exit_code}" -eq 0 ] && ! scale_applied "${log}" "${scale}"; then
    fail "$(specs_at_scale "${scale}")" drive "${reason_scale_mismatch}"
  fi
  if [ "${exit_code}" -ne 0 ] || log_reports_failure "${log}"; then drive_failed=1; fi

  record_group_verdicts "${scale}" "${log}" "${results}"
  if [ "${drive_failed}" -eq 1 ] && log_completed "${log}" && ! has_failed_verdict "${scale}"; then
    for index in $(indexes_at_scale "${scale}"); do verdicts[index]=FAIL; done
  fi

  unconfirmed="$(unconfirmed_among "$(indexes_at_scale "${scale}")")"
  [ -z "${unconfirmed}" ] && return 0
  if is_timeout_exit "${exit_code}"; then
    reason="${reason_timeout}"
  elif [ "${drive_failed}" -eq 0 ] && lacks_structured_result "${scale}" "${results}"; then
    reason="${reason_group_missing}"
  fi
  fail "${unconfirmed}" drive "${reason}"
}

drive_scale() {
  local scale="$1" label log results exit_code reason
  label="$(specs_at_scale "${scale}")"
  log="$(scale_log "${scale}")"
  results="$(scale_results "${scale}")"
  ensure_device "${label}"
  run_drive "${scale}" "${log}"
  exit_code=$?
  if [ "${exit_code}" -ne 0 ]; then
    reason="$(retry_reason "${exit_code}" "${log}")"
    if [ -n "${reason}" ]; then
      cp "${log}" "${log%.log}.attempt1.log"
      retried+=("drive:${reason}")
      platform_recover
      ensure_device "${label}"
      run_drive "${scale}" "${log}"
      exit_code=$?
      [ "${exit_code}" -eq 0 ] && report_retry_pass "${label}" "${reason}" "${log}"
    fi
  fi
  settle_drive "${scale}" "${exit_code}" "${log}" "${results}"
}

# 첫 drive가 만든 앱 산출물을 나머지 배율의 drive가 재사용하도록 한다. 산출물이 없으면 빌드 실패로 끝낸다.
reuse_built_app() {
  [ -e "${app_binary}" ] || fail "$1" build
  drive_reuse_args=("--use-application-binary=${app_binary}")
  # shellcheck disable=SC2034 # 어댑터의 platform_drive가 쓴다.
  drive_timeout_seconds="${reuse_drive_timeout_seconds}"
}

# 모든 항목이 PASS인지 명시적으로 단언한다. PASS 영수증은 이 단언 뒤에만 쓴다.
assert_all_passed() {
  local unconfirmed
  unconfirmed="$(unconfirmed_among "${!specs[*]}")"
  [ -z "${unconfirmed}" ] || fail "${unconfirmed}" drive "${reason_verdict_not_pass}"
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

  # 첫 drive가 이 산출물을 만든다. 미리 지워 두면 재사용 시점의 산출물이 이번 실행의 것임이 보장된다.
  rm -rf "${app_binary}"
  for index in "${!scales[@]}"; do
    started="${SECONDS}"
    drive_scale "${scales[index]}"
    echo "::notice::글꼴 배율 ${scales[index]} drive($(specs_at_scale "${scales[index]}")) ${SECONDS}s 시점 종료, 소요 $((SECONDS - started))초"
    if [ "${#drive_reuse_args[@]}" -eq 0 ] && [ "$((index + 1))" -lt "${#scales[@]}" ]; then
      reuse_built_app "$(specs_at_scale "${scales[index]}")"
    fi
  done

  assert_all_passed
  report_verdicts
  write_receipt PASS
}
