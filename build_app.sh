#!/usr/bin/env bash
#
# Builds QuickCopy and assembles a runnable .app bundle.
#
# Usage:
#   ./build_app.sh           # release build into ./build/QuickCopy.app
#   ./build_app.sh --debug   # debug build
#
set -euo pipefail

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="QuickCopy"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc code signature. macOS keys the Accessibility grant to the binary's
# signature, so signing keeps the permission stable across rebuilds of an
# already-granted bundle (re-grant once after the first signed build).
echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
echo "    Run with: open \"$APP_BUNDLE\""
