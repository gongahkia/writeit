#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CSV_FILE="${1:-}"

if [[ "${CSV_FILE}" == "-h" || "${CSV_FILE}" == "--help" ]]; then
  print "usage: Scripts/evaluate_head_gestures.sh [head-gesture-validation.csv]"
  exit 0
fi

swift run --package-path "$ROOT_DIR" cerberus-head-gesture-eval ${CSV_FILE:+"$CSV_FILE"}
