#!/usr/bin/env bash
# Run the same checks locally and in CI. Requires Swift 6.3+ and Python 3.
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift format lint --strict --recursive Sources Tests probe Package.swift
if ! swift test --force-resolved-versions --jobs "${SWIFT_JOBS:-4}" "$@"; then
    if [[ "$(uname -s)" == Darwin ]] && ! xcode-select -p | grep -q "Xcode.app"; then
        echo >&2
        echo "Note: Running tests on macOS requires Xcode.app with XCTest framework." >&2
        echo "On systems with only Command Line Tools, use 'swift build' and 'python3 scripts/smoke-test.py \$(swift build --show-bin-path)/atb'." >&2
    fi
    exit 1
fi
BIN="$(swift build --show-bin-path "$@")"
python3 scripts/smoke-test.py "$BIN/atb"
python3 scripts/test-installer.py
