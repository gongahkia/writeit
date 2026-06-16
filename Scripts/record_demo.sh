#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/.dist/cerberus.app}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/.dist/demo}"
OUT_FILE="${1:-$OUT_DIR/cerberus-demo.mov}"
DURATION="${DEMO_SECONDS:-45}"
MODE="${DEMO_CAPTURE_MODE:-interactive}"
OPEN_APP="${DEMO_OPEN_APP:-1}"
CHECK_ONLY=0

usage() {
  print "usage: Scripts/record_demo.sh [--check|output.mov]"
  print ""
  print "env:"
  print "  DEMO_SECONDS=45"
  print "  DEMO_CAPTURE_MODE=interactive|display"
  print "  DEMO_OPEN_APP=1|0"
  print "  APP_BUNDLE=.dist/cerberus.app"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --check)
    CHECK_ONLY=1
    ;;
esac

if ! command -v screencapture >/dev/null 2>&1; then
  print -u2 "screencapture is not installed or not on PATH."
  exit 69
fi

if ! screencapture -h 2>&1 | grep -q -- "-v"; then
  print -u2 "screencapture video mode is unavailable on this macOS install."
  exit 69
fi

if [[ ! "$DURATION" == <-> || "$DURATION" -lt 1 ]]; then
  print -u2 "DEMO_SECONDS must be a positive integer."
  exit 64
fi

case "$MODE" in
  interactive|display)
    ;;
  *)
    print -u2 "DEMO_CAPTURE_MODE must be interactive or display."
    exit 64
    ;;
esac

if [[ "$OUT_FILE" != /* ]]; then
  OUT_FILE="$PWD/$OUT_FILE"
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
  if [[ -d "$APP_BUNDLE" ]]; then
    print "app bundle ok: $APP_BUNDLE"
  else
    print "app bundle missing; record_demo will build it: $APP_BUNDLE"
  fi
  print "demo recorder ok"
  exit 0
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  "$ROOT_DIR/Scripts/build_app.sh" >/dev/null
fi

mkdir -p "$(dirname "$OUT_FILE")"

if [[ "$OPEN_APP" == "1" ]]; then
  open "$APP_BUNDLE"
  sleep 2
fi

print "Recording $DURATION seconds to $OUT_FILE"

case "$MODE" in
  interactive)
    print "Select the cerberus area or window when prompted."
    screencapture -i -Jvideo -v -V"$DURATION" "$OUT_FILE"
    ;;
  display)
    screencapture -D1 -v -V"$DURATION" "$OUT_FILE"
    ;;
esac

if [[ ! -s "$OUT_FILE" ]]; then
  print -u2 "Demo recording was not created: $OUT_FILE"
  exit 70
fi

print "$OUT_FILE"
