#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift run cerberus-model-benchmark --golden-fixtures "${1:-Fixtures/Model/golden-requests.jsonl}"
