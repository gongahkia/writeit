#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/.dist/cerberus.app}"
PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$PROFILE" ]]; then
  print -u2 "Set NOTARY_PROFILE to a notarytool keychain profile."
  exit 64
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  print -u2 "App bundle not found: $APP_BUNDLE"
  exit 66
fi

ZIP_PATH="${APP_BUNDLE%.app}.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
