#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/.dist/cerberus.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/.dist/release/cerberus.zip}"

usage() {
  print "usage: Scripts/release_smoke.sh"
  print ""
  print "env:"
  print "  CODESIGN_IDENTITY='Developer ID Application: Team Name (TEAMID)'"
  print "  NOTARY_PROFILE=cerberus-notary"
  print "  APP_BUNDLE=.dist/cerberus.app"
  print "  ZIP_PATH=.dist/release/cerberus.zip"
}

run_step() {
  local name="$1"
  shift
  print "==> $name"
  "$@"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage
    exit 64
    ;;
esac

run_step "build app" "$ROOT_DIR/Scripts/build_app.sh"
run_step "package release" "$ROOT_DIR/Scripts/package_release.sh"
run_step "verify package checksum" shasum -a 256 -c "$ZIP_PATH.sha256"
run_step "gatekeeper assessment" spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
run_step "demo check" "$ROOT_DIR/Scripts/release_check.sh" demo
run_step "open-source check" "$ROOT_DIR/Scripts/release_check.sh" oss

print "release smoke ok"
