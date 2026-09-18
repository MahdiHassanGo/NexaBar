#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_DIR="$ROOT/dist/NexaBar.app"

printf "\n▸ Building NexaBar %s\n" "$VERSION"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/NexaBar" "$APP_DIR/Contents/MacOS/NexaBar"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ROOT/AppIcon.icns" ]]; then
  cp "$ROOT/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT/Sources/NexaBar/AppIcon.png" ]]; then
  cp "$ROOT/Sources/NexaBar/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  printf "▸ Signing with Developer ID: %s\n" "$SIGNING_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  printf "▸ Applying ad-hoc signature for local testing\n"
  codesign --force --deep --sign - "$APP_DIR"
fi

printf "✓ App created: %s\n" "$APP_DIR"
printf "  Run it with: open \"%s\"\n\n" "$APP_DIR"
