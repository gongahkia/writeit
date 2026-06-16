#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="cerberus"
APP_BUNDLE="$ROOT_DIR/.dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
XPC_BUNDLE="$APP_CONTENTS/XPCServices/ShellExecService.xpc"
XPC_CONTENTS="$XPC_BUNDLE/Contents"
XPC_MACOS="$XPC_CONTENTS/MacOS"
IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_OPTIONS=(--force --options runtime)

if [[ "$IDENTITY" != "-" ]]; then
  SIGN_OPTIONS+=(--timestamp)
fi

cd "$ROOT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$XPC_MACOS"

cp "$BIN_DIR/cerberus" "$APP_MACOS/cerberus"
cp "$BIN_DIR/ShellExecService" "$XPC_MACOS/ShellExecService"
cp "$ROOT_DIR/Sources/cerberusApp/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/Config/ShellExecService-Info.plist" "$XPC_CONTENTS/Info.plist"

codesign "${SIGN_OPTIONS[@]}" \
  --entitlements "$ROOT_DIR/Config/ShellExecService.entitlements" \
  --sign "$IDENTITY" \
  "$XPC_BUNDLE"

codesign "${SIGN_OPTIONS[@]}" \
  --entitlements "$ROOT_DIR/Config/cerberus.entitlements" \
  --sign "$IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || true

print "$APP_BUNDLE"
