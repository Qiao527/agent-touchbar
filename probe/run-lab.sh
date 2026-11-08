#!/bin/bash
# Builds and launches the Agent Touchbar Lab (Safety Sandbox).
# Tests:
# 1. CAMetalLayer 60 FPS GPU Zero-Copy rendering (<1% CPU)
# 2. Direct Multi-Touch Tracking (NSTouchTypeDirect)
# 3. 1004pt Edge-to-Edge Full-Width Mode (with 8-second auto-revert safety rope)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TouchBarLab.app"

if ! command -v swiftc >/dev/null; then
    echo "Error: swiftc not found. Please install Xcode Command Line Tools." >&2
    exit 1
fi

pkill -x TouchBarLab 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Generate customized Info.plist for TouchBarLab
cat << 'EOF' > "$APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>TouchBarLab</string>
	<key>CFBundleIdentifier</key>
	<string>io.github.qiao527.touchbarlab</string>
	<key>CFBundleExecutable</key>
	<string>TouchBarLab</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
EOF

echo "🔨 Compiling TouchBarLab.swift with Metal & Cocoa..."
swiftc -O TouchBarLab.swift -o "$APP/Contents/MacOS/TouchBarLab"

echo "🔏 Signing with ad-hoc signature..."
codesign --force --sign - "$APP"

echo "🚀 Launching TouchBarLab..."
open "$APP"

echo "✅ Running! Check the on-screen diagnostics window and your Touch Bar."
