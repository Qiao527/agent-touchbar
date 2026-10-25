#!/bin/bash
# 编译并打包 agentTouchbar.app（放在 build/ 目录）。
#
# 签名：默认 ad-hoc 签名，但每次编译签名都会变，系统权限（辅助功能、完全磁盘访问）需要重新授权。
# 想让权限保持有效，设置 SIGN_IDENTITY 为钥匙串里的证书名，例如：
#   SIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" ./scripts/build-app.sh
# 查看可用证书：security find-identity -v -p codesigning
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/agentTouchbar.app"
CONFIG="${CONFIGURATION:-release}"

swift build -c "$CONFIG" --product AgentTouchbar
swift build -c "$CONFIG" --product atb
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/AgentTouchbar" "$APP/Contents/MacOS/AgentTouchbar"
cp "$BIN/atb" "$APP/Contents/MacOS/atb"

IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/atb"
codesign --force --sign "$IDENTITY" "$APP"
echo "已生成 ${PWD}/${APP}，签名：${IDENTITY}"
