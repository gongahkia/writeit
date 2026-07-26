#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${WRITEIT_ARTIFACT_DIR:-$ROOT_DIR/.build/artifacts}"
BENCHMARK_ARTIFACT="${WRITEIT_BENCHMARK_ARTIFACT:-$ARTIFACT_DIR/benchmark-smoke.json}"
COMPATIBILITY_ARTIFACT="${WRITEIT_COMPATIBILITY_ARTIFACT:-$ARTIFACT_DIR/compatibility-smoke.json}"
OUTPUT_ARTIFACT="$ARTIFACT_DIR/release-readiness.json"

json_value() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
  value = json.load(file)
for key in sys.argv[2].split("."):
  value = value[key]
if isinstance(value, bool):
  print(str(value).lower())
elif isinstance(value, str):
  print(value)
else:
  raise TypeError("expected a string or boolean")
PY
}

require_value() {
  local actual
  actual="$(json_value "$1" "$2")"
  if [[ "$actual" != "$3" ]]; then
    echo "release readiness failed: $2 must be $3 in $1" >&2
    exit 1
  fi
}

command -v python3 >/dev/null
test -f "$BENCHMARK_ARTIFACT"
test -f "$COMPATIBILITY_ARTIFACT"
require_value "$BENCHMARK_ARTIFACT" artifact_type writeit-benchmark-smoke
require_value "$BENCHMARK_ARTIFACT" qualification_test_status passed
require_value "$COMPATIBILITY_ARTIFACT" artifact_type writeit-compatibility-smoke
require_value "$COMPATIBILITY_ARTIFACT" status passed

trocr_included="$(json_value "$BENCHMARK_ARTIFACT" trocr_model_included)"
trocr_status="$(json_value "$BENCHMARK_ARTIFACT" trocr_qualification_status)"
if [[ "$trocr_included" == true && "$trocr_status" != qualified ]]; then
  echo "release readiness failed: included TrOCR requires a qualified benchmark result" >&2
  exit 1
fi
if [[ "$trocr_included" != true && "$trocr_status" != not_evaluated ]]; then
  echo "release readiness failed: unbundled TrOCR must be not_evaluated" >&2
  exit 1
fi
if [[ "$trocr_included" == true ]]; then
  readiness_status=passed
  readiness_warnings='[]'
else
  readiness_status=passed_with_warnings
  readiness_warnings='["no-real-trocr-benchmark-result"]'
fi

"$ROOT_DIR/script/verify_source_beta.sh"
"$ROOT_DIR/script/package_release.sh" --dry-run

mkdir -p "$ARTIFACT_DIR"
cat >"$OUTPUT_ARTIFACT" <<EOF
{
  "schema_version": 1,
  "artifact_type": "writeit-release-readiness",
  "status": "$readiness_status",
  "warnings": $readiness_warnings
}
EOF
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$OUTPUT_ARTIFACT"
if [[ "$trocr_included" == true ]]; then
  echo "release readiness passed"
else
  echo "release readiness passed with warning: no real TrOCR benchmark result"
fi
echo "$OUTPUT_ARTIFACT"
