#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/check-android-aab-16kb-page-size.sh --aab <app.aab> --bundle-config <config.txt> --artifact-dir <dir>

Options:
  --aab <path>           Required Android App Bundle.
  --bundle-config <path> Required non-empty bundletool config dump.
  --artifact-dir <dir>  Required output directory for local-only evidence.
  -h, --help            Show this help.
USAGE
}

AAB=""
BUNDLE_CONFIG=""
ARTIFACT_DIR=""
MIN_ALIGN=16384
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab) AAB="${2:-}"; shift 2 ;;
    --bundle-config) BUNDLE_CONFIG="${2:-}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$AAB" || -z "$BUNDLE_CONFIG" || -z "$ARTIFACT_DIR" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -s "$AAB" ]]; then
  echo "AAB not found or empty: $AAB" >&2
  exit 2
fi
if [[ ! -s "$BUNDLE_CONFIG" ]]; then
  echo "bundletool config not found or empty: $BUNDLE_CONFIG" >&2
  exit 2
fi

mkdir -p "$ARTIFACT_DIR"
if ! grep -q '"alignment": "PAGE_ALIGNMENT_16K"' "$BUNDLE_CONFIG"; then
  {
    echo "android_16kb_aab_page_size_check"
    echo "aab=$AAB"
    echo "minimum_load_segment_alignment=$MIN_ALIGN"
    echo "bundle_config=bundle-config.txt"
    echo "result=fail"
    echo "reason=missing_PAGE_ALIGNMENT_16K_native_library_alignment"
  } > "$ARTIFACT_DIR/summary.txt"
  exit 1
fi
zipinfo -1 "$AAB" | grep -E '(^|/)lib/[^/]+/[^/]+\.so$' > "$ARTIFACT_DIR/native-libraries.txt" || true

if [[ ! -s "$ARTIFACT_DIR/native-libraries.txt" ]]; then
  echo "No native libraries found in AAB." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

status=0
summary="$ARTIFACT_DIR/native-alignment-summary.tsv"
printf 'library\tload_alignments\tstatus\n' > "$summary"
while IFS= read -r library; do
  out="$tmp_dir/$(basename "$library")"
  align_out="$ARTIFACT_DIR/$(echo "$library" | tr '/:' '__').load-alignments.txt"
  lib_status="pass"
  if ! unzip -p "$AAB" "$library" > "$out"; then
    echo "extract_failed" > "$align_out"
    lib_status="fail"
    status=1
  elif ! node "$SCRIPT_DIR/check-elf-load-alignment.mjs" --min-align "$MIN_ALIGN" "$out" > "$align_out"; then
    lib_status="fail"
    status=1
  fi
  aligns="$(cat "$align_out")"
  printf '%s\t%s\t%s\n' "$library" "$aligns" "$lib_status" >> "$summary"
done < "$ARTIFACT_DIR/native-libraries.txt"

{
  echo "android_16kb_aab_page_size_check"
  echo "aab=$AAB"
  echo "minimum_load_segment_alignment=$MIN_ALIGN"
  echo "bundle_config=bundle-config.txt"
  echo "native_libraries=native-libraries.txt"
  echo "native_alignment_summary=native-alignment-summary.tsv"
  echo "result=$([[ "$status" -eq 0 ]] && echo pass || echo fail)"
} > "$ARTIFACT_DIR/summary.txt"

exit "$status"
