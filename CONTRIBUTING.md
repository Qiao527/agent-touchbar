# Contributing

Thanks for your interest. Bug reports, widget ideas, and pull requests are welcome.

## Development setup

Use Swift 6.3 or later and Python 3 on Linux or macOS for core and CLI development. Building the menu bar app requires a Mac with Xcode Command Line Tools (`xcode-select --install`). A Touch Bar is required for hardware acceptance testing.

```bash
./scripts/check.sh          # lint, core tests, CLI integration checks, installer regression checks
./scripts/build-app.sh      # macOS only: build and verify build/agentTouchbar.app
```

`SWIFT_JOBS=4` controls test build parallelism. `scripts/check.sh` accepts SwiftPM cache/configuration path arguments for environments with a read-only home directory. See [docs/RELEASE.md](docs/RELEASE.md) for release requirements.

## Project layout

| Path | What lives there |
|---|---|
| `Sources/AgentTouchbarCore` | AppKit-free logic: config, scenes, alert queue, code extraction, hook parsing, HTTP parsing, localization. Put anything testable here. |
| `Sources/atb` | The command-line tool used by hooks and scripts. |
| `Sources/AgentTouchbar` | The menu bar app. `TouchBar/DFR.swift` is the only file that touches private APIs. |
| `probe/` | A standalone tool that checks the private APIs and Touch Bar wake behavior on real hardware. |
| `docs/DESIGN.md` | Architecture and design decisions. |

## Guidelines

- **Tests.** Logic changes in `AgentTouchbarCore` need unit tests. UI and private-API changes should say in the PR which Mac model and macOS version you tested on.
- **Formatting.** Run `swift format --in-place --recursive Sources Tests probe Package.swift`. CI runs `swift format lint --strict`.
- **Localization.** Every user-facing string goes through `L("English text {0}", value)` as a single-line literal, with a Simplified Chinese entry in `Sources/AgentTouchbarCore/Localization`. `LocalizationTests` fails if a translation is missing, unused, or has different placeholders. Log messages stay in plain English.
- **Hooks never fail.** `atb hook ...` must always exit 0, even when the app is not running, because a failing hook interrupts Claude Code or Codex.
- **Commits.** Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`, ...). Keep each commit focused.
- **Changelog.** Add user-visible changes to the "Unreleased" section of `CHANGELOG.md`.

## Pull requests

1. Fork and create a branch from `main`.
2. Make the change with tests.
3. Make sure CI passes.
4. Open a pull request and fill in the template.

## Releasing (maintainers)

1. Move the "Unreleased" entries in `CHANGELOG.md` under a new version heading.
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The `Release` workflow builds the app and publishes a GitHub Release with notes from the changelog.
