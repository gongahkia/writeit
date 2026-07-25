#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$ROOT_DIR" cerberus-vlm-benchmark "$@"
