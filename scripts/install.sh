#!/bin/bash
# 编译、安装到 /Applications，并把 atb 链接到 ~/.local/bin，然后启动。
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

pkill -x AgentTouchbar 2>/dev/null || true
sleep 0.5
rm -rf /Applications/agentTouchbar.app
cp -R build/agentTouchbar.app /Applications/

mkdir -p "$HOME/.local/bin"
ln -sf /Applications/agentTouchbar.app/Contents/MacOS/atb "$HOME/.local/bin/atb"

open /Applications/agentTouchbar.app
echo
echo "已安装并启动。菜单栏会出现 agentTouchbar 的图标。"
echo "atb 命令在 ~/.local/bin/atb（如果找不到命令，把 ~/.local/bin 加到 PATH）。"
echo "下一步："
echo "  1. 菜单栏图标 →「复制 Claude Code 的 hooks 配置」，粘贴到 ~/.claude/settings.json"
echo "  2. 菜单栏图标 →「复制 Codex 的 hooks 配置」，粘贴到 ~/.codex/config.toml"
echo "  3. 按菜单里的提示授予「完全磁盘访问权限」和「辅助功能」权限"
