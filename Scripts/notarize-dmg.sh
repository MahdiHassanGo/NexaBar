#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
PROFILE="${NOTARY_PROFILE:-NexaBarNotary}"
DMG="$ROOT/dist/NexaBar-$VERSION.dmg"

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found: $DMG"
  echo "Run Scripts/make-dmg.sh first."
  exit 1
fi

echo "▸ Submitting to Apple notarization service using profile: $PROFILE"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling notarization ticket"
xcrun stapler staple "$DMG"

echo "✓ Notarized DMG: $DMG"
