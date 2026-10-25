import Foundation

// Wire format between the atb CLI and the menu bar app (HTTP + JSON, 127.0.0.1 only).
//
//   POST /v1/agent       AgentEvent          → 200 {}
//   POST /v1/permission  PermissionRequest   → 200 PermissionResponse (returns once you tap on the Touch Bar)
//   POST /v1/notify      NotifyRequest       → 200 {}
//   GET  /v1/health                          → 200 {"ok":true}
//
// Every request must carry `Authorization: Bearer <token>`; the token lives in ~/.config/agentTouchbar/token.

public enum AgentState: String, Codable, Sendable {
    case idle  // session started, waiting for input
    case running  // working
    case waiting  // waiting for approval or a reply
    case done  // turn finished
    case ended  // session ended
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var agent: String  // claude / codex / other
    public var session: String
    public var state: AgentState
    public var detail: String?
    public var cwd: String?
    /// TERM_PROGRAM, used to jump back to the right terminal
    public var terminal: String?

    public init(
        agent: String, session: String, state: AgentState, detail: String? = nil,
        cwd: String? = nil, terminal: String? = nil
    ) {
        self.agent = agent
        self.session = session
        self.state = state
        self.detail = detail
        self.cwd = cwd
        self.terminal = terminal
    }
}

public struct PermissionRequestMessage: Codable, Equatable, Sendable {
    public var agent: String
    public var session: String
    public var tool: String
    public var summary: String
    public var cwd: String?
    public var terminal: String?
    /// Maximum wait in seconds
    public var wait: Int

    public init(
        agent: String, session: String, tool: String, summary: String, cwd: String? = nil,
        terminal: String? = nil, wait: Int
    ) {
        self.agent = agent
        self.session = session
        self.tool = tool
        self.summary = summary
        self.cwd = cwd
        self.terminal = terminal
        self.wait = wait
    }
}

public enum PermissionDecision: String, Codable, Sendable {
    case allow
    case deny
    /// No decision; the terminal asks as usual
    case none
}

public struct PermissionResponse: Codable, Equatable, Sendable {
    public var decision: PermissionDecision
    public init(decision: PermissionDecision) { self.decision = decision }
}

public struct NotifyRequest: Codable, Equatable, Sendable {
    public var id: String?
    public var kind: String?
    public var title: String
    public var detail: String?
    public var icon: String?
    public var color: String?
    public var priority: Int?
    public var ttl: Double?
    public var actions: [AlertAction]?

    public init(
        id: String? = nil, kind: String? = nil, title: String, detail: String? = nil, icon: String? = nil,
        color: String? = nil, priority: Int? = nil, ttl: Double? = nil, actions: [AlertAction]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.icon = icon
        self.color = color
        self.priority = priority
        self.ttl = ttl
        self.actions = actions
    }
}

// MARK: - Claude Code / Codex hook input

/// Claude Code and Codex share roughly the same hook input format; only the fields we use are decoded.
public struct HookInput: Decodable, Sendable {
    public var hookEventName: String
    public var sessionID: String?
    public var cwd: String?
    public var toolName: String?
    public var toolInput: [String: ConfigValue]?
    public var message: String?
    public var notificationType: String?
    public var lastAssistantMessage: String?
    public var prompt: String?

    enum CodingKeys: String, CodingKey {
        case cwd, message, prompt
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try c.decode(String.self, forKey: .hookEventName)
        sessionID = try? c.decodeIfPresent(String.self, forKey: .sessionID)
        cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
        toolName = try? c.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try? c.decodeIfPresent([String: ConfigValue].self, forKey: .toolInput)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        notificationType = try? c.decodeIfPresent(String.self, forKey: .notificationType)
        lastAssistantMessage = try? c.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        prompt = try? c.decodeIfPresent(String.self, forKey: .prompt)
    }

    public static func decode(_ data: Data) throws -> HookInput {
        try JSONDecoder().decode(HookInput.self, from: data)
    }

    /// One-line description of a permission request, e.g. `Bash: rm -rf build`
    public var toolSummary: String {
        let tool = toolName ?? L("Tool")
        guard let input = toolInput else { return tool }
        for key in ["command", "file_path", "path", "url", "pattern", "description"] {
            if let value = input[key] {
                if let text = value.string { return "\(tool): \(Text.oneLine(text))" }
                // Codex may send command as an array
                if let list = value.array?.compactMap(\.string), !list.isEmpty {
                    return "\(tool): \(Text.oneLine(list.joined(separator: " ")))"
                }
            }
        }
        return tool
    }
}

public enum HookMapping {
    /// Maps a hook call to a state event. Permission requests are handled separately and return nil.
    public static func event(agent: String, input: HookInput, terminal: String?) -> AgentEvent? {
        let session = input.sessionID ?? "default"
        func make(_ state: AgentState, _ detail: String?) -> AgentEvent {
            AgentEvent(
                agent: agent, session: session, state: state,
                detail: detail.map { Text.truncate(Text.oneLine($0), 80) },
                cwd: input.cwd, terminal: terminal)
        }

        switch input.hookEventName {
        case "SessionStart":
            return make(.idle, nil)
        case "UserPromptSubmit":
            return make(.running, input.prompt)
        case "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact":
            return make(.running, input.toolName.map { _ in input.toolSummary })
        case "PermissionRequest":
            return nil
        case "Notification":
            if input.notificationType == "idle_prompt" {
                return make(.done, input.message)
            }
            return make(.waiting, input.message)
        case "Stop", "StopFailure":
            return make(.done, input.lastAssistantMessage)
        case "SessionEnd":
            return make(.ended, nil)
        default:
            return nil
        }
    }

    /// Legacy Codex `notify` setting: the JSON arrives as the last command-line argument.
    public static func codexNotifyEvent(json: Data, terminal: String?) -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let type = object["type"] as? String
        else { return nil }
        let session = (object["thread-id"] as? String) ?? (object["turn-id"] as? String) ?? "codex"
        let message = object["last-assistant-message"] as? String
        let cwd = object["cwd"] as? String
        switch type {
        case "agent-turn-complete":
            return AgentEvent(
                agent: "codex", session: session, state: .done,
                detail: message.map { Text.truncate(Text.oneLine($0), 80) }, cwd: cwd, terminal: terminal)
        case "approval-requested":
            return AgentEvent(
                agent: "codex", session: session, state: .waiting,
                detail: L("Waiting for approval"), cwd: cwd, terminal: terminal)
        default:
            return nil
        }
    }

    /// Output for the PermissionRequest hook. `.none` prints nothing so the terminal handles it.
    public static func permissionOutput(_ decision: PermissionDecision) -> String? {
        let decisionObject: [String: Any]
        switch decision {
        case .allow:
            decisionObject = ["behavior": "allow"]
        case .deny:
            decisionObject = ["behavior": "deny", "message": L("Denied on the Touch Bar")]
        case .none:
            return nil
        }
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionObject,
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
