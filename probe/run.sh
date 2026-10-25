#!/bin/bash
# 编译并运行 agentTouchbar 探针，实时显示测试过程。
# 只需要 Xcode 命令行工具：xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ATBProbe.app"
REPORT="$HOME/Desktop/agentTouchbar-probe.txt"

if ! command -v swiftc >/dev/null; then
    echo "找不到 swiftc，请先运行：xcode-select --install" >&2
    exit 1
fi

pkill -x ATBProbe 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
echo "正在编译…"
swiftc -O main.swift -o "$APP/Contents/MacOS/ATBProbe"
# 本机编译、本机运行，ad-hoc 签名就够了
codesign --force --sign - "$APP"

: > "$REPORT"
open "$APP"
tail -n +1 -f "$REPORT" &
TAIL=$!
sleep 2
while pgrep -x ATBProbe >/dev/null; do sleep 1; done
sleep 1
kill "$TAIL" 2>/dev/null || true
