import Foundation
import Yams

// MARK: - Top-level config

public struct AppConfig: Decodable, Equatable, Sendable {
    public var version: Int
    public var theme: Theme
    public var touchbar: TouchBarSettings
    public var layout: Layout
    public var scenes: [Scene]
    public var alerts: [String: AlertRule]
    public var agents: AgentSettings
    public var verificationCodes: VerificationCodeSettings
    public var clipboard: ClipboardSettings
    public var calendar: CalendarSettings
    public var downloads: DownloadSettings
    public var battery: BatterySettings
    public var ai: AISettings
    public var server: ServerSettings
    public var widgets: [WidgetConfig]

    enum CodingKeys: String, CodingKey {
        case version, theme, touchbar, layout, scenes, alerts, agents
        case verificationCodes = "verification_codes"
        case clipboard, calendar, downloads, battery, ai, server, widgets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.value(.version, default: 1)
        theme = try c.value(.theme, default: Theme())
        touchbar = try c.value(.touchbar, default: TouchBarSettings())
        layout = try c.value(.layout, default: Layout())
        scenes = try c.value(.scenes, default: [])
        let userAlerts = try c.value(.alerts, default: [String: AlertRule]())
        alerts = AlertRule.defaults.merging(userAlerts) { _, user in user }
        agents = try c.value(.agents, default: AgentSettings())
        verificationCodes = try c.value(.verificationCodes, default: VerificationCodeSettings())
        clipboard = try c.value(.clipboard, default: ClipboardSettings())
        calendar = try c.value(.calendar, default: CalendarSettings())
        downloads = try c.value(.downloads, default: DownloadSettings())
        battery = try c.value(.battery, default: BatterySettings())
        ai = try c.value(.ai, default: AISettings())
        server = try c.value(.server, default: ServerSettings())
        widgets = try c.value(.widgets, default: [])
    }

    /// Parses YAML text. An empty file means all defaults.
    public static func parse(yaml: String) throws -> AppConfig {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        return try YAMLDecoder().decode(AppConfig.self, from: trimmed.isEmpty ? "{}" : yaml)
    }

    public static var `default`: AppConfig {
        // Unit tests guarantee the built-in default config parses
        (try? parse(yaml: DefaultConfig.yaml)) ?? (try! parse(yaml: "{}"))
    }

    /// Returns the widget config for an id. A bare type name in the layout (e.g. `clock`) means that type with no options.
    public func widget(id: String) -> WidgetConfig {
        widgets.first { $0.id == id } ?? WidgetConfig(id: id, type: id, options: Options())
    }

    public func alertRule(for kind: String) -> AlertRule {
        alerts[kind] ?? AlertRule()
    }
}

// MARK: - Sections

public struct Theme: Decodable, Equatable, Sendable {
    public var accent: String = "#7C5CFF"
    public var fontSize: Double = 13
    public var density: String = "comfortable"  // compact / comfortable
    public var animations: Bool = true

    enum CodingKeys: String, CodingKey {
        case accent, density, animations
        case fontSize = "font_size"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = try c.value(.accent, default: accent)
        fontSize = try c.value(.fontSize, default: fontSize)
        density = try c.value(.density, default: density)
        animations = try c.value(.animations, default: animations)
    }

    public var spacing: Double { density == "compact" ? 6 : 12 }
}

public struct TouchBarSettings: Decodable, Equatable, Sendable {
    /// full: the whole strip (including the system button area on the right); app_region: only the app area on the left
    public var mode: String = "full"
    /// Try to wake the Touch Bar when an alert arrives while it is dimmed
    public var wakeOnAlert: Bool = true

    enum CodingKeys: String, CodingKey {
        case mode
        case wakeOnAlert = "wake_on_alert"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.value(.mode, default: mode)
        wakeOnAlert = try c.value(.wakeOnAlert, default: wakeOnAlert)
    }
}

public struct Layout: Decodable, Equatable, Sendable {
    public var left: [String] = ["esc"]
    public var island: [String] = ["next_event", "now_playing"]
    public var right: [String] = ["clock", "battery", "volume"]

    public init() {}

    public init(left: [String], island: [String], right: [String]) {
        self.left = left
        self.island = island
        self.right = right
    }

    enum CodingKeys: String, CodingKey { case left, island, right }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        left = try c.value(.left, default: left)
        island = try c.value(.island, default: island)
        right = try c.value(.right, default: right)
    }
}

public struct AlertRule: Decodable, Equatable, Sendable {
    public var enabled: Bool = true
    public var priority: Int = 50
    /// Seconds; nil keeps the alert until it is handled
    public var ttl: Double? = 30
    public var sticky: Bool = false

    enum CodingKeys: String, CodingKey { case enabled, priority, ttl, sticky }

    public init() {}

    public init(priority: Int, ttl: Double?, sticky: Bool = false) {
        self.priority = priority
        self.ttl = ttl
        self.sticky = sticky
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)
        priority = try c.value(.priority, default: priority)
        ttl = try c.decodeIfPresent(Double.self, forKey: .ttl) ?? ttl
        sticky = try c.value(.sticky, default: sticky)
    }

    /// Effective expiry time
    public func expiry(from date: Date) -> Date? {
        guard !sticky, let ttl else { return nil }
        return date.addingTimeInterval(ttl)
    }

    public static let defaults: [String: AlertRule] = [
        AlertKind.agentPermission: AlertRule(priority: 100, ttl: nil, sticky: true),
        AlertKind.verificationCode: AlertRule(priority: 90, ttl: 120),
        AlertKind.meetingSoon: AlertRule(priority: 80, ttl: 600),
        AlertKind.agentDone: AlertRule(priority: 60, ttl: 30),
        AlertKind.pomodoro: AlertRule(priority: 55, ttl: nil, sticky: true),
        AlertKind.batteryLow: AlertRule(priority: 50, ttl: 60),
        AlertKind.reminder: AlertRule(priority: 40, ttl: 60),
        AlertKind.downloadDone: AlertRule(priority: 30, ttl: 15),
        AlertKind.custom: AlertRule(priority: 50, ttl: 30),
    ]
}

public enum AlertKind {
    public static let agentPermission = "agent_permission"
    public static let agentDone = "agent_done"
    public static let verificationCode = "verification_code"
    public static let meetingSoon = "meeting_soon"
    public static let batteryLow = "battery_low"
    public static let downloadDone = "download_done"
    public static let pomodoro = "pomodoro"
    public static let reminder = "reminder"
    public static let custom = "custom"
}

public struct AgentSettings: Decodable, Equatable, Sendable {
    /// Handle Claude Code / Codex permission requests on the Touch Bar
    public var permissionOnTouchbar: Bool = true
    /// Seconds to wait for a tap on the Touch Bar. The terminal prompt is held back meanwhile, so keep it short.
    public var permissionWait: Int = 30

    enum CodingKeys: String, CodingKey {
        case permissionOnTouchbar = "permission_on_touchbar"
        case permissionWait = "permission_wait"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        permissionOnTouchbar = try c.value(.permissionOnTouchbar, default: permissionOnTouchbar)
        permissionWait = try c.value(.permissionWait, default: permissionWait)
    }
}

public struct VerificationCodeSettings: Decodable, Equatable, Sendable {
    public var enabled: Bool = true
    /// Seconds after pasting before the clipboard is cleared (only if it still holds the code)
    public var clearClipboardAfter: Double = 120
    public var extraKeywords: [String] = []

    enum CodingKeys: String, CodingKey {
        case enabled
        case clearClipboardAfter = "clear_clipboard_after"
        case extraKeywords = "extra_keywords"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)
        clearClipboardAfter = try c.value(.clearClipboardAfter, default: clearClipboardAfter)
        extraKeywords = try c.value(.extraKeywords, default: extraKeywords)
    }
}

public struct ClipboardSettings: Decodable, Equatable, Sendable {
    public var enabled: Bool = true
    public var maxItems: Int = 20
    /// Number of items shown on the Touch Bar
    public var show: Int = 4

    enum CodingKeys: String, CodingKey {
        case enabled, show
        case maxItems = "max_items"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)
        maxItems = try c.value(.maxItems, default: maxItems)
        show = try c.value(.show, default: show)
    }
}

public struct CalendarSettings: Decodable, Equatable, Sendable {
    public var enabled: Bool = true
    public var leadMinutes: Int = 5

    enum CodingKeys: String, CodingKey {
        case enabled
        case leadMinutes = "lead_minutes"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)
        leadMinutes = try c.value(.leadMinutes, default: leadMinutes)
    }
}

public struct DownloadSettings: Decodable, Equatable, Sendable {
    public var enabled: Bool = true
    public var path: String = "~/Downloads"

    enum CodingKeys: String, CodingKey { case enabled, path }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.value(.enabled, default: enabled)
        path = try c.value(.path, default: path)
    }
}

public struct BatterySettings: Decodable, Equatable, Sendable {
    public var lowThreshold: Int = 20

    enum CodingKeys: String, CodingKey { case lowThreshold = "low_threshold" }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lowThreshold = try c.value(.lowThreshold, default: lowThreshold)
    }
}

public struct AISettings: Decodable, Equatable, Sendable {
    /// Any OpenAI Chat Completions compatible endpoint (OpenAI, DeepSeek, local Ollama, ...)
    public var baseURL: String = "https://api.openai.com/v1"
    public var model: String = "gpt-4o-mini"
    /// Environment variable holding the API key; falls back to the Keychain (service agentTouchbar.ai)
    public var apiKeyEnv: String = "OPENAI_API_KEY"
    public var prompts: [AIPrompt] = AIPrompt.defaults

    enum CodingKeys: String, CodingKey {
        case model, prompts
        case baseURL = "base_url"
        case apiKeyEnv = "api_key_env"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.value(.baseURL, default: baseURL)
        model = try c.value(.model, default: model)
        apiKeyEnv = try c.value(.apiKeyEnv, default: apiKeyEnv)
        prompts = try c.value(.prompts, default: prompts)
    }
}

public struct AIPrompt: Codable, Equatable, Sendable {
    public var title: String
    public var prompt: String

    public init(title: String, prompt: String) {
        self.title = title
        self.prompt = prompt
    }

    public static let defaults = [
        AIPrompt(
            title: "Translate",
            prompt:
                "If the text below is in English, translate it into Simplified Chinese; otherwise translate it into English. Output only the translation."
        ),
        AIPrompt(
            title: "Polish", prompt: "Polish the text below. Keep its meaning and language. Output only the result."),
        AIPrompt(title: "Explain", prompt: "Explain the content below in plain language, in 80 words or fewer."),
    ]
}

public struct ServerSettings: Decodable, Equatable, Sendable {
    public var port: Int = 47800

    enum CodingKeys: String, CodingKey { case port }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = try c.value(.port, default: port)
    }
}

/// A widget config: `id`, `type`, and every other key is a widget-specific option.
public struct WidgetConfig: Decodable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var options: Options

    public init(id: String, type: String, options: Options) {
        self.id = id
        self.type = type
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        var values = try decoder.singleValueContainer().decode([String: ConfigValue].self)
        guard let id = values.removeValue(forKey: "id")?.string else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: L("Widget is missing an id")))
        }
        self.id = id
        self.type = values.removeValue(forKey: "type")?.string ?? id
        self.options = Options(values)
    }
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
