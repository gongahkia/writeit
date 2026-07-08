#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="cerberus"
APP_BUNDLE="$ROOT_DIR/.dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_OPTIONS=(--force --options runtime)

usage() {
  print "usage: Scripts/build_app.sh [--check]"
}

check_layout() {
  local missing=0
  local files=(
    "$ROOT_DIR/Sources/cerberusApp/Resources/Info.plist"
    "$ROOT_DIR/Config/cerberus.entitlements"
  )

  for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
      print "missing: $file" >&2
      missing=1
    fi
  done

  if (( missing )); then
    return 1
  fi

  print "bundle layout ok: $APP_BUNDLE"
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --check)
    check_layout
    exit $?
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

if [[ "$IDENTITY" != "-" ]]; then
  SIGN_OPTIONS+=(--timestamp)
fi

cd "$ROOT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"

cp "$BIN_DIR/cerberus" "$APP_MACOS/cerberus"
cp "$ROOT_DIR/Sources/cerberusApp/Resources/Info.plist" "$APP_CONTENTS/Info.plist"

codesign "${SIGN_OPTIONS[@]}" \
  --entitlements "$ROOT_DIR/Config/cerberus.entitlements" \
  --sign "$IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || true

print "$APP_BUNDLE"
