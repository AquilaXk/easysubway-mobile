#!/usr/bin/env bash
# Android 에뮬레이터에서 NATIVE_TARGETS의 integration test를 차례로 실행하고 영수증을 쓴다.
# apps/mobile을 작업 디렉터리로 호출한다. 어느 단계든 실패하면 FAIL 영수증에 실패한 대상과
# 단계를 남기고 즉시 끝내므로, 뒤에 오는 PASS 영수증이 FAIL을 덮어쓸 수 없다.
set -uo pipefail

evidence="${RUNNER_TEMP}/mobile-native-android"

write_receipt() {
  printf '{"schemaVersion":1,"lane":"android-native","status":"%s"%s}\n' "$1" "${2:-}" > "${evidence}/receipt.json"
}

fail() {
  adb logcat -d -b crash > "${evidence}/adb-crash.log" 2>&1 || true
  write_receipt FAIL ",\"target\":\"$1\",\"step\":\"$2\""
  exit 1
}

sources=()
for target in ${NATIVE_TARGETS}; do
  sources+=("integration_test/${target}.dart")
done

dart format --output=none --set-exit-if-changed "${sources[@]}" || fail "${NATIVE_TARGETS}" format
flutter analyze "${sources[@]}" || fail "${NATIVE_TARGETS}" analyze

for target in ${NATIVE_TARGETS}; do
  timeout 12m flutter drive --driver=test_driver/integration_test.dart "--target=integration_test/${target}.dart" -d emulator-5554 --no-dds > "${evidence}/flutter-drive-${target}.log" 2>&1 || fail "${target}" drive
done

write_receipt PASS
