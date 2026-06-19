#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for script in "$ROOT_DIR"/Scripts/*.sh; do
  zsh -n "$script"
done

print "script lint ok"
