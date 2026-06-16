#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/.dist/cerberus.app}"
DEMO_FILE="${DEMO_FILE:-$ROOT_DIR/.dist/demo/cerberus-demo.mov}"
CHECK="${1:-all}"

usage() {
  print "usage: Scripts/release_check.sh [all|dev-id|notary|demo|oss]"
  print ""
  print "env:"
  print "  CODESIGN_IDENTITY='Developer ID Application: Team Name (TEAMID)'"
  print "  NOTARY_PROFILE=cerberus-notary"
  print "  APP_BUNDLE=.dist/cerberus.app"
  print "  DEMO_FILE=.dist/demo/cerberus-demo.mov"
}

die() {
  print -u2 "release check failed: $1"
  exit "${2:-70}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed or not on PATH." 69
}

check_dev_id() {
  local identity="${CODESIGN_IDENTITY:-}"
  [[ -n "$identity" ]] || die "set CODESIGN_IDENTITY to a Developer ID Application certificate." 64
  [[ "$identity" == Developer\ ID\ Application:* ]] || die "CODESIGN_IDENTITY must be a Developer ID Application certificate." 64
  security find-identity -v -p codesigning | grep -F -- "$identity" >/dev/null || die "Developer ID identity is not installed in the keychain." 65
  [[ -d "$APP_BUNDLE" ]] || die "app bundle not found: $APP_BUNDLE" 66
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >/dev/null
  codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -F "Authority=$identity" >/dev/null || die "app bundle is not signed by CODESIGN_IDENTITY." 65
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE" >/dev/null
  print "dev-id ok"
}

check_notary() {
  require_command xcrun
  local profile="${NOTARY_PROFILE:-}"
  [[ -n "$profile" ]] || die "set NOTARY_PROFILE to a notarytool keychain profile." 64
  xcrun notarytool history --keychain-profile "$profile" >/dev/null || die "notarytool profile is missing or invalid." 65
  [[ -d "$APP_BUNDLE" ]] || die "app bundle not found: $APP_BUNDLE" 66
  xcrun stapler validate "$APP_BUNDLE" >/dev/null || die "app bundle does not have a valid notarization ticket stapled." 65
  print "notary ok"
}

check_demo() {
  [[ -s "$DEMO_FILE" ]] || die "demo video not found or empty: $DEMO_FILE" 66
  file "$DEMO_FILE" | grep -E "QuickTime|ISO Media|MPEG-4" >/dev/null || die "demo file is not a recognized video: $DEMO_FILE" 65
  print "demo ok"
}

check_oss() {
  require_command gh
  [[ -f "$ROOT_DIR/LICENSE" || -f "$ROOT_DIR/COPYING" ]] || die "add a LICENSE or COPYING file before making the repository public." 66
  local visibility
  visibility="$(cd "$ROOT_DIR" && gh repo view --json visibility -q .visibility 2>/dev/null)" || die "gh cannot read repository visibility." 69
  [[ "$visibility" == "PUBLIC" || "$visibility" == "public" ]] || die "repository visibility is $visibility, not PUBLIC." 65
  print "oss ok"
}

case "$CHECK" in
  -h|--help)
    usage
    ;;
  dev-id)
    check_dev_id
    ;;
  notary)
    check_notary
    ;;
  demo)
    check_demo
    ;;
  oss)
    check_oss
    ;;
  all)
    check_dev_id
    check_notary
    check_demo
    check_oss
    ;;
  *)
    usage
    exit 64
    ;;
esac
