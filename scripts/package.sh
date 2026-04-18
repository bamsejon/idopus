#!/bin/bash
#
# Build iDOpus as a distributable macOS .dmg
#
# Output: dist/iDOpus-<version>.dmg
#
# Requires: cmake, Xcode command line tools, hdiutil, codesign (built-in).
# Uses ad-hoc code signing (no Apple Developer ID required). Ad-hoc signing
# still gives macOS a stable code identity, so TCC grants (Documents,
# Downloads, etc.) are more likely to persist across rebuilds.
#
# Users still need to right-click → Open on first launch because the
# signature isn't Apple-notarized.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build-release"
DIST_DIR="$PROJECT_DIR/dist"

VERSION=$(grep -E "project\(idopus VERSION" "$PROJECT_DIR/CMakeLists.txt" | sed -E 's/.*VERSION ([0-9.]+).*/\1/')
DMG_NAME="iDOpus-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOL_NAME="iDOpus ${VERSION}"

echo "=== Fetching rclone helper (if needed) ==="
"$SCRIPT_DIR/fetch-rclone.sh"

echo "=== Building iDOpus ${VERSION} (Release) ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

cmake -S "$PROJECT_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" --config Release -j

APP_PATH="$BUILD_DIR/iDOpus.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: $APP_PATH not produced by build" >&2
    exit 1
fi

echo "=== Running tests ==="
"$BUILD_DIR/pal_test" >/dev/null
"$BUILD_DIR/core_test" >/dev/null
echo "  tests OK"

echo "=== Code-signing (ad-hoc) ==="
codesign --force --deep --sign - \
    --options runtime \
    --identifier "se.bamsejon.idopus" \
    "$APP_PATH" >/dev/null
codesign --verify --deep --strict "$APP_PATH"
echo "  signed"

echo "=== Creating $DMG_NAME ==="
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo
echo "Built: $DMG_PATH ($SIZE)"
echo "SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
