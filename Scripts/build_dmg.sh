#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-3.0.1}"
export VERSION
export UNIVERSAL_BUILD=1
"$ROOT/Scripts/make-dmg.sh"
cp "$ROOT/dist/NexaBar-$VERSION.dmg" "$ROOT/NexaBar.dmg"
printf 'Universal installer created: %s/NexaBar.dmg\n' "$ROOT"
