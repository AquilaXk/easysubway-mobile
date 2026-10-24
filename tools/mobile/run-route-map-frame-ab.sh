#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-route-map-frame-ab.sh --serial <adb-serial> --artifact-root <dir> \
    --side <label>=<apk> --side <label>=<apk> [--side ...] [options]

Options:
  --serial <adb-serial>   Required Android device serial.
  --artifact-root <dir>   Required. Each run goes to <dir>/<label>-r<round>, the summary
                          to <dir>/summary.md and <dir>/summary.json.
  --side <label>=<apk>    At least two. Each side is installed with adb install -r and
                          becomes one analyzer group named <label>.
  --rounds <n>            Rounds. Each round measures every side once. Defaults to 5.
  --pan-count <n>         Pans per run. Defaults to 6.
  --pan-span-percent <n>  Swipe length as a percent of screen width. Defaults to 40.
  --focus-line <label>    Line chip to select before the pans (for example 2호선).
  --settle-seconds <sec>  Wait after launch and after the line tap. Defaults to 5.
  --adb <path>            adb executable. Defaults to $ADB or PATH lookup.
  -h, --help              Show this help.

Every round measures the sides in the order given (A, B, A, B, ...) so warmup,
heat and drift favor no side (benchmark checklist: at least 5 runs per side,
alternating). The script first copies itself, the evidence script and the
analyzer to <artifact-root>/harness and reruns from that copy, so editing the
working tree during a batch cannot change the harness mid-run. Both APKs must be
profile builds of the same package signed with the same key. The script only
installs with adb install -r. It never uninstalls, so a failed install stops
the run, and it leaves the last installed side on the device.
USAGE
}

SERIAL=""
ARTIFACT_ROOT=""
SIDE_LABELS=()
SIDE_APKS=()
ROUNDS=5
PAN_COUNT=6
PAN_SPAN_PERCENT=40
FOCUS_LINE=""
SETTLE_SECONDS=5
ADB="${ADB:-}"
ORIGINAL_ARGS=("$@")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="${2:-}"; shift 2 ;;
    --artifact-root) ARTIFACT_ROOT="${2:-}"; shift 2 ;;
    --side)
      side="${2:-}"
      if [[ "$side" != *=* ]]; then
        echo "--side needs <label>=<apk>: $side" >&2
        exit 2
      fi
      SIDE_LABELS+=("${side%%=*}")
      SIDE_APKS+=("${side#*=}")
      shift 2
      ;;
    --rounds) ROUNDS="${2:-}"; shift 2 ;;
    --pan-count) PAN_COUNT="${2:-}"; shift 2 ;;
    --pan-span-percent) PAN_SPAN_PERCENT="${2:-}"; shift 2 ;;
    --focus-line) FOCUS_LINE="${2:-}"; shift 2 ;;
    --settle-seconds) SETTLE_SECONDS="${2:-}"; shift 2 ;;
    --adb) ADB="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$SERIAL" || -z "$ARTIFACT_ROOT" || ${#SIDE_LABELS[@]} -lt 2 ]]; then
  usage >&2
  exit 2
fi
for apk in "${SIDE_APKS[@]}"; do
  if [[ ! -f "$apk" ]]; then
    echo "APK not found: $apk" >&2
    exit 2
  fi
done
if [[ "$(printf '%s\n' "${SIDE_LABELS[@]}" | sort -u | wc -l | tr -d ' ')" != "${#SIDE_LABELS[@]}" ]]; then
  echo "Side labels must be unique: ${SIDE_LABELS[*]}" >&2
  exit 2
fi
if [[ -z "$ADB" ]]; then
  ADB="$(command -v adb || true)"
fi
if [[ -z "$ADB" || ! -x "$ADB" ]]; then
  echo "adb executable not found. Pass --adb or set ADB." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$ARTIFACT_ROOT"
HARNESS_DIR="$(cd "$ARTIFACT_ROOT" && pwd)/harness"
if [[ "$SCRIPT_DIR" != "$HARNESS_DIR" ]]; then
  mkdir -p "$HARNESS_DIR"
  for script in run-route-map-frame-ab.sh run-route-map-android-evidence.sh \
    analyze-route-map-android-evidence.mjs; do
    cp "$SCRIPT_DIR/$script" "$HARNESS_DIR/$script"
  done
  exec bash "$HARNESS_DIR/run-route-map-frame-ab.sh" "${ORIGINAL_ARGS[@]}"
fi

install_side() {
  local apk="$1" output
  output="$("$ADB" -s "$SERIAL" install -r "$apk" 2>&1)"
  if ! grep -qx "Success" <<< "$(tr -d '\r' <<< "$output")"; then
    echo "adb install -r failed for $apk:" >&2
    echo "$output" >&2
    exit 1
  fi
}

measure_side() {
  local apk="$1" label="$2" round="$3"
  install_side "$apk"
  local evidence_args=(
    --serial "$SERIAL"
    --artifact-dir "$ARTIFACT_ROOT/$label-r$round"
    --adb "$ADB"
    --build-mode profile
    --pan-count "$PAN_COUNT"
    --pan-span-percent "$PAN_SPAN_PERCENT"
    --settle-seconds "$SETTLE_SECONDS"
    --measure-after-route-map-settle
  )
  if [[ -n "$FOCUS_LINE" ]]; then
    evidence_args+=(--focus-line "$FOCUS_LINE")
  fi
  "$SCRIPT_DIR/run-route-map-android-evidence.sh" "${evidence_args[@]}"
}

for ((round = 1; round <= ROUNDS; round += 1)); do
  for index in "${!SIDE_LABELS[@]}"; do
    measure_side "${SIDE_APKS[$index]}" "${SIDE_LABELS[$index]}" "$round"
  done
done

analyzer_args=()
for label in "${SIDE_LABELS[@]}"; do
  analyzer_args+=(--group "$label")
  for ((round = 1; round <= ROUNDS; round += 1)); do
    analyzer_args+=(--artifact-dir "$ARTIFACT_ROOT/$label-r$round")
  done
done

node "$SCRIPT_DIR/analyze-route-map-android-evidence.mjs" "${analyzer_args[@]}" \
  > "$ARTIFACT_ROOT/summary.md"
node "$SCRIPT_DIR/analyze-route-map-android-evidence.mjs" "${analyzer_args[@]}" \
  --format json --frames > "$ARTIFACT_ROOT/summary.json"
echo "A/B summary written to $ARTIFACT_ROOT/summary.md"
