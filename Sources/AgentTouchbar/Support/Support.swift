import AppKit
import AgentTouchbarCore

// MARK: - 主线程

/// 从任意线程切回主线程执行
func onMain(_ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
}

/// 在主线程上的重复定时器
@MainActor
func repeatingTimer(_ interval: TimeInterval, fireNow: Bool = true,
                    _ work: @escaping @MainActor () -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in
        MainActor.assumeIsolated { work() }
    }
    timer.tolerance = interval * 0.1
    RunLoop.main.add(timer, forMode: .common)
    if fireNow { work() }
    return timer
}

// MARK: - 日志

enum Log {
    private static let queue = DispatchQueue(label: "agentTouchbar.log")

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            let url = Paths.logFile
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 日志超过 2 MB 就从头开始
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
    }
}

// MARK: - 运行命令

enum Shell {
    private static let queue = DispatchQueue(label: "agentTouchbar.shell", attributes: .concurrent)

    struct Result {
        var status: Int32
        var output: String
        var error: String
    }

    /// 在后台运行程序，结果回到主线程
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15,
                    completion: (@MainActor (Result) -> Void)? = nil) {
        queue.async {
            let result = runSync(executable, arguments, timeout: timeout)
            if let completion { onMain { completion(result) } }
        }
    }

    /// 用登录 shell 运行一段命令，这样能用到你在 .zshrc 里配置的 PATH
    static func shell(_ command: String, timeout: TimeInterval = 30,
                      completion: (@MainActor (Result) -> Void)? = nil) {
        run("/bin/zsh", ["-lc", command], timeout: timeout, completion: completion)
    }

    static func osascript(_ source: String, timeout: TimeInterval = 5,
                          completion: (@MainActor (Result) -> Void)? = nil) {
        run("/usr/bin/osascript", ["-e", source], timeout: timeout, completion: completion)
    }

    static func runSync(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        // 先读输出再等待退出，避免输出太多把管道塞满
        let group = DispatchGroup()
        var outData = Data(), errData = Data()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let deadline = DispatchTime.now() + timeout
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return Result(status: -2, output: "", error: "超时")
        }
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      output: String(data: outData, encoding: .utf8) ?? "",
                      error: String(data: errData, encoding: .utf8) ?? "")
    }

    /// AppleScript 字符串转义
    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

// MARK: - 键盘和粘贴

@MainActor
enum Keyboard {
    /// 发送快捷键，需要"辅助功能"权限
    static func send(_ combo: KeyCombo) {
        guard Permissions.accessibility(prompt: true) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.shift { flags.insert(.maskShift) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }
        let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func send(_ text: String) {
        if let combo = KeyCombo.parse(text) { send(combo) }
    }

    /// 写入剪贴板并粘贴到当前输入框。concealed 为 true 时，剪贴板管理工具（包括我们自己）会忽略这条内容
    static func paste(_ text: String, concealed: Bool = false) {
        copy(text, concealed: concealed)
        // 等剪贴板写入生效
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { send(KeyCombo(command: true, keyCode: 0x09)) }
        }
    }

    static func copy(_ text: String, concealed: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        if concealed {
            board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }
    }

    /// 系统按键（亮度、媒体键），和 MTMR 的做法一样
    static func systemKey(_ key: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    static let brightnessUp: Int32 = 2      // NX_KEYTYPE_BRIGHTNESS_UP
    static let brightnessDown: Int32 = 3    // NX_KEYTYPE_BRIGHTNESS_DOWN
}

// MARK: - 权限

@MainActor
enum Permissions {
    private static var prompted = false

    static func accessibility(prompt: Bool) -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted && prompt && !prompted {
            prompted = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return trusted
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 钥匙串

enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 颜色和图标

extension NSColor {
    static func from(_ text: String?, fallback: NSColor = .labelColor) -> NSColor {
        guard let rgb = RGBColor.parse(text) else { return fallback }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

enum Icon {
    /// `sf:符号名` → SF Symbols；其他当作图片路径
    static func image(_ spec: String?, size: CGFloat = 15) -> NSImage? {
        guard let spec, !spec.isEmpty else { return nil }
        if spec.hasPrefix("sf:") {
            let name = String(spec.dropFirst(3))
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        let image = NSImage(contentsOfFile: Paths.expand(spec))
        image?.size = NSSize(width: size + 9, height: size + 9)
        return image
    }
}

// MARK: - 跳回终端

@MainActor
enum AppActivator {
    static let terminalBundleIDs: [String: String] = [
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
        "vscode": "com.microsoft.VSCode",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "Hyper": "co.zeit.hyper",
    ]

    /// terminal 可以是 bundle id，也可以是 TERM_PROGRAM 的值
    static func activate(terminal: String?) {
        guard let terminal else { return }
        let bundleID = terminalBundleIDs[terminal] ?? terminal
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func activate(appNamed name: String) {
        let lower = name.lowercased()
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == lower || $0.bundleIdentifier?.lowercased() == lower
        }) {
            app.activate()
        }
    }
}
