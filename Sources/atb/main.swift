import AgentTouchbarCore
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// atb: command-line tool for Claude Code, Codex and your own scripts. It forwards events to the menu bar app.
//
// Hook mode must never exit with an error: a failing hook disrupts Claude Code / Codex.
// If the app is not running, the network fails or the input is unreadable, exit 0 quietly.

let usage = [
    L("Usage:"),
    "  atb hook claude              " + L("Run as a Claude Code hook (reads JSON from stdin)"),
    "  atb hook codex               " + L("Run as a Codex hook (reads JSON from stdin)"),
    "  atb codex-notify '<json>'    " + L("Run as the legacy Codex notify command"),
    "  atb notify " + L("--title <title> [--detail <text>] [--icon sf:bell] [--color orange]"),
    "             " + L("[--ttl <seconds>] [--priority <number>] [--id <id>]"),
    "  atb status                   " + L("Check whether the menu bar app is running"),
    "  atb init                     " + L("Create the default config file ~/.config/agentTouchbar/config.yaml"),
    "  atb hooks claude|codex       " + L("Print the hook config to paste into the agent's config file"),
    "  atb set-key                  " + L("Store the AI API key in the Keychain"),
    "  atb set-secret <name>        "
        + L("Store sensitive text (e.g. a card number) in the Keychain for the Snippets widget"),
].joined(separator: "\n")

// MARK: - Talking to the menu bar app

/// Written on the callback thread, read on the main thread after the semaphore, so access never overlaps.
final class ResponseBox: @unchecked Sendable {
    var data: Data?
}

struct Client {
    let port: Int
    let token: String?

    init() {
        let config =
            (try? String(contentsOf: Paths.configFile, encoding: .utf8))
            .flatMap { try? AppConfig.parse(yaml: $0) } ?? .default
        port = config.server.port
        token = Token.read()
    }

    /// Sends a request and waits for the result; returns nil on failure.
    func send<Body: Encodable>(
        _ path: String, _ body: Body?, method: String = "POST",
        timeout: TimeInterval = 3
    ) -> Data? {
        guard let token, let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { box.data = data }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 1) == .timedOut { task.cancel() }
        return box.data
    }
}

/// Used to jump back to the terminal: terminals launched from a GUI app carry __CFBundleIdentifier (e.g. VS Code, iTerm2).
func terminalIdentifier() -> String? {
    let env = ProcessInfo.processInfo.environment
    return env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"]
}

// MARK: - Commands

func runHook(agent: String) -> Never {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = try? HookInput.decode(data) else { exit(0) }
    let client = Client()

    if input.hookEventName == "PermissionRequest" {
        let config =
            (try? String(contentsOf: Paths.configFile, encoding: .utf8))
            .flatMap { try? AppConfig.parse(yaml: $0) } ?? .default
        guard config.agents.permissionOnTouchbar else { exit(0) }

        let wait = max(5, min(config.agents.permissionWait, 300))
        let message = PermissionRequestMessage(
            agent: agent, session: input.sessionID ?? "default", tool: input.toolName ?? L("Tool"),
            summary: input.toolSummary, cwd: input.cwd, terminal: terminalIdentifier(), wait: wait)
        guard let reply = client.send("/v1/permission", message, timeout: TimeInterval(wait) + 5),
            let response = try? JSONDecoder().decode(PermissionResponse.self, from: reply),
            let output = HookMapping.permissionOutput(response.decision)
        else { exit(0) }
        print(output)
        exit(0)
    }

    if let event = HookMapping.event(agent: agent, input: input, terminal: terminalIdentifier()) {
        _ = client.send("/v1/agent", event)
    }
    exit(0)
}

func runCodexNotify(_ arguments: [String]) -> Never {
    guard let json = arguments.last?.data(using: .utf8),
        let event = HookMapping.codexNotifyEvent(json: json, terminal: terminalIdentifier())
    else { exit(0) }
    _ = Client().send("/v1/agent", event)
    exit(0)
}

func runNotify(_ arguments: [String]) -> Never {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--"), index + 1 < arguments.count else {
            fail(L("Unrecognized argument: {0}", key) + "\n\n" + usage)
        }
        options[String(key.dropFirst(2))] = arguments[index + 1]
        index += 2
    }
    guard let title = options["title"] else { fail(L("Missing --title") + "\n\n" + usage) }
    let request = NotifyRequest(
        id: options["id"], kind: options["kind"], title: title, detail: options["detail"],
        icon: options["icon"], color: options["color"],
        priority: options["priority"].flatMap(Int.init), ttl: options["ttl"].flatMap(Double.init))
    guard Client().send("/v1/notify", request) != nil else {
        fail(L("Send failed: agentTouchbar is not running, or the token is wrong"))
    }
    exit(0)
}

func runStatus() -> Never {
    let client = Client()
    guard client.token != nil else { fail(L("No token yet: start agentTouchbar first")) }
    guard client.send("/v1/health", Optional<String>.none, method: "GET") != nil else {
        fail(L("agentTouchbar is not responding (port {0})", client.port))
    }
    print(L("agentTouchbar is running (port {0})", client.port))
    exit(0)
}

func runInit() -> Never {
    let url = Paths.configFile
    if FileManager.default.fileExists(atPath: url.path) {
        print(L("Config file already exists: {0}", url.path))
        exit(0)
    }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DefaultConfig.yaml.write(to: url, atomically: true, encoding: .utf8)
        print(L("Wrote {0}", url.path))
        exit(0)
    } catch {
        fail(L("Write failed: {0}", error.localizedDescription))
    }
}

func runHooks(_ agent: String?) -> Never {
    let atb =
        Bundle.main.executableURL?.resolvingSymlinksInPath().path
        ?? "/Applications/agentTouchbar.app/Contents/MacOS/atb"
    switch agent {
    case "claude":
        let note = L("Merge the following into the \"hooks\" field of ~/.claude/settings.json:")
        print(
            """
            # \(note)
            {
              "hooks": {
                "SessionStart":      [{ "hooks": [{ "type": "command", "command": "\(atb) hook claude" }] }],
                "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "\(atb) hook claude" }] }],
                "PreToolUse":        [{ "matcher": "*", "hooks": [{ "type": "command", "command": "\(atb) hook claude" }] }],
                "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "\(atb) hook claude", "timeout": 330 }] }],
                "Notification":      [{ "hooks": [{ "type": "command", "command": "\(atb) hook claude" }] }],
                "Stop":              [{ "hooks": [{ "type": "command", "command": "\(atb) hook claude" }] }],
                "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "\(atb) hook claude" }] }]
              }
            }
            """)
    case "codex":
        let note = L("Add the following to ~/.codex/config.toml, then run /hooks in Codex to trust these hooks:")
        print(
            """
            # \(note)
            [[hooks.SessionStart]]
            [[hooks.SessionStart.hooks]]
            type = "command"
            command = "\(atb) hook codex"

            [[hooks.UserPromptSubmit]]
            [[hooks.UserPromptSubmit.hooks]]
            type = "command"
            command = "\(atb) hook codex"

            [[hooks.PreToolUse]]
            [[hooks.PreToolUse.hooks]]
            type = "command"
            command = "\(atb) hook codex"

            [[hooks.PermissionRequest]]
            [[hooks.PermissionRequest.hooks]]
            type = "command"
            command = "\(atb) hook codex"
            timeout = 330

            [[hooks.Stop]]
            [[hooks.Stop.hooks]]
            type = "command"
            command = "\(atb) hook codex"
            """)
    default:
        fail(L("Usage: atb hooks claude or atb hooks codex"))
    }
    exit(0)
}

/// Writes to the Keychain via the built-in security tool, which prompts for the value so it never lands in shell history.
func runKeychain(service: String, account: String) -> Never {
    #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["add-generic-password", "-U", "-s", service, "-a", account, "-w"]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                print(L("Saved to the Keychain (service {0}, account {1})", service, account))
            }
            exit(process.terminationStatus)
        } catch {
            fail(L("Could not run security: {0}", error.localizedDescription))
        }
    #else
        fail(L("The Keychain is only available on macOS"))
    #endif
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "hook":
    runHook(agent: arguments.dropFirst().first ?? "agent")
case "codex-notify":
    runCodexNotify(Array(arguments.dropFirst()))
case "notify":
    runNotify(Array(arguments.dropFirst()))
case "status":
    runStatus()
case "init":
    runInit()
case "hooks":
    runHooks(arguments.dropFirst().first)
case "set-key":
    runKeychain(service: "agentTouchbar.ai", account: "api_key")
case "set-secret":
    guard let name = arguments.dropFirst().first else { fail(L("Usage: atb set-secret <name>")) }
    runKeychain(service: "agentTouchbar.snippet", account: name)
case "-h", "--help", "help", nil:
    print(usage)
    exit(0)
default:
    fail(L("Unknown command: {0}", arguments[0]) + "\n\n" + usage)
}
