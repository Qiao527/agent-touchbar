# Security

agentTouchbar runs with access to sensitive things: your text messages (for verification codes), your clipboard, and a local endpoint that can approve actions for Claude Code and Codex. This document describes what it does with that access and how to report a problem.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub Security Advisories](https://github.com/Qiao527/agent-touchbar/security/advisories/new) rather than in a public issue. I aim to reply within 7 days.

## Threat model

The trust boundary is your macOS user account. agentTouchbar does not try to defend against malware already running as you; such a process could read your messages and Keychain-unlocked secrets directly.

### Local HTTP server

`atb` talks to the app over HTTP so that hooks stay simple and fast.

- The server binds to `127.0.0.1` only and rejects connections from non-loopback addresses.
- Every request needs a bearer token. The token is 192 random bits, generated on first launch and stored at `~/.config/agentTouchbar/token` with mode `0600`. It is compared in constant time.
- Requests over 1 MB are rejected; the parser only accepts `Content-Length` bodies.

### Approving agent actions from the Touch Bar

- Tapping **Allow** is equivalent to approving the prompt in your terminal. Claude Code still evaluates its deny and ask rules after an allow decision.
- If you do not tap within `agents.permission_wait` seconds (default 30), `atb` returns no decision and the agent asks in the terminal as usual. A missing or crashed app also falls back to the terminal; hooks never fail loudly.

### Verification codes

- The Messages database is opened read-only and requires Full Disk Access, which you grant explicitly.
- Codes are never logged. When pasted, they are marked with `org.nspasteboard.ConcealedType` so clipboard managers (including agentTouchbar's own history) skip them, and the clipboard is cleared after `verification_codes.clear_clipboard_after` seconds if it still holds the code.

### Clipboard history

Kept in memory only, capped at `clipboard.max_items`, cleared on quit. Items marked concealed or transient (for example by 1Password) are skipped.

### Secrets

The AI API key and sensitive snippets are stored in the macOS Keychain (`atb set-key`, `atb set-secret`). Do not put secrets in `config.yaml`.

### Commands in the config file

`buttons`, `script`, and alert actions run shell commands from `config.yaml`. Treat the config file like code: do not paste one you have not read.

### Data sent off the machine

| Feature | What is sent | Where |
|---|---|---|
| AI widget, page summary | The selected text or page text | The `ai.base_url` you configure |
| Weather | Latitude and longitude from your config | api.open-meteo.com |
| Page translation | The current page URL | translate.google.com |
| Spotify artwork | Artwork URL provided by Spotify | Spotify's CDN |

Nothing else leaves the machine. There is no telemetry.

### Private APIs

Global Touch Bar display uses undocumented frameworks (`DFRFoundation`, `DFRBrightness`). They are looked up dynamically; if a macOS update removes them, the app degrades instead of crashing. This also means the app cannot be distributed through the Mac App Store.
