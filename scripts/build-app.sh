#!/bin/bash
# Build and package agentTouchbar.app into build/.
#
# Signing: defaults to an ad-hoc signature. Ad-hoc signatures change on every
# build, so macOS forgets permission grants (Accessibility, Full Disk Access).
# To keep grants across rebuilds, set SIGN_IDENTITY to a certificate in your
# Keychain, for example:
#   SIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" ./scripts/build-app.sh
# List available identities with: security find-identity -v -p codesigning
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != Darwin ]]; then
    echo "The menu bar app requires macOS. Run ./scripts/check.sh for Linux core and CLI checks." >&2
    exit 1
fi

APP="build/agentTouchbar.app"
CONFIG="${CONFIGURATION:-release}"
case "$CONFIG" in
    debug|release) ;;
    *) echo "CONFIGURATION must be debug or release" >&2; exit 1 ;;
esac

swift build --force-resolved-versions -c "$CONFIG" --product AgentTouchbar
swift build --force-resolved-versions -c "$CONFIG" --product atb
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp "$BIN/AgentTouchbar" "$APP/Contents/MacOS/AgentTouchbar"
cp "$BIN/atb" "$APP/Contents/MacOS/atb"

IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/atb"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built ${PWD}/${APP} (signature: ${IDENTITY})"
