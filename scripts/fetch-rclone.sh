#!/bin/bash
#
# Fetch the official rclone binary for darwin-arm64 into third_party/rclone/.
# Idempotent — skips download if the binary already exists at the pinned
# version (tracked via third_party/rclone/VERSION). Bundled into iDOpus.app
# so users don't need to install anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$PROJECT_DIR/third_party/rclone"

# Pin to a specific rclone version for reproducible builds.
RCLONE_VERSION="${RCLONE_VERSION:-v1.68.2}"
ARCH="osx-arm64"
URL="https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-${ARCH}.zip"

mkdir -p "$DEST"

if [[ -f "$DEST/VERSION" && "$(cat "$DEST/VERSION")" == "$RCLONE_VERSION" && -x "$DEST/rclone" ]]; then
    echo "rclone $RCLONE_VERSION already present at $DEST/rclone"
    exit 0
fi

echo "Fetching rclone $RCLONE_VERSION for $ARCH..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -sSL "$URL" -o "$TMP/rclone.zip"
unzip -q "$TMP/rclone.zip" -d "$TMP"
BIN="$(find "$TMP" -type f -name rclone | head -1)"
LIC="$(find "$TMP" -type f -iname 'LICENSE*' | head -1)"
if [[ -z "$BIN" ]]; then
    echo "ERROR: rclone binary not found inside $URL" >&2
    exit 1
fi
install -m 0755 "$BIN" "$DEST/rclone"
[[ -n "$LIC" ]] && cp "$LIC" "$DEST/LICENSE"
echo "$RCLONE_VERSION" > "$DEST/VERSION"
echo "Installed: $DEST/rclone ($(du -h "$DEST/rclone" | cut -f1))"
