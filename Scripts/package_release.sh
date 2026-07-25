#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/.dist/cerberus.app}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/.dist/release}"
ZIP_PATH="${ZIP_PATH:-$OUT_DIR/cerberus.zip}"
ALLOW_ADHOC="${ALLOW_ADHOC:-0}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
FORCE_BUILD="${FORCE_BUILD:-1}"

usage() {
  print "usage: Scripts/package_release.sh"
  print ""
  print "env:"
  print "  CODESIGN_IDENTITY='Developer ID Application: Team Name (TEAMID)'"
  print "  NOTARY_PROFILE=cerberus-notary"
  print "  NOTARY_KEYCHAIN=/path/to/ci.keychain-db"
  print "  APP_BUNDLE=.dist/cerberus.app"
  print "  OUT_DIR=.dist/release"
  print "  ZIP_PATH=.dist/release/cerberus.zip"
  print "  SKIP_NOTARIZE=1   package without notarization"
  print "  ALLOW_ADHOC=1     allow ad-hoc signed local package"
  print "  FORCE_BUILD=0     reuse existing app bundle"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

for command_name in ditto shasum codesign; do
  command -v "$command_name" >/dev/null 2>&1 || {
    print -u2 "$command_name is not installed or not on PATH."
    exit 69
  }
done

if [[ "$ALLOW_ADHOC" != "1" ]]; then
  identity="${CODESIGN_IDENTITY:-}"
  if [[ -z "$identity" || "$identity" != Developer\ ID\ Application:* ]]; then
    print -u2 "Set CODESIGN_IDENTITY to a Developer ID Application certificate, or set ALLOW_ADHOC=1 for local packaging."
    exit 64
  fi
fi

if [[ "$FORCE_BUILD" == "1" || ! -d "$APP_BUNDLE" ]]; then
  "$ROOT_DIR/Scripts/build_app.sh" >/dev/null
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  print -u2 "App bundle not found: $APP_BUNDLE"
  exit 66
fi

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    print -u2 "Set NOTARY_PROFILE, or set SKIP_NOTARIZE=1 for local packaging."
    exit 64
  fi
  "$ROOT_DIR/Scripts/notarize_app.sh" "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >/dev/null
if [[ "$ALLOW_ADHOC" != "1" ]]; then
  "$ROOT_DIR/Scripts/release_check.sh" dev-id
  if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    "$ROOT_DIR/Scripts/release_check.sh" notary
  fi
fi

mkdir -p "$OUT_DIR"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

print "$ZIP_PATH"
print "$ZIP_PATH.sha256"
