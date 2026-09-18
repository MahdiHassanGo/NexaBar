#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.2.0}"
APP_DIR="$ROOT/dist/NexaBar.app"
STAGE="$ROOT/dist/dmg-root"
DMG="$ROOT/dist/NexaBar-$VERSION.dmg"

"$ROOT/Scripts/build-app.sh"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/NexaBar.app"
ln -s /Applications "$STAGE/Applications"

printf "▸ Creating DMG\n"
hdiutil create \
  -volname "NexaBar" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"
printf "✓ DMG created: %s\n\n" "$DMG"
