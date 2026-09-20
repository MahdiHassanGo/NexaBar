#!/bin/bash
set -e

echo "🔨 Building NexaBar release binary (Universal arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

echo "📦 Assembling NexaBar.app bundle..."
mkdir -p build/dmg_root/NexaBar.app/Contents/MacOS
mkdir -p build/dmg_root/NexaBar.app/Contents/Resources

cp .build/apple/Products/Release/NexaBar build/dmg_root/NexaBar.app/Contents/MacOS/ 2>/dev/null || cp .build/release/NexaBar build/dmg_root/NexaBar.app/Contents/MacOS/
cp build/Info.plist build/dmg_root/NexaBar.app/Contents/
cp AppIcon.icns build/dmg_root/NexaBar.app/Contents/Resources/
cp -R .build/apple/Products/Release/NexaBar_NexaBar.bundle build/dmg_root/NexaBar.app/Contents/Resources/ 2>/dev/null || cp -R .build/release/NexaBar_NexaBar.bundle build/dmg_root/NexaBar.app/Contents/Resources/ 2>/dev/null || true

echo "🔏 Ad-hoc code signing NexaBar.app..."
codesign --force --deep -s - build/dmg_root/NexaBar.app

ln -sf /Applications build/dmg_root/Applications

echo "💿 Creating NexaBar.dmg installer..."
rm -f NexaBar.dmg
hdiutil create -volname "NexaBar" -srcfolder build/dmg_root -ov -format UDZO NexaBar.dmg

echo "✅ Done! Created universal NexaBar.dmg successfully."
