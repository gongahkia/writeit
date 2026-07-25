#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/writeit-source-beta.XXXXXX")"

cleanup() { rm -rf "$SCRATCH_DIR"; }
trap cleanup EXIT

command -v swift >/dev/null
command -v xcodebuild >/dev/null
command -v xcrun >/dev/null
xcodebuild -version
xcrun --show-sdk-path --sdk macosx >/dev/null
swift package --package-path "$ROOT_DIR" describe --type json >/dev/null
swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_DIR/build" -Xswiftc -warnings-as-errors
swift test --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_DIR/test" --quiet
bash -n "$ROOT_DIR/script/build_and_run.sh" "$ROOT_DIR/script/package_release.sh"
"$ROOT_DIR/script/package_release.sh" --dry-run
plutil -lint "$ROOT_DIR/Packaging/Info.plist" >/dev/null
git -C "$ROOT_DIR" diff --check
echo "clean source-beta verification passed"
