import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// MARK: - Text

public enum Text {
    /// Truncates with an ellipsis past `max` characters (each CJK character counts as one).
    public static func truncate(_ text: String, _ max: Int) -> String {
        guard max > 1, text.count > max else { return text }
        return String(text.prefix(max - 1)) + "…"
    }

    /// Collapses newlines and runs of whitespace into single spaces.
    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// Masks sensitive text such as card numbers, keeping the last 4 characters.
    public static func mask(_ text: String) -> String {
        let visible = text.suffix(4)
        return "•••• " + visible
    }

    /// Human-readable countdown between two dates.
    public static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        if seconds <= 0 { return L("now") }
        if seconds < 60 { return L("in {0} s", seconds) }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return L("in {0} min", minutes) }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? L("in {0} h", hours) : L("in {0} h {1} min", hours, rest)
    }

    /// Time remaining until a date, e.g. "12 min left".
    public static func timeLeft(until date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded()))
        if seconds < 60 { return L("{0} s left", seconds) }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return L("{0} min left", minutes) }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? L("{0} h left", hours) : L("{0} h {1} min left", hours, rest)
    }

    /// 00:00 or 1:02:03
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Paths

public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Override with AGENT_TOUCHBAR_HOME (for tests or multiple setups).
    public static var configDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["AGENT_TOUCHBAR_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: expand(custom))
        }
        return home.appendingPathComponent(".config/agentTouchbar")
    }

    public static var configFile: URL { configDirectory.appendingPathComponent("config.yaml") }
    public static var tokenFile: URL { configDirectory.appendingPathComponent("token") }
    public static var logFile: URL { configDirectory.appendingPathComponent("agentTouchbar.log") }

    public static func expand(_ path: String) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))).path }
        return path
    }
}

// MARK: - token

public enum Token {
    /// Reads the token, creating one with file mode 600 if missing.
    public static func loadOrCreate(at url: URL = Paths.tokenFile) throws -> String {
        if let existing = read(at: url) { return existing }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: 24)
        var generator = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255, using: &generator) }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        // Exclusive creation prevents replacing an existing token or following a symlink.
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            let code = errno
            if code == EEXIST, let existing = read(at: url) { return existing }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: Data(token.utf8))
        try handle.synchronize()
        try handle.close()
        return token
    }

    public static func read(at url: URL = Paths.tokenFile) -> String? {
        guard let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }
        return text
    }

    /// Constant-time comparison for equal lengths, so timing does not leak the token.
    public static func matches(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

// MARK: - Meeting links

public enum MeetingLink {
    static let hosts = [
        "meeting.tencent.com", "voovmeeting.com", "vc.feishu.cn", "vc.larksuite.com", "meetings.feishu.cn",
        "zoom.us", "zoom.com.cn", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "dingtalk.com", "meet.dingtalk.com",
    ]

    /// Finds the first meeting link in an event's location, notes or URL.
    public static func find(in texts: [String?]) -> URL? {
        // A link ends at whitespace, quotes, angle brackets or CJK punctuation
        guard
            let regex = try? NSRegularExpression(
                pattern: #"https?://[^\s<>"'，。；、）】]+"#,
                options: [.caseInsensitive])
        else { return nil }
        for text in texts.compactMap({ $0 }) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let url = URL(string: ns.substring(with: match.range)),
                    let host = url.host?.lowercased()
                else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}

// MARK: - Script widget output

/// Output of a script widget: one line of JSON, or plain text.
public struct ScriptOutput: Equatable, Sendable {
    public var text: String
    public var icon: String?
    public var image: String?
    public var color: String?
    public var progress: Double?
    public var tap: String?
    public var alert: NotifyRequest?

    public init(
        text: String, icon: String? = nil, image: String? = nil, color: String? = nil,
        progress: Double? = nil, tap: String? = nil, alert: NotifyRequest? = nil
    ) {
        self.text = text
        self.icon = icon
        self.image = image
        self.color = color
        self.progress = progress
        self.tap = tap
        self.alert = alert
    }

    public static func parse(_ output: String) -> ScriptOutput {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
            let object = try? JSONDecoder().decode(Raw.self, from: data)
        {
            return ScriptOutput(
                text: object.text ?? "", icon: object.icon, image: object.image, color: object.color,
                progress: object.progress.map { min(1, max(0, $0)) }, tap: object.tap,
                alert: object.alert)
        }
        let firstLine = trimmed.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return ScriptOutput(text: firstLine)
    }

    private struct Raw: Decodable {
        var text: String?
        var icon: String?
        var image: String?
        var color: String?
        var progress: Double?
        var tap: String?
        var alert: NotifyRequest?
    }
}

// MARK: - Clipboard history

public struct ClipboardHistory: Equatable, Sendable {
    public private(set) var items: [String] = []
    public var limit: Int

    public init(limit: Int = 20) { self.limit = limit }

    public mutating func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        let capacity = max(0, limit)
        if items.count > capacity { items.removeLast(items.count - capacity) }
    }

    public mutating func clear() { items.removeAll() }
}

// MARK: - Pomodoro

public struct Pomodoro: Equatable, Sendable {
    public enum Phase: String, Sendable { case idle, focus, rest }

    public var focusMinutes: Double
    public var restMinutes: Double
    public private(set) var phase: Phase = .idle
    public private(set) var endsAt: Date?
    public private(set) var completedRounds = 0

    public init(focusMinutes: Double = 25, restMinutes: Double = 5) {
        self.focusMinutes = focusMinutes
        self.restMinutes = restMinutes
    }

    public mutating func startFocus(at date: Date = Date()) {
        phase = .focus
        endsAt = date.addingTimeInterval(focusMinutes * 60)
    }

    public mutating func startRest(at date: Date = Date()) {
        phase = .rest
        endsAt = date.addingTimeInterval(restMinutes * 60)
    }

    public mutating func snooze(minutes: Double = 5, at date: Date = Date()) {
        endsAt = date.addingTimeInterval(minutes * 60)
    }

    public mutating func stop() {
        phase = .idle
        endsAt = nil
    }

    public func remaining(at date: Date = Date()) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(date)) }
    }

    /// When time is up, returns the finished phase and waits for a choice (phase unchanged, endsAt cleared).
    public mutating func tick(at date: Date = Date()) -> Phase? {
        guard let endsAt, date >= endsAt, phase != .idle else { return nil }
        self.endsAt = nil
        if phase == .focus { completedRounds += 1 }
        return phase
    }

    public var isWaitingForChoice: Bool { phase != .idle && endsAt == nil }
}

// MARK: - Colors

public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Accepts #RRGGBB, RRGGBB and a few common color names.
    public static func parse(_ text: String?) -> RGBColor? {
        guard let raw = text?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let named: [String: String] = [
            "red": "FF453A", "orange": "FF9F0A", "yellow": "FFD60A", "green": "30D158", "blue": "0A84FF",
            "purple": "BF5AF2", "pink": "FF375F", "gray": "8E8E93", "grey": "8E8E93", "white": "FFFFFF",
            "teal": "40C8E0",
        ]
        var hex = named[raw] ?? raw
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return RGBColor(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
