# Project review

This review covers the Swift package, local HTTP boundary, CLI integration, configuration loading, shared command execution, macOS service lifecycle, installation scripts, CI, release packaging, and English documentation. The project is a native macOS app with a local service, not a hosted full-stack web application.

## Changes from the review

| Area | Finding | Change and verification |
| --- | --- | --- |
| HTTP parsing | Duplicate headers, unsupported transfer encoding, malformed lines, and oversized declared bodies were accepted or held open | Strict framing and header checks; regression tests cover fragments, binary bodies, duplicate authorization, and framing errors |
| Authentication | Token writes could fail silently | Exclusive private file creation and propagated errors; persistence and failure tests |
| Configuration | Negative limits, nonfinite values, invalid ports, malformed scene conditions, and duplicate widgets could reach runtime code | Validation before config replacement; regression cases cover invalid input and valid boundaries |
| Runtime conversions | Floating-point conversion and negative clipboard limits could trap | Safe conversions and bounded capacity; regression tests |
| CLI hooks | Spaces or quotes in installation paths broke generated commands | Shell quoting followed by JSON/TOML encoding; executable-copy integration test |
| Permission hooks | Fail-safe behavior had little end-to-end coverage | Local fixture exercises both agents, allow/deny/no-decision, invalid authentication, missing app, and malformed input |
| Commands | Closed output streams could bypass the timeout and output could grow without bound | Shared core runner with nonblocking drains, bounded capture, wall-clock timeout, and regression tests |
| Calendar | Disabled configuration still requested access; stale callbacks could restart polling | Enable/disable lifecycle, callback generation checks, observer cleanup, and alert-history pruning; macOS validation required |
| App startup | Invalid first configuration could prevent defaults from being applied | Apply safe defaults before attempting the first reload; macOS validation required |
| Local service | Incomplete connections and permission wait inputs had no complete resource bounds | Connection cap, receive deadline, maximum connection lifetime, and clamped permission waits; macOS validation required |
| AI client | A non-success HTTP response containing choices could be reported as success | Require a successful HTTP status before accepting content; macOS validation required |
| Installation | The old app was deleted before a replacement could be verified | Staging, signature verification, and rollback; isolated mock tests verify success, failure recovery, and symlink handling |
| Delivery | Release builds skipped packaged CLI smoke checks and tag/version consistency | Shared verification, packaged CLI checks, version/changelog gate, and documented acceptance procedure |
| Language | UI followed system language and the default translation prompt targeted Chinese | English default; explicit Chinese and system-language opt-ins remain available |

## Validation boundaries

Linux can validate the core and CLI, strict formatting, installer file operations with mocked macOS tools, and workflow structure. It cannot compile AppKit, exercise the real Network framework listener, grant macOS permissions, validate a Developer ID signature, notarize an app, or test private Touch Bar APIs. Those checks must pass on macOS before treating a release as ready for end users.

The existing Chinese localization and translation fixtures remain intentional optional compatibility features. English is the default, and all new product documentation and review material is in English.

The command runner limits the launched process and captured output; it does not isolate arbitrary trusted configuration commands or supervise every detached descendant. The trust boundary remains the current macOS user account, as documented in `SECURITY.md`.

Real Touch Bar hardware behavior and notarized distribution remain unverified requirements. No release tag should imply these have passed without recorded evidence.
