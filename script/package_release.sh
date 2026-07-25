#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-package}"
APP_NAME="WriteIt"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_TEMPLATE="$ROOT_DIR/Packaging/Info.plist"
LICENSE_FILE="$ROOT_DIR/LICENSE"
README_FILE="$ROOT_DIR/README.md"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
COPYRIGHT_NOTICE="Copyright © 2026 Gabriel Ong Zhe Mian. Licensed under MIT."

usage() {
  echo "usage: $0 [--dry-run|--notarize]" >&2
}

verify_attribution() {
  test -f "$LICENSE_FILE"
  grep -Fq "MIT License" "$LICENSE_FILE"
  grep -Fq "Permission is hereby granted, free of charge" "$LICENSE_FILE"
  grep -Fq "THE SOFTWARE IS PROVIDED \"AS IS\"" "$LICENSE_FILE"
  test "$(plutil -extract NSHumanReadableCopyright raw -o - "$INFO_TEMPLATE")" = "$COPYRIGHT_NOTICE"
  grep -Fq "[MIT License](LICENSE)" "$README_FILE"
}

if [[ "$MODE" == "--dry-run" ]]; then
  test -f "$INFO_TEMPLATE"
  command -v swift >/dev/null
  command -v codesign >/dev/null
  command -v ditto >/dev/null
  command -v plutil >/dev/null
  verify_attribution
  echo "release prerequisites and attribution checks passed; set WRITEIT_VERSION and WRITEIT_SIGNING_IDENTITY to package"
  exit 0
fi

if [[ "$MODE" != "package" && "$MODE" != "--notarize" ]]; then
  usage
  exit 2
fi

verify_attribution

: "${WRITEIT_VERSION:?set WRITEIT_VERSION, for example 0.1.0}"
: "${WRITEIT_SIGNING_IDENTITY:?set WRITEIT_SIGNING_IDENTITY to a Developer ID Application identity}"
if [[ "$MODE" == "--notarize" ]]; then
  : "${WRITEIT_NOTARY_PROFILE:?set WRITEIT_NOTARY_PROFILE to a notarytool keychain profile}"
fi

ZIP_PATH="$RELEASE_DIR/$APP_NAME-$WRITEIT_VERSION.zip"

BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)/$APP_NAME"
swift build --package-path "$ROOT_DIR" -c release

rm -rf "$APP_BUNDLE"
rm -f "$ZIP_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_TEMPLATE" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $WRITEIT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${WRITEIT_BUILD_NUMBER:-1}" "$APP_BUNDLE/Contents/Info.plist"

codesign --force --options runtime --timestamp --sign "$WRITEIT_SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [[ "$MODE" == "--notarize" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$WRITEIT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
fi

echo "$ZIP_PATH"
