import AppKit
import AgentTouchbarCore

// MARK: - AI 接口（兼容 OpenAI Chat Completions）

@MainActor
final class AIService {
    var settings = AISettings()

    var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment[settings.apiKeyEnv], !env.isEmpty { return env }
        return Keychain.read(service: "agentTouchbar.ai", account: "api_key")
    }

    func complete(system: String, user: String, completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        let base = settings.baseURL.hasSuffix("/") ? String(settings.baseURL.dropLast()) : settings.baseURL
        guard let url = URL(string: base + "/chat/completions") else {
            return completion(.failure(AIError.message("base_url 无效")))
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": settings.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<String, Error>
            if let error {
                result = .failure(error)
            } else if let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String {
                result = .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(AIError.message("接口返回 \(status)：\(Text.truncate(text, 200))"))
            }
            onMain { completion(result) }
        }.resume()
    }

    enum AIError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }
}

// MARK: - 读取选中的文字

@MainActor
enum Selection {
    /// 先用辅助功能接口读取；读不到就模拟 ⌘C，读完恢复原来的剪贴板
    static func read(_ completion: @escaping @MainActor (String?) -> Void) {
        guard Permissions.accessibility(prompt: true) else { return completion(nil) }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let element = focused {
            var selected: CFTypeRef?
            // swiftlint:disable:next force_cast
            if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
               let text = selected as? String, !text.isEmpty {
                return completion(text)
            }
        }

        let board = NSPasteboard.general
        let previous = board.string(forType: .string)
        let before = board.changeCount
        Keyboard.send(KeyCombo(command: true, keyCode: 0x08))   // ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated {
                let text = board.changeCount != before ? board.string(forType: .string) : nil
                if let previous { Keyboard.copy(previous) }
                completion(text)
            }
        }
    }
}

// MARK: - 结果面板

/// 不抢焦点的浮动面板，显示在鼠标附近。"替换"会把结果粘贴回原来的输入框。
@MainActor
final class ResultPanel: NSObject {
    static let shared = ResultPanel()

    private var panel: NSPanel?
    private let textView = NSTextView()
    private var result = ""

    func show(title: String, text: String, canReplace: Bool) {
        result = text
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.title = title
        textView.string = text
        replaceButton?.isHidden = !canReplace

        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height - 20)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            frame.origin.x = max(screen.visibleFrame.minX, min(frame.origin.x, screen.visibleFrame.maxX - frame.width))
            frame.origin.y = max(screen.visibleFrame.minY, min(frame.origin.y, screen.visibleFrame.maxY - frame.height))
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func showLoading(_ title: String) {
        show(title: title, text: "思考中…", canReplace: false)
    }

    private var replaceButton: NSButton?

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView

        let replace = NSButton(title: "替换原文", target: self, action: #selector(replace))
        let copy = NSButton(title: "复制", target: self, action: #selector(copyResult))
        let close = NSButton(title: "关闭", target: self, action: #selector(closePanel))
        replace.keyEquivalent = "\r"
        replaceButton = replace
        let buttons = NSStackView(views: [replace, copy, close])
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        panel.contentView = content
        return panel
    }

    @objc private func replace() {
        panel?.orderOut(nil)
        Keyboard.paste(result)
    }

    @objc private func copyResult() {
        Keyboard.copy(result)
        panel?.orderOut(nil)
    }

    @objc private func closePanel() {
        panel?.orderOut(nil)
    }
}

// MARK: - 浏览器（AppleScript 执行网页里的 JavaScript）

@MainActor
enum Browser {
    enum Kind { case chrome(String), safari }

    /// 前台浏览器。Chrome 内核的浏览器（Chrome、Edge、Arc、Brave）用同一套 AppleScript
    static var front: Kind? {
        switch NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        case "com.google.Chrome": return .chrome("Google Chrome")
        case "com.microsoft.edgemac": return .chrome("Microsoft Edge")
        case "company.thebrowser.Browser": return .chrome("Arc")
        case "com.brave.Browser": return .chrome("Brave Browser")
        case "com.apple.Safari": return .safari
        default: return nil
        }
    }

    /// 在当前标签页执行 JavaScript。需要在浏览器里打开"允许 Apple 事件中的 JavaScript"
    static func run(_ javascript: String, completion: (@MainActor (String?) -> Void)? = nil) {
        guard let kind = front else { completion?(nil); return }
        let js = Shell.quote(javascript)
        let script: String
        switch kind {
        case .chrome(let name):
            script = "tell application \"\(name)\" to execute active tab of front window javascript \(js)"
        case .safari:
            script = "tell application \"Safari\" to do JavaScript \(js) in current tab of front window"
        }
        Shell.osascript(script) { result in
            if result.status != 0 { Log.error("浏览器脚本失败：\(result.error)") }
            completion?(result.status == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        }
    }

    static func tabs(_ completion: @escaping @MainActor ([String]) -> Void) {
        guard let kind = front else { return completion([]) }
        let script: String
        switch kind {
        case .chrome(let name):
            script = """
            tell application "\(name)"
                set out to ""
                repeat with t in tabs of front window
                    set out to out & (title of t) & linefeed
                end repeat
                return out
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                set out to ""
                repeat with t in tabs of front window
                    set out to out & (name of t) & linefeed
                end repeat
                return out
            end tell
            """
        }
        Shell.osascript(script) { result in
            completion(result.output.components(separatedBy: "\n").filter { !$0.isEmpty })
        }
    }

    static func selectTab(_ index: Int) {
        guard let kind = front else { return }
        switch kind {
        case .chrome(let name):
            Shell.osascript("tell application \"\(name)\" to set active tab index of front window to \(index + 1)")
        case .safari:
            Shell.osascript("tell application \"Safari\" to set current tab of front window to tab \(index + 1) of front window")
        }
    }

    static func currentURL(_ completion: @escaping @MainActor (String?) -> Void) {
        run("location.href", completion: completion)
    }

    /// 页面上面积最大的视频
    static let videoJS = """
    (function(){var v=[].slice.call(document.querySelectorAll('video')).sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight})[0];if(!v)return '';%@})()
    """

    static func video(_ body: String, completion: (@MainActor (String?) -> Void)? = nil) {
        run(videoJS.replacingOccurrences(of: "%@", with: body), completion: completion)
    }
}
