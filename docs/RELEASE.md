# Release and installation

agentTouchbar is a native macOS menu bar application with a local HTTP service and a companion CLI. Publishing its source to GitHub does not deploy an application server. There is no hosted web frontend, database service, or cloud backend to provision.

## Required checks

Use Swift 6.3 or later and Python 3:

```bash
./scripts/check.sh
```

On macOS with Xcode Command Line Tools:

```bash
./scripts/build-app.sh
python3 scripts/smoke-test.py build/agentTouchbar.app/Contents/MacOS/atb
swiftc -O probe/main.swift -o build/ATBProbe
```

CI runs Linux core/CLI validation and a separate macOS build, packaged CLI smoke test, and probe compilation. The test server is a fixture: it verifies CLI requests and decisions, not the real AppKit server or physical Touch Bar.

## Install and recover

```bash
./scripts/install.sh
```

The installer stages and verifies the bundle before replacing the existing application. If moving, linking, or launching fails, it restores the previous bundle. Configuration and secrets are not deleted. `INSTALL_DIR` overrides `/Applications`; `BIN_DIR` overrides `~/.local/bin`. The destination application must not be a symlink.

The application is ad-hoc signed by default. To retain macOS permission grants across rebuilds, use an installed signing identity:

```bash
SIGN_IDENTITY='Apple Development: your identity' ./scripts/install.sh
```

A valid local signature is not Apple notarization. Public notarized distribution requires an appropriate Developer ID certificate, hardened runtime configuration, entitlements as needed, notarization through Apple's service, and stapling. Those credentials and a validated notarization pipeline are not included. Do not present the current archive as notarized or App Store compatible.

## Hardware acceptance

Before calling a release hardware-validated, run `probe/run.sh` on the supported Touch Bar MacBook, then check:

- Global display, scene changes, wake after dimming, sleep/wake recovery, and quitting/restoring the system strip.
- Test alert rendering, action buttons, expiry, and menu bar fallback when private APIs are unavailable.
- Claude Code and Codex permission allow/deny behavior, timeout fallback, malformed hooks, and app shutdown during a request.
- Verification-code pasting and clipboard clearing without logging or retaining concealed items.
- Calendar disabled at launch, authorization denial, and toggling the feature on/off while an authorization callback is pending.
- Accessibility, Full Disk Access, Automation, and Calendar behavior with the minimum permissions needed for enabled features.

Record the Mac model, macOS version, app commit, and results. Compilation and mock tests cannot establish these behaviors.

## Publish an archive

1. Complete CI and the required hardware acceptance checks.
2. Set `CFBundleShortVersionString` in `Resources/Info.plist` and add the matching version section to `CHANGELOG.md`.
3. Push a matching `vMAJOR.MINOR.PATCH` tag. The release workflow rejects a mismatched tag or missing changelog section.
4. The workflow reruns checks, builds and verifies the app, tests its packaged CLI, and uploads the ZIP and SHA-256 checksum as a GitHub prerelease.
5. Download and verify the archive on a Mac before promoting the prerelease. Keep hardware or notarization limitations visible in the release notes.

The SHA-256 file detects accidental corruption. It is not an independent signature or a substitute for notarization. Never publish signing credentials, local configuration, message fixtures containing personal data, or API keys.
