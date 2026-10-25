#!/bin/bash
# Build, install to /Applications, link atb into ~/.local/bin, and launch.
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
echo "Installed and launched. Look for the agentTouchbar icon in the menu bar."
echo "atb is linked at ~/.local/bin/atb (add ~/.local/bin to PATH if the command is not found)."
echo "Next steps:"
echo "  1. Menu bar icon > Copy Claude Code hooks config, then paste it into ~/.claude/settings.json"
echo "  2. Menu bar icon > Copy Codex hooks config, then paste it into ~/.codex/config.toml"
echo "  3. Grant Full Disk Access and Accessibility when the menu prompts you"
