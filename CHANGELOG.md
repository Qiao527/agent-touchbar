# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Preserve clipboard types and concealed markers during AI selection fallback; avoid overwriting newer clipboard changes.
- Compare installer symlink targets by file identity so macOS temporary-directory aliases do not cause false test failures.
- Reject ambiguous HTTP framing, duplicate headers, unsupported transfer encoding, malformed request lines, and oversized declared bodies.
- Report token persistence errors and create tokens exclusively with private permissions.
- Reject unsafe configuration values before hot reload, including invalid ports, nonfinite numbers, negative limits, invalid scene conditions, and duplicate widget IDs.
- Preserve explicit null alert TTLs and prevent integer conversion and clipboard limit crashes.
- Respect disabled calendar access, invalidate stale authorization callbacks, and apply safe defaults when the initial configuration is invalid.
- Bound command output and enforce deadlines even when a command closes its output streams before exiting.
- Escape generated hook commands for installation paths containing whitespace or quotes.
- Validate notification arguments and reject unsuccessful AI HTTP responses.
- Restore the previous application when installation or launch fails.

### Added
- Generic system notification fallback when the Touch Bar is unavailable or remains dark after wake attempts.
- Third-party license notices retained in app bundles, public-source review notes, and evidence-backed portfolio guidance.
- Shared local and CI verification command (`./scripts/check.sh`), CLI integration fixtures, installer rollback checks, and robustness regression tests.
- Local server connection limits, incomplete-request deadlines, and bounded permission polling.
- Release version checks, packaged CLI checks, signature verification, and release documentation.
- English and optional Simplified Chinese UI, configurable with `AGENT_TOUCHBAR_LANG`.
- Release workflow that publishes a zipped app on version tags.
- Lint step (`swift format`) in CI, Dependabot, issue and PR templates.
- `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`.

### Changed
- English is the default UI language; `AGENT_TOUCHBAR_LANG=auto` opts into system language detection.
- New default AI translation prompts target English.
- Code comments, docs, default config, and the probe are now in English.
- Default scene names are English (`Meeting`, `Coding`, `Browser`, `Night`).

## [0.1.0] - 2026-10-25

First complete implementation. Compiled and unit-tested in CI; not yet verified on Touch Bar hardware.

### Added
- Menu bar app that takes over the Touch Bar with a three-zone layout (left, island, right) and a priority alert queue.
- YAML config with hot reload, scene rules (frontmost app, microphone, time, weekday, battery, meeting), and 25 widget types.
- Claude Code and Codex integration through the `atb` CLI, including Allow / Deny on the Touch Bar for permission requests.
- Verification codes from Messages, calendar and meeting alerts, Spotify, clipboard history, snippets, audio output switching, Pomodoro and reminders, weather, AirPods battery, browser video controls, page summaries, and AI text actions.
- Hardware probe (`probe/`) for the private Touch Bar APIs and wake behavior.
