#!/bin/bash
# Builds and runs the agentTouchbar probe, showing test progress live.
# Only needs the Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ATBProbe.app"
REPORT="$HOME/Desktop/agentTouchbar-probe.txt"

if ! command -v swiftc >/dev/null; then
    echo "swiftc not found. Run this first: xcode-select --install" >&2
    exit 1
fi

pkill -x ATBProbe 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
echo "Compiling…"
swiftc -O main.swift -o "$APP/Contents/MacOS/ATBProbe"
# Built and run on this Mac, so an ad-hoc signature is enough
codesign --force --sign - "$APP"

: > "$REPORT"
open "$APP"
tail -n +1 -f "$REPORT" &
TAIL=$!
sleep 2
while pgrep -x ATBProbe >/dev/null; do sleep 1; done
sleep 1
kill "$TAIL" 2>/dev/null || true
