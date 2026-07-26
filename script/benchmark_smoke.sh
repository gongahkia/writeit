#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${WRITEIT_ARTIFACT_DIR:-$ROOT_DIR/.build/artifacts}"
ARTIFACT="$OUTPUT_DIR/benchmark-smoke.json"

mkdir -p "$OUTPUT_DIR"
swift test --package-path "$ROOT_DIR" --filter TrOCRQualificationTests --quiet

cat >"$ARTIFACT" <<'EOF'
{
  "schema_version": 1,
  "artifact_type": "writeit-benchmark-smoke",
  "qualification_test_status": "passed",
  "trocr_model_included": false,
  "trocr_qualification_status": "not_evaluated",
  "warnings": ["no-real-trocr-benchmark-result"]
}
EOF
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$ARTIFACT"
echo "$ARTIFACT"
