# Portfolio positioning

agentTouchbar is best presented as an experimental native macOS and developer-tools project. Its strongest evidence is architectural separation, privacy-sensitive local integration, explicit failure handling, and reproducible tests. It is not a hosted full-stack service or a hardware-validated product yet.

## Resume wording supported by the repository

> Led the design and AI-assisted implementation of a Swift macOS automation prototype, separating an AppKit menu bar UI from a portable core with YAML scene rules, an authenticated loopback HTTP API, and Claude Code/Codex permission hooks.

> Hardened HTTP framing, configuration validation, command deadlines, and installer rollback; added a shared verification workflow covering 61 Swift tests, 9 CLI integration tests, and 5 isolated installer tests.

Use the first-person verbs only for work you actually owned and can explain. Keep the existing AI-assistance disclosure. Avoid implying that every line was hand-written, that the product has users, or that the prototype has been deployed to production.

## Evidence to show in an interview

| Engineering decision | Evidence | Tradeoff to explain |
| --- | --- | --- |
| Isolate platform APIs | `Package.swift`, `Sources/AgentTouchbarCore`, `Sources/AgentTouchbar` | Linux tests accelerate core work but cannot validate AppKit, permissions, or hardware |
| Authenticated local IPC | `HTTP.swift`, `AgentServices.swift`, `SECURITY.md` | Loopback plus bearer authentication protects the endpoint boundary, not a compromised user account |
| Fail-safe hooks | `Sources/atb/main.swift`, `scripts/smoke-test.py` | Unavailable UI returns no permission decision so the agent can fall back to its terminal prompt |
| Validate before reload | `Config.swift`, `ConfigStore` | Unsafe input is rejected and the last working configuration remains active |
| Bound subprocess execution | `CommandRunner.swift`, `RobustnessTests.swift` | Output and the launched process are bounded; arbitrary trusted commands are not sandboxed |
| Recover from installer failures | `scripts/install.sh`, `scripts/test-installer.py` | Stage and verify before replacement; recover both the old bundle and CLI link on failure |

## Milestones for a stronger portfolio entry

1. Link passing Linux and macOS CI for the exact published commit.
2. Merge the reviewed changes into the default branch so visitors see the verified implementation and current documentation.
3. Record a short real-hardware demo showing an alert, a scene transition, and one agent permission request. Do not substitute a mockup for hardware evidence.
4. Publish a prerelease with reproducible installation instructions and clearly stated signing and compatibility limitations.
5. Explain one failure found during testing and the regression test that prevents it. Add measured latency, resource use, or user feedback only after collecting that evidence.

A public prototype can be useful before all these milestones are complete, provided its limitations are visible. Calling it production-ready, deployed at scale, fully hardware-compatible, or proven to improve productivity is not supported by the current evidence.
