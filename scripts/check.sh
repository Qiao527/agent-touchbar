#!/usr/bin/env bash
# Run the same checks locally and in CI. Requires Swift 6.3+ and Python 3.
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift format lint --strict --recursive Sources Tests probe Package.swift
swift test --force-resolved-versions --jobs "${SWIFT_JOBS:-4}" "$@"
BIN="$(swift build --show-bin-path "$@")"
python3 scripts/smoke-test.py "$BIN/atb"
python3 scripts/test-installer.py
