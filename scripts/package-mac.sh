#!/bin/sh
# Builds MoodMix.app for macOS (release build, vinyl icon, signed with your Apple Development
# certificate if you have one) and zips it as dist/MoodMix-macOS.zip for a GitHub release.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
APP=dist/MoodMix.app

swift build -c release
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MoodMix "$APP/Contents/MacOS/MoodMix"

# Icon: render the Mac tile, then every size macOS wants.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png" --mac
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MoodMix</string>
    <key>CFBundleDisplayName</key><string>MoodMix</string>
    <key>CFBundleIdentifier</key><string>com.saxenapratham.moodmix.mac</string>
    <key>CFBundleExecutable</key><string>MoodMix</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MoodMix asks Spotify to start playing when Spotify isn't responding to remote control.</string>
</dict>
</plist>
PLIST

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" --identifier com.saxenapratham.moodmix.mac "$APP"
ditto -c -k --keepParent "$APP" dist/MoodMix-macOS.zip
echo "Built $APP and dist/MoodMix-macOS.zip ($(du -h dist/MoodMix-macOS.zip | cut -f1))"
