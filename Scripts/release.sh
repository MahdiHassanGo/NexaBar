#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
NOTES="${2:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: ./Scripts/release.sh <version> [\"patch notes\"]"
  echo "Example: ./Scripts/release.sh 0.3.0 \"- Added compact and balanced layouts with icons\n- Added auto-update system\""
  exit 1
fi

TAG="v$VERSION"

echo "🚀 Preparing NexaBar Release $TAG..."

# Update CFBundleShortVersionString in Resources/Info.plist
if [[ -f "Resources/Info.plist" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "Resources/Info.plist" 2>/dev/null || true
  echo "✓ Updated Resources/Info.plist version to $VERSION"
fi

# Build local binary to verify compilation
echo "🔨 Verifying local build..."
swift build -c release

# Git commit & tag
git add Resources/Info.plist Sources/
if ! git diff --cached --quiet; then
  git commit -m "chore(release): bump version to $TAG"
fi

echo "🏷  Creating git tag $TAG..."
git tag -fa "$TAG" -m "NexaBar $TAG"

echo "⬆️  Pushing commit and tag to GitHub..."
git push origin HEAD
git push origin "$TAG"

# Check if GitHub CLI is installed to create release directly
if command -v gh &> /dev/null; then
  echo "📦 Building NexaBar.dmg..."
  ./Scripts/build_dmg.sh

  echo "🌐 Publishing GitHub Release via gh CLI..."
  if [[ -n "$NOTES" ]]; then
    gh release create "$TAG" NexaBar.dmg --title "NexaBar $TAG" --notes "$NOTES"
  else
    gh release create "$TAG" NexaBar.dmg --title "NexaBar $TAG" --generate-notes
  fi
  echo "✅ Release $TAG published successfully!"
else
  echo ""
  echo "🎉 Git tag $TAG has been pushed to GitHub!"
  echo ""
  echo "To complete the release:"
  echo "1. Go to: https://github.com/MahdiHassanGo/NexaBar/releases/new?tag=$TAG"
  echo "2. Add your Release Title (e.g. 'NexaBar $TAG') and Patch Notes."
  echo "3. Click 'Publish release'."
  echo "   → GitHub Actions will automatically compile NexaBar.dmg and attach it to the release!"
  echo "   → All laptops running NexaBar will automatically detect the update, show your patch notes, and update!"
  echo ""
fi
