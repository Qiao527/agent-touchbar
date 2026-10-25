# agentTouchbar Design

> **Status:** Draft v0.2 · 2026-10-25 · Target hardware: MacBook Pro 13" M1 with Touch Bar on macOS 27

agentTouchbar is a macOS menu bar app that turns the Touch Bar into a context-aware "dynamic island": quiet by default, it surfaces actionable items when something needs attention and adapts its controls to what you are doing.

## 1. Goals

- **Idle:** show a small amount of low-noise, always-on information.
- **On events:** surface relevant items automatically (verification codes, an AI agent waiting for approval, a meeting about to start) and let the user resolve them with one tap.
- **After handling:** dismiss automatically.
- **Per context:** show different controls for meetings, video, music, coding, and browsing.
- **Configurable:** widgets, layout, scene rules, appearance, and custom scripts are all user-configurable.

### Non-goals

- Distribution through the Mac App Store. Global display requires private APIs.
- Reading or uploading chat content. Verification codes are parsed locally and discarded after use.
- Support for Intel Macs or Macs without a Touch Bar.

## 2. Screen layout

The Touch Bar is split into three zones:

```
┌──────┬───────────────────────────────────────────┬──────────────────────────────┐
│ esc  │              Center: island               │        Right: status         │
│      │  Scene widgets; alerts take over when     │  Clock / battery / CPU /     │
│      │  present                                  │  volume                      │
└──────┴───────────────────────────────────────────┴──────────────────────────────┘
```

| Zone | Content |
|---|---|
| **Left** | Fixed `esc`, plus one or two optional shortcut buttons. |
| **Center (island)** | Widgets for the current scene. An incoming alert slides in from the right and covers the scene widgets. Multiple alerts queue by priority; swipe left/right to page through them. |
| **Right** | Always-on status items; content and order are configurable. Tapping expands into system controls (volume and brightness sliders). |

## 3. Features

Difficulty: 🟢 Easy · 🟡 Medium · 🔴 Hard

### 3.1 Alerts (shown only when needed)

| Feature | Data source | On the Touch Bar | Interaction | Difficulty |
|---|---|---|---|---|
| Verification codes | Watch the Messages database `~/Library/Messages/chat.db`; extract 4–8 character codes with regex | `🔑 482913 · CMB` | Tap to paste into the focused field; long-press to copy only | 🟡 |
| Claude Code / Codex status | Hooks in both tools call the local `atb` CLI | `🤖 Claude · Needs approval: rm -rf build` | Allow / Deny / Jump to terminal | 🟡 |
| Upcoming meeting | EventKit calendar data; parse meeting links | `📅 In 5 min · Weekly sync` | Tap to open the meeting link | 🟡 |
| Download finished | FSEvents on `~/Downloads` | `⬇️ report.pdf downloaded` | Open / Show in Finder | 🟢 |
| Low battery | IOKit power source info | `🔋 18%` (blinking) | Tap to enable Low Power Mode | 🟢 |
| Low AirPods battery | Bluetooth device battery (approach unverified, see §12) | `🎧 L 10%` | — | 🟡 |
| Pomodoro / hydrate / stand up | Internal timers | `🍅 Time's up` | Break / Another round / Snooze | 🟢 |

### 3.2 Scenes (automatic context switching)

| Scene | Trigger | Content | Difficulty |
|---|---|---|---|
| Meeting | Frontmost app is Tencent Meeting (腾讯会议), Feishu (飞书), or Zoom, or the microphone is in use | Mute, camera, meeting timer, leave meeting | 🔴 |
| Video | A `<video>` element is playing in the browser | Scrubber, playback speed, skip intro | 🔴 |
| Music | Spotify is playing | Album art, scrolling title, previous, play/pause, next, volume | 🟢 |
| Coding | Frontmost app is a terminal or editor | Agent status, current git branch, command buttons | 🟡 |
| Browsing | Frontmost app is Chrome or Safari | Translate page, summarize article, tab list | 🔴 |

### 3.3 One-tap actions

| Feature | Implementation | Difficulty |
|---|---|---|
| Clipboard history (last 3–5 items) | Poll `NSPasteboard.changeCount` | 🟢 |
| Snippets (email, phone, address, card number) | Config file; sensitive values in Keychain | 🟢 |
| Switch audio output | CoreAudio default output device | 🟢 |
| Do Not Disturb | Run a Shortcut (`shortcuts run`) | 🟢 |
| Dark mode / lock screen / screenshot | AppleScript, `pmset`, `screencapture` | 🟢 |
| AI translate / rewrite / explain selected text | Read selection via Accessibility API, call an AI API, show the result in a floating panel | 🟡 |

### 3.4 Glanceable status

| Feature | Data source | Difficulty |
|---|---|---|
| Next event and countdown | EventKit | 🟢 |
| Weather | [Open-Meteo](https://open-meteo.com/) (free, no API key) | 🟢 |
| Multiple time zones | System time zone data | 🟢 |
| CPU and memory | `host_statistics` | 🟢 |

## 4. Personalization

### 4.1 Config file

Location: `~/.config/agentTouchbar/config.yaml`. Changes apply on save; no restart required.

```yaml
version: 1

theme:
  accent: "#7C5CFF"        # accent color
  font: system             # system / rounded / mono
  density: comfortable     # compact / comfortable
  animations: true

layout:
  left: [esc]
  island: [next_event, now_playing]   # shown when no scene matches
  right: [clock, battery, cpu]

# Scenes: evaluated top to bottom; the first match wins
scenes:
  - name: Meeting
    when:
      app: [com.tencent.meeting, us.zoom.xos]   # bundle ids; see §12 for how to look them up
      or_mic_in_use: true
    island: [meeting_controls]

  - name: Coding
    when:
      app: [com.googlecode.iterm2, com.apple.Terminal, com.microsoft.VSCode]
    island: [agents, git_branch, dev_commands]

  - name: Night
    when:
      time: "22:00-06:00"
    hide: [cpu]
    island: [bedtime]

# Alerts: higher priority sorts first; ttl = seconds until auto-dismiss; sticky = must be handled manually
alerts:
  agent_permission: { priority: 100, sticky: true, sound: false }
  verification_code: { priority: 90, ttl: 120, tap: paste, long_press: copy }
  meeting_soon:      { priority: 80, lead_minutes: 5 }
  agent_done:        { priority: 60, ttl: 30 }
  battery_low:       { priority: 50, threshold: 20 }
  download_done:     { priority: 30, ttl: 15 }

widgets:
  - id: clock
    type: clock
    zones: [Asia/Shanghai, America/Los_Angeles]

  - id: dev_commands
    type: buttons
    items:
      - { title: "Test", icon: "sf:checkmark.seal", run: "cd ~/code/app && npm test" }
      - { title: "Deploy", icon: "sf:paperplane", run: "~/bin/deploy.sh", confirm: true }

  - id: snippets
    type: snippets
    items:
      - { title: "Email", text: "me@example.com" }
      - { title: "Bank card", keychain: "atb.card.cmb", mask: "**** 1234" }

  - id: btc
    type: script
    command: "~/bin/btc-price.sh"
    interval: 60
```

### 4.2 Script widgets

Any script can be a widget. agentTouchbar runs the script every `interval` seconds and reads one line of JSON from stdout:

```json
{ "text": "BTC 68,210", "icon": "sf:bitcoinsign.circle", "color": "#F7931A" }
```

| Field | Description |
|---|---|
| `text` | Label text |
| `icon` | `sf:<name>` (SF Symbols) or an image file path |
| `image` | Image path, rendered as a thumbnail |
| `color` | Text or background color |
| `progress` | 0–1, rendered as a progress bar |
| `alert` | Object; lets the script raise an alert |
| `tap` | Command to run on tap |

Plain-text (non-JSON) output is displayed as `text`.

### 4.3 Settings window

Menu bar icon → Settings. The window shows a to-scale Touch Bar preview with drag-and-drop widget ordering; changes are written back to `config.yaml`. This is the last phase; until then, configuration is file-only.

## 5. Architecture

```
┌───────────────────────────── agentTouchbar.app (menu bar app) ─────────────────────────────┐
│                                                                                            │
│   Sources                     Core                            TouchBar                     │
│   ┌────────────────┐        ┌──────────────────┐            ┌───────────────────────┐      │
│   │ MessagesSource │──┐     │  EventBus        │            │ TouchBarHost          │      │
│   │ AgentServer    │──┤     │  AlertQueue      │──────────▶ │ (global, private API) │      │
│   │ CalendarSource │──┼───▶ │  ContextEngine   │            │ ZoneRenderer          │      │
│   │ SpotifySource  │──┤     │  SceneMatcher    │            │ Widget views          │      │
│   │ SystemSource   │──┤     │  WidgetRegistry  │            └───────────────────────┘      │
│   │ ScriptRunner   │──┘     │  ConfigStore     │                                           │
│   └────────────────┘        └──────────────────┘                                           │
└────────────────────────────────────────────────────────────────────────────────────────────┘
          ▲
          │  atb CLI (Claude Code / Codex hooks and your own scripts send events through it)
```

### 5.1 Modules

| Module | Responsibility |
|---|---|
| **ConfigStore** | Loads `config.yaml`, watches it for changes, hot-reloads. |
| **ContextEngine** | Collects current state: frontmost app, time, music playback, microphone use, power state. |
| **SceneMatcher** | Matches current state against scene rules and decides which widgets the island shows. |
| **AlertQueue** | Alert priority, queuing, and expiry. |
| **WidgetRegistry** | Registry of all widgets. Built-in and script widgets implement the same protocol. |
| **TouchBarHost** | Renders widgets on the Touch Bar; handles animation and touch input. |
| **AgentServer** | Local HTTP server bound to `127.0.0.1`; receives events from `atb` (see §7.2). |

### 5.2 Widget protocol (draft)

```swift
protocol Widget: AnyObject {
    var id: String { get }
    /// Preferred width in points. nil means size to fit.
    var preferredWidth: CGFloat? { get }
    /// Creates the view shown on the Touch Bar.
    func makeView() -> NSView
    /// Called when config or data changes.
    func update(config: WidgetConfig, context: Context)
}
```

### 5.3 Alert model

```swift
struct Alert: Identifiable {
    let id: String
    let kind: String          // "verification_code", "agent_permission", ...
    let source: String        // "messages", "claude", "codex", ...
    var title: String
    var detail: String?
    var icon: Icon?
    var priority: Int
    var expiresAt: Date?      // nil means sticky
    var actions: [AlertAction]
}
```

### 5.4 Core/UI separation

Scene matching, code extraction, config parsing, and alert queuing live in a separate Swift package target, `AgentTouchbarCore`, with no AppKit dependency. This lets the logic build and run tests on Linux, so most changes do not require a Mac to validate.

## 6. Global Touch Bar (private API)

The public API only lets an app change the Touch Bar while it is frontmost. Displaying across all apps requires the private `DFRFoundation` framework:

| Call | Purpose |
|---|---|
| `NSTouchBar.presentSystemModalTouchBar(_:systemTrayItemIdentifier:)` | Present our Touch Bar above the system Touch Bar. |
| `DFRElementSetControlStripPresenceForIdentifier` | Add an entry button to the system Control Strip. |
| `DFRSystemModalShowsCloseBoxWhenFrontMost` | Hide the close box on the left. |

[MTMR](https://github.com/Toxblh/MTMR) and [Pock](https://github.com/pock/pock) use the same approach and serve as references.

**Research findings (2026-10-25):**

- [StripGauge](https://github.com/CodeCampusCo/stripgauge) tested `DFRElementSetControlStripPresenceForIdentifier`, `addSystemTrayItem:`, and `presentSystemModalTouchBar:systemTrayItemIdentifier:` on **macOS 26.5.2 on an M1 13"**; all work. Its design doc also notes that occupying only the left region keeps the system brightness and volume buttons, while taking the full bar means reimplementing them.
- BetterTouchTool relies on the same mechanism. Its author reported it working overall on the first macOS 27 beta, and the forum has no reports of Touch Bar breakage so far ([forum thread](https://community.folivora.ai/t/macos-27-golden-gate/47224)).
- No public record yet confirms these calls on the macOS 27 release build, so the probe in `probe/` verifies them on the target Mac.

**Layout decision:** use the full bar first (`placement: 1`) and implement brightness and volume in the right zone. If the probe shows the full-bar mode does not work, fall back to the left region only and keep the system Control Strip on the right.

## 7. Implementation notes

### 7.1 Verification codes

- On recent macOS versions, message bodies are often absent from `text` and stored in `attributedBody` (a serialized `NSAttributedString`). Parse both.
- Watch `chat.db-wal` for changes and query only messages newer than the last seen `ROWID`.
- Extraction: look for 4–8 digit or alphanumeric tokens near keywords such as `验证码` / `校验码` / `code` / `OTP`, then use the sender or a bracketed company tag in the message (`【…】`) as the source label. Rules are extensible in config.
- On tap: write to the clipboard → simulate `⌘V` → after 2 minutes, clear the clipboard if it still holds the code.
- Codes are never logged and never enter clipboard history.

### 7.2 Claude Code / Codex

A CLI, `atb`, is called by hooks in both tools:

```bash
atb hook claude   # reads Claude Code hook JSON from stdin
atb hook codex    # reads Codex hook JSON from stdin
atb notify --title "Build finished" --icon sf:hammer --ttl 20   # usable from your own scripts
```

Hook events used:

| State | Claude Code | Codex |
|---|---|---|
| Running | `UserPromptSubmit`, `PreToolUse` | `UserPromptSubmit`, `PreToolUse` |
| Awaiting approval | `PermissionRequest`, `Notification` | `PermissionRequest` |
| Turn finished | `Stop` | `Stop` (`notify` on older versions) |
| Session ended | `SessionEnd` | — |

**Allow/deny from the Touch Bar:** both tools' `PermissionRequest` hooks can return an allow/deny decision. `atb hook` blocks on the request while the Touch Bar shows Allow / Deny / Handle in terminal:

- Allow or Deny → `atb` prints the corresponding decision JSON.
- Handle in terminal, or timeout (default 60 s) → `atb` returns no decision and the terminal prompts as usual.

**Jump to terminal:** hook payloads include `cwd` and a session ID. Based on `TERM_PROGRAM`, AppleScript activates the matching iTerm2 or Terminal window; for the Codex app and Claude Desktop, the app itself is activated. Best effort.

**Git branch:** run `git branch --show-current` in the hook's `cwd`.

#### Local HTTP API

`AgentServer` exposes a small HTTP API used by `atb`.

| Endpoint | Purpose |
|---|---|
| `POST /v1/agent` | Agent status event (running, turn finished, session ended). |
| `POST /v1/permission` | Permission request. Long-polls until the user taps a choice or the timeout expires. |
| `POST /v1/notify` | Generic notification / alert. |
| `GET /v1/health` | Liveness check. |

Security:

- The server binds to `127.0.0.1` only.
- On first launch the app generates a random bearer token and stores it at `~/.config/agentTouchbar/token` with mode `0600`. Every request must send `Authorization: Bearer <token>`.

### 7.3 Spotify

- AppleScript reads the current track, artist, playback state, and artwork URL (`artwork url of current track`), and controls playback and volume.
- Requires the Automation permission (macOS prompts on first use).
- The private MediaRemote framework restricts third-party callers starting with macOS 15.4, so the app does not depend on it and integrates per app instead.
- Liking tracks requires the Spotify Web API with OAuth; deferred.

### 7.4 Calendar and meetings

- EventKit reads all calendars (requires Calendar permission).
- Meeting links are detected in location, notes, and URL fields: `meeting.tencent.com`, `vc.feishu.cn`, `zoom.us`, `meet.google.com`, `teams.microsoft.com`.
- **Meeting controls:** Tencent Meeting and Feishu have no public API, so controls simulate their keyboard shortcuts (requires Accessibility). Shortcuts are defined per app in config and are user-editable.
- **Meeting timer:** starts when the Meeting scene activates.

### 7.5 Browser and video

Chrome and Safari can both execute page JavaScript via AppleScript (requires enabling "Allow JavaScript from Apple Events" in the browser). Without a browser extension, this enables:

- Reading the tab list and switching tabs.
- Controlling `<video>` elements: position, playback speed, seeking forward (Skip intro defaults to +85 s, configurable).
- Extracting article text for AI summarization. Translation uses the browser's built-in translator or the AI backend.

If AppleScript does not work on certain sites, a browser extension is the fallback.

### 7.6 AI text actions

- Read the selection via the Accessibility API (`AXSelectedText`); fall back to simulating `⌘C`.
- Supports OpenAI, Anthropic, and local models with an OpenAI-compatible API, selected in config. API keys are stored in Keychain.
- The Touch Bar is too small for results, so they appear in a floating panel near the cursor with Replace / Copy / Close.
- Prompts are configurable; users can add their own buttons (e.g. "Rewrite as an English email").

### 7.7 System features

| Feature | Mechanism |
|---|---|
| Do Not Disturb | Run a user-created Shortcut (`shortcuts run "Toggle Focus"`). The Shortcuts widget can run any shortcut, which doubles as an extension point. |
| Dark mode | `osascript` via System Events |
| Lock screen | `pmset displaysleepnow` |
| Screenshot | `screencapture -i -c` |
| Audio output | CoreAudio `kAudioHardwarePropertyDefaultOutputDevice` |
| Battery | IOKit `IOPSCopyPowerSourcesInfo` |
| CPU/memory | `host_statistics64` |
| Download finished | FSEvents on `~/Downloads`; ignore temp files such as `.crdownload` and `.download` |

### 7.8 Clipboard

- Check `NSPasteboard.changeCount` every 0.5 s.
- Skip items marked `org.nspasteboard.ConcealedType` or `TransientType` (set by password managers such as 1Password), and skip verification codes.
- In-memory only, at most 20 items, cleared on quit. Persistence can be enabled in config.

## 8. Permissions

| Permission | Used for | Requested when |
|---|---|---|
| Full Disk Access | Reading the Messages database (verification codes) | The verification code widget is enabled |
| Accessibility | Simulated paste, meeting shortcuts, reading selected text | First use |
| Automation | Controlling Spotify, browsers, System Events | Prompted by macOS |
| Calendar | Reading events | The calendar widget is enabled |

**Note:** macOS ties these grants to the app's code signature. Ad-hoc signatures change on every build, so grants must be re-approved. Signing with a stable certificate (for example, the Apple Development certificate from a free Apple ID personal team in Xcode) avoids this.

## 9. Project structure

The project uses Swift Package Manager instead of XcodeGen: it builds with the Command Line Tools alone (no full Xcode), and GitHub Actions can build and package it directly on macOS.

```
agentTouchbar/
├── Package.swift
├── Sources/
│   ├── AgentTouchbarCore/      # AppKit-free core logic (testable on Linux)
│   ├── atb/                    # atb CLI
│   └── AgentTouchbar/          # menu bar app (App, TouchBar, Sources, Widgets, Support)
├── Tests/AgentTouchbarCoreTests/
├── Resources/Info.plist
├── scripts/                    # build-app.sh packages, install.sh installs
├── probe/                      # hardware probe
├── config/config.example.yaml  # kept in sync with built-in defaults (enforced by a test)
└── .github/workflows/build.yml # Linux: core tests; macOS 26: build, package, upload app
```

## 10. Localization

| Aspect | Approach |
|---|---|
| Keys | English strings are the keys, passed to `L("...")`. |
| Translations | Simplified Chinese tables live in `Sources/AgentTouchbarCore/Localization`. |
| Enforcement | A unit test scans the sources and fails if any `L` literal lacks a translation or if placeholders differ between the key and its translation. |
| Language selection | Follows the system language; override with `AGENT_TOUCHBAR_LANG=en\|zh`. |

## 11. Testing strategy

| Layer | How it is tested |
|---|---|
| Core logic (`AgentTouchbarCore`) | AppKit-free; unit tests run on Linux and macOS in CI. |
| CI | GitHub Actions: a Linux container (`swift:6.1`) and a `macos-26` runner. The macOS job also builds the `.app` and runs `atb` smoke tests. |
| Touch Bar / private API | Isolated in `TouchBar/DFR.swift`; verified on real hardware with the probe in `probe/`. |

## 12. Open questions

| Question | Why it matters | How to verify |
|---|---|---|
| Can the app wake the Touch Bar after it dims from inactivity? | Determines whether "show only when needed" works | Run `probe/run.sh`. Known leads below. |
| Do the `DFRFoundation` private APIs work on macOS 27? | Determines whether global display is possible | Run `probe/run.sh`. Findings in §6. |
| How to read AirPods battery level | No public API | Try `system_profiler SPBluetoothDataType` and `ioreg` on the target Mac |
| Bundle IDs and shortcuts for Tencent Meeting and Feishu | Needed for the Meeting scene | Run `osascript -e 'id of app "腾讯会议"'`; check each app's shortcut settings |
| `chat.db` schema on macOS 27 | Verification codes depend on it | Test against real data in phase 2 |

**Known leads for waking the Touch Bar:**

- `TouchBarServer`, which handles idle dimming, uses the `DFRBrightnessClient` class from `DFRBrightness.framework`, which has `turnOn` and `turnOff` methods. [TouchBarOff](https://github.com/gbili/touchbar-off) uses it to turn the Touch Bar off and on on an **M1 13" with macOS 15.5**, and uses `DFRGetStatus()` to read the state (bit `0x4` set means off).
- The public `IOPMAssertionDeclareUserActivity` declares user activity and may also wake the Touch Bar; no test record found.
- The probe tries each method in order (update content only → re-present → declare user activity → private API wake), records which one works, and measures how long the bar stays lit afterward.

**If nothing wakes it:** alerts are also mirrored to the menu bar icon (color change or badge count) and to system notifications so they are not missed.

## 13. Progress

| Phase | Scope | Status |
|---|---|---|
| **0. Feasibility** | `probe/` hardware probe | Probe ready; **waiting for a hardware run** |
| **1. Foundation** | Menu bar app, three-zone layout, config hot reload, scene matching, alert queue, `atb` and local server | Code complete, compiled in CI; not yet verified on hardware |
| **2. First widgets** | Verification codes, Claude Code/Codex (incl. allow/deny), Spotify, clock, battery, CPU | Code complete, compiled in CI; not yet verified on hardware |
| **3. Second widgets** | Calendar and meeting alerts, Pomodoro and reminders, clipboard, snippets, audio output, Shortcuts, system toggles, script widgets | Code complete, compiled in CI; not yet verified on hardware |
| **4. Third widgets** | AI text actions, weather, AirPods, download finished | Code complete, compiled in CI; not yet verified on hardware |
| **5. Hard parts** | Meeting controls, browser tabs, web video controls, page summaries | Code complete, compiled in CI; not yet verified on hardware |
| **6. Settings window** | Drag-and-drop layout, theme editor | Not started; config file only for now |

"Code complete" means the code is written, compiles in CI, and core logic has unit tests. Nothing involving Touch Bar rendering, system permissions, or third-party apps has been verified on real hardware yet.

## 14. Prerequisites

1. Install the Xcode Command Line Tools: `xcode-select --install` (needed only to build locally; not needed for the CI-built app).
2. For verification codes: on the iPhone, enable Settings → Messages → Text Message Forwarding for this Mac.
3. To keep permission grants across rebuilds: have a code signing certificate in Keychain and set `SIGN_IDENTITY` at build time (see `scripts/build-app.sh`).
