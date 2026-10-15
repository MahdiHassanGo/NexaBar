#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-3.4.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_DIR="$ROOT/dist/NexaBar.app"

printf "\n▸ Building NexaBar %s\n" "$VERSION"
BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

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

# Preserve SwiftPM resources used by Bundle.module on other Macs.
if [[ -d "$BIN_DIR/NexaBar_NexaBar.bundle" ]]; then
  cp -R "$BIN_DIR/NexaBar_NexaBar.bundle" "$APP_DIR/Contents/Resources/"
fi
if [[ ! -f "$APP_DIR/Contents/Resources/AppIcon.icns" && -f "$ROOT/Sources/NexaBar/AppIcon.png" ]]; then
  ICONSET="$ROOT/dist/NexaBar.iconset"
  mkdir -p "$ICONSET"
  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Sources/NexaBar/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    RETINA=$((SIZE * 2))
    sips -z "$RETINA" "$RETINA" "$ROOT/Sources/NexaBar/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
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
