#!/usr/bin/env bash
# FLUTTER_ROOT의 Flutter SDK에 패치를 적용하고 flutter tool을 다시 빌드한다.
# 사용: apply-flutter-patch.sh <패치 파일> <패치가 flutter tool 스냅샷에 더하는 문자열>
#
# 실패하면 CI도 실패한다(fail-closed).
# - 패치가 SDK에 맞지 않으면(다른 Flutter 버전이거나 수정이 이미 SDK에 들어왔으면) 적용하지 않고 실패한다.
#   이 경우 패치를 지우거나 새 버전에 맞춰 갱신해야 한다는 신호다.
# - 다시 빌드한 flutter tool 스냅샷에 문자열이 없으면 실패한다. 패치가 실제로 쓰이는 tool에 들어갔다는 확인이다.
# 캐시에서 복원된 SDK처럼 이미 패치된 SDK는 다시 적용하지 않는다. tool 스냅샷은 소스가 아니라 git revision으로 최신 여부를
# 가리므로(bin/internal/shared.sh), 스냅샷에 문자열이 없을 때만 stamp를 지워 다시 빌드한다.
set -euo pipefail

patch_file="${1:?패치 파일이 필요합니다}"
snapshot_marker="${2:?스냅샷에서 찾을 문자열이 필요합니다}"
cd "${FLUTTER_ROOT:?FLUTTER_ROOT가 필요합니다}"
snapshot="bin/cache/flutter_tools.snapshot"
stamp="bin/cache/flutter_tools.stamp"

snapshot_has_marker() { grep -aqF -- "${snapshot_marker}" "${snapshot}"; }

if git apply --reverse --check "${patch_file}" 2> /dev/null; then
  echo "Flutter SDK에 패치가 이미 적용되어 있습니다: $(basename "${patch_file}")"
else
  git apply "${patch_file}"
  echo "Flutter SDK에 패치를 적용했습니다: $(basename "${patch_file}")"
fi

if ! snapshot_has_marker 2> /dev/null; then
  rm -f "${stamp}"
  bin/flutter --version > /dev/null
fi
snapshot_has_marker || {
  echo "패치를 적용했지만 flutter tool 스냅샷에 반영되지 않았습니다: ${snapshot}"
  exit 1
}
echo "flutter tool 스냅샷에 패치가 반영되었습니다."
