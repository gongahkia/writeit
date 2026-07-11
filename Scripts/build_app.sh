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
  local info_plist="$ROOT_DIR/Sources/cerberusApp/Resources/Info.plist"
  local files=(
    "$info_plist"
    "$ROOT_DIR/Config/cerberus.entitlements"
  )

  for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
      print "missing: $file" >&2
      missing=1
    fi
  done

  local usage_key
  local usage_keys=(
    NSMicrophoneUsageDescription
    NSMotionUsageDescription
    NSScreenCaptureUsageDescription
    NSSpeechRecognitionUsageDescription
  )
  for usage_key in "${usage_keys[@]}"; do
    if [[ -z "$(plutil -extract "$usage_key" raw -o - "$info_plist" 2>/dev/null || true)" ]]; then
      print "missing privacy usage description: $usage_key" >&2
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
RESOURCE_BUNDLE_NAME="cerberus_cerberusApp.bundle"
RESOURCE_BUNDLE="$BIN_DIR/$RESOURCE_BUNDLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"

cp "$BIN_DIR/cerberus" "$APP_MACOS/cerberus"
cp "$ROOT_DIR/Sources/cerberusApp/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp -R "$RESOURCE_BUNDLE" "$APP_CONTENTS/"

codesign "${SIGN_OPTIONS[@]}" \
  --sign "$IDENTITY" \
  "$APP_CONTENTS/$RESOURCE_BUNDLE_NAME"

codesign "${SIGN_OPTIONS[@]}" \
  --entitlements "$ROOT_DIR/Config/cerberus.entitlements" \
  --sign "$IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || true

print "$APP_BUNDLE"
