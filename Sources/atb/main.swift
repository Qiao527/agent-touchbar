import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AgentTouchbarCore

// atb：给 Claude Code、Codex 和你自己的脚本用的命令行工具，把事件发给菜单栏程序。
//
// hook 模式下绝不能报错退出：hook 失败会打断 Claude Code / Codex 的正常流程。
// 程序没运行、网络错误、输入看不懂时，一律安静地退出 0。

let usage = """
用法：
  atb hook claude              作为 Claude Code 的 hook（从标准输入读取 JSON）
  atb hook codex               作为 Codex 的 hook（从标准输入读取 JSON）
  atb codex-notify '<json>'    作为 Codex 旧版 notify 命令
  atb notify --title 标题 [--detail 说明] [--icon sf:bell] [--color orange]
             [--ttl 秒] [--priority 数字] [--id 标识]
  atb status                   检查菜单栏程序是否在运行
  atb init                     生成默认配置文件 ~/.config/agentTouchbar/config.yaml
  atb hooks claude|codex       打印 hook 配置，复制到对应的配置文件里
  atb set-key                  把 AI 接口的 API key 存进钥匙串
  atb set-secret 名字          把一段敏感文本（如银行卡号）存进钥匙串，供"常用文本"组件使用
"""

// MARK: - 与菜单栏程序通信

/// 在回调线程写入、主线程读取；读取发生在 semaphore 之后，不会同时访问
final class ResponseBox: @unchecked Sendable {
    var data: Data?
}

struct Client {
    let port: Int
    let token: String?

    init() {
        let config = (try? String(contentsOf: Paths.configFile, encoding: .utf8))
            .flatMap { try? AppConfig.parse(yaml: $0) } ?? .default
        port = config.server.port
        token = Token.read()
    }

    /// 发送请求并等待结果；失败时返回 nil
    func send<Body: Encodable>(_ path: String, _ body: Body?, method: String = "POST",
                               timeout: TimeInterval = 3) -> Data? {
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

/// 用来跳回终端：GUI 程序启动的终端会带上 __CFBundleIdentifier（例如 VS Code、iTerm2）
func terminalIdentifier() -> String? {
    let env = ProcessInfo.processInfo.environment
    return env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"]
}

// MARK: - 命令

func runHook(agent: String) -> Never {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = try? HookInput.decode(data) else { exit(0) }
    let client = Client()

    if input.hookEventName == "PermissionRequest" {
        let config = (try? String(contentsOf: Paths.configFile, encoding: .utf8))
            .flatMap { try? AppConfig.parse(yaml: $0) } ?? .default
        guard config.agents.permissionOnTouchbar else { exit(0) }

        let wait = max(5, min(config.agents.permissionWait, 300))
        let message = PermissionRequestMessage(
            agent: agent, session: input.sessionID ?? "default", tool: input.toolName ?? "工具",
            summary: input.toolSummary, cwd: input.cwd, terminal: terminalIdentifier(), wait: wait)
        guard let reply = client.send("/v1/permission", message, timeout: TimeInterval(wait) + 5),
              let response = try? JSONDecoder().decode(PermissionResponse.self, from: reply),
              let output = HookMapping.permissionOutput(response.decision) else { exit(0) }
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
          let event = HookMapping.codexNotifyEvent(json: json, terminal: terminalIdentifier()) else { exit(0) }
    _ = Client().send("/v1/agent", event)
    exit(0)
}

func runNotify(_ arguments: [String]) -> Never {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--"), index + 1 < arguments.count else {
            fail("无法识别的参数：\(key)\n\n\(usage)")
        }
        options[String(key.dropFirst(2))] = arguments[index + 1]
        index += 2
    }
    guard let title = options["title"] else { fail("缺少 --title\n\n\(usage)") }
    let request = NotifyRequest(
        id: options["id"], kind: options["kind"], title: title, detail: options["detail"],
        icon: options["icon"], color: options["color"],
        priority: options["priority"].flatMap(Int.init), ttl: options["ttl"].flatMap(Double.init))
    guard Client().send("/v1/notify", request) != nil else {
        fail("发送失败：agentTouchbar 没有运行，或者 token 不对")
    }
    exit(0)
}

func runStatus() -> Never {
    let client = Client()
    guard client.token != nil else { fail("还没有 token：请先启动 agentTouchbar") }
    guard client.send("/v1/health", Optional<String>.none, method: "GET") != nil else {
        fail("agentTouchbar 没有响应（端口 \(client.port)）")
    }
    print("agentTouchbar 正在运行（端口 \(client.port)）")
    exit(0)
}

func runInit() -> Never {
    let url = Paths.configFile
    if FileManager.default.fileExists(atPath: url.path) {
        print("配置文件已存在：\(url.path)")
        exit(0)
    }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DefaultConfig.yaml.write(to: url, atomically: true, encoding: .utf8)
        print("已生成：\(url.path)")
        exit(0)
    } catch {
        fail("写入失败：\(error.localizedDescription)")
    }
}

func runHooks(_ agent: String?) -> Never {
    let atb = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        ?? "/Applications/agentTouchbar.app/Contents/MacOS/atb"
    switch agent {
    case "claude":
        print("""
        # 把下面的内容合并到 ~/.claude/settings.json 的 "hooks" 字段里：
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
        print("""
        # 把下面的内容加到 ~/.codex/config.toml，然后在 Codex 里运行 /hooks 信任这些 hook：
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
        fail("用法：atb hooks claude 或 atb hooks codex")
    }
    exit(0)
}

/// 用系统自带的 security 命令写钥匙串，它会提示你输入内容，不会出现在命令历史里
func runKeychain(service: String, account: String) -> Never {
    #if os(macOS)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["add-generic-password", "-U", "-s", service, "-a", account, "-w"]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 { print("已保存到钥匙串（服务名 \(service)，账户 \(account)）") }
        exit(process.terminationStatus)
    } catch {
        fail("无法运行 security：\(error.localizedDescription)")
    }
    #else
    fail("钥匙串只在 macOS 上可用")
    #endif
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - 入口

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
    guard let name = arguments.dropFirst().first else { fail("用法：atb set-secret 名字") }
    runKeychain(service: "agentTouchbar.snippet", account: name)
case "-h", "--help", "help", nil:
    print(usage)
    exit(0)
default:
    fail("未知命令：\(arguments[0])\n\n\(usage)")
}
