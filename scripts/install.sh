#!/usr/bin/env bash
# Build a release and install it as ~/Applications/Speaking Speed.app.
# Re-run after pulling changes; it replaces the installed app.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${APP_DIR:-$HOME/Applications}/Speaking Speed.app"
VERSION=$(sed -n 's/.*version = "\(.*\)"/\1/p' Sources/SpeakingSpeedCore/Version.swift)

swift build -c release
BIN="$(swift build -c release --show-bin-path)/speaking-speed"

# Quit a running copy so the binary can be replaced.
pkill -f "$APP/Contents/MacOS/speaking-speed" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/speaking-speed"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.rufuspollock.speaking-speed</string>
  <key>CFBundleName</key><string>Speaking Speed</string>
  <key>CFBundleExecutable</key><string>speaking-speed</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Speaking Speed listens to estimate how fast you are talking. Audio is analysed on this Mac and never stored or sent anywhere.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for the mic permission and login items on this Mac.
codesign --force --sign - "$APP"

echo "Installed $APP"
if [[ "${1:-}" != "--no-open" ]]; then open "$APP"; fi
