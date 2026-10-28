#!/bin/sh
# Builds the Mac widget, signs it with your Apple Development certificate (so the Keychain keeps
# recognizing it as the same app after every rebuild, and only it can read your keys), and starts it.
set -e
cd "$(dirname "$0")/.."
swift build
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --identifier com.saxenapratham.moodmix.mac .build/debug/MoodMix
else
    echo "No Apple Development certificate found (add your Apple ID in Xcode → Settings → Accounts); running unsigned."
fi
pkill -x MoodMix 2>/dev/null || true  # any running copy, however it was started
sleep 1
nohup .build/debug/MoodMix > /tmp/moodmix.log 2>&1 &
echo "MoodMix is running."
