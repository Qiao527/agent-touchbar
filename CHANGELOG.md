# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- English and Simplified Chinese UI; the language follows the system and can be forced with `AGENT_TOUCHBAR_LANG`.
- Release workflow that publishes a zipped app on version tags.
- Lint step (`swift format`) in CI, Dependabot, issue and PR templates.
- `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`.

### Changed
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
