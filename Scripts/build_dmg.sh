#!/bin/bash
set -e

echo "🔨 Building NexaBar release binary..."
swift build -c release

echo "📦 Assembling NexaBar.app bundle..."
mkdir -p build/dmg_root/NexaBar.app/Contents/MacOS
mkdir -p build/dmg_root/NexaBar.app/Contents/Resources

cp .build/release/NexaBar build/dmg_root/NexaBar.app/Contents/MacOS/
cp build/Info.plist build/dmg_root/NexaBar.app/Contents/
cp AppIcon.icns build/dmg_root/NexaBar.app/Contents/Resources/
cp -R .build/release/NexaBar_NexaBar.bundle build/dmg_root/NexaBar.app/Contents/Resources/ 2>/dev/null || true
ln -sf /Applications build/dmg_root/Applications

echo "💿 Creating NexaBar.dmg installer..."
rm -f NexaBar.dmg
hdiutil create -volname "NexaBar" -srcfolder build/dmg_root -ov -format UDZO NexaBar.dmg

echo "✅ Done! Created NexaBar.dmg successfully."
