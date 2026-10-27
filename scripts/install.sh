#!/usr/bin/env bash
# Build, verify, install with rollback, link atb, and launch on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
DESTINATION="${INSTALL_DIR:-/Applications}"
mkdir -p "$DESTINATION"
APP="$DESTINATION/agentTouchbar.app"
if [[ -L "$APP" ]]; then
    echo "Refusing to replace a symbolic link at $APP" >&2
    exit 1
fi
STAGING="$(mktemp -d "$DESTINATION/.agentTouchbar-install.XXXXXX")"
INSTALLED=false
HAD_PREVIOUS=false
HAD_LINK=false
LINK_INSTALLED=false
BIN_DIRECTORY="${BIN_DIR:-$HOME/.local/bin}"
cleanup() {
    local status=$?
    if [[ $status -ne 0 && "$LINK_INSTALLED" == true ]]; then
        rm -f "$BIN_DIRECTORY/atb"
    fi
    if [[ $status -ne 0 && "$HAD_LINK" == true ]]; then
        mv "$STAGING/previous-atb" "$BIN_DIRECTORY/atb"
    fi
    if [[ $status -ne 0 && "$INSTALLED" == true ]]; then
        rm -rf "$APP"
    fi
    if [[ $status -ne 0 && "$HAD_PREVIOUS" == true ]]; then
        mv "$STAGING/previous.app" "$APP"
        echo "Restored the previous application after installation failed." >&2
    fi
    rm -rf "$STAGING"
    exit "$status"
}
trap cleanup EXIT

ditto build/agentTouchbar.app "$STAGING/agentTouchbar.app"
codesign --verify --deep --strict "$STAGING/agentTouchbar.app"
pkill -x AgentTouchbar 2>/dev/null || true
if [[ -e "$APP" ]]; then
    mv "$APP" "$STAGING/previous.app"
    HAD_PREVIOUS=true
fi
mv "$STAGING/agentTouchbar.app" "$APP"
INSTALLED=true
mkdir -p "$BIN_DIRECTORY"
if [[ -d "$BIN_DIRECTORY/atb" && ! -L "$BIN_DIRECTORY/atb" ]]; then
    echo "Refusing to replace a directory at $BIN_DIRECTORY/atb" >&2
    exit 1
fi
if [[ -e "$BIN_DIRECTORY/atb" || -L "$BIN_DIRECTORY/atb" ]]; then
    mv "$BIN_DIRECTORY/atb" "$STAGING/previous-atb"
    HAD_LINK=true
fi
ln -s "$APP/Contents/MacOS/atb" "$BIN_DIRECTORY/atb"
LINK_INSTALLED=true
open "$APP"
echo
echo "Installed and launched. Look for the agentTouchbar icon in the menu bar."
echo "atb is linked at $BIN_DIRECTORY/atb (add $BIN_DIRECTORY to PATH if needed)."
echo "Next steps:"
echo "  1. Copy Claude Code hooks from the menu into ~/.claude/settings.json."
echo "  2. Copy Codex hooks from the menu into ~/.codex/config.toml."
echo "  3. Grant permissions only for the features you enable."
