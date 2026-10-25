import Foundation
import Yams

// MARK: - 顶层配置

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

    /// 解析 YAML 文本。空文件等同于全部使用默认值。
    public static func parse(yaml: String) throws -> AppConfig {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        return try YAMLDecoder().decode(AppConfig.self, from: trimmed.isEmpty ? "{}" : yaml)
    }

    public static var `default`: AppConfig {
        // 内置的默认配置有单元测试保证能解析
        (try? parse(yaml: DefaultConfig.yaml)) ?? (try! parse(yaml: "{}"))
    }

    /// 找到 id 对应的组件配置。布局里直接写类型名（如 `clock`）时，按该类型、空选项处理。
    public func widget(id: String) -> WidgetConfig {
        widgets.first { $0.id == id } ?? WidgetConfig(id: id, type: id, options: Options())
    }

    public func alertRule(for kind: String) -> AlertRule {
        alerts[kind] ?? AlertRule()
    }
}

// MARK: - 各部分

public struct Theme: Decodable, Equatable, Sendable {
    public var accent: String = "#7C5CFF"
    public var fontSize: Double = 13
    public var density: String = "comfortable"   // compact / comfortable
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
    /// full：占满整条（包括右侧系统按钮区）；app_region：只占左侧程序区域
    public var mode: String = "full"
    /// 有提醒时，如果 Touch Bar 已熄灭，尝试点亮它
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
    /// 秒；nil 表示一直显示，直到处理
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

    /// 实际过期时间
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
    /// 在 Touch Bar 上处理 Claude Code / Codex 的权限请求
    public var permissionOnTouchbar: Bool = true
    /// 等待你在 Touch Bar 上点击的秒数。等待期间终端里的确认框不会出现，所以不宜太长。
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
    /// 粘贴后多少秒清除剪贴板（剪贴板内容还是这个码时才清除）
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
    /// Touch Bar 上显示几条
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
    /// 兼容 OpenAI Chat Completions 接口的地址（OpenAI、DeepSeek、本地 Ollama 等）
    public var baseURL: String = "https://api.openai.com/v1"
    public var model: String = "gpt-4o-mini"
    /// 从这个环境变量读取 API key；没有时再从钥匙串读取（服务名 agentTouchbar.ai）
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
        AIPrompt(title: "翻译", prompt: "把下面的文字翻译成中文；如果已经是中文，就翻译成英文。只输出译文。"),
        AIPrompt(title: "润色", prompt: "润色下面的文字，保持原意和语言，只输出结果。"),
        AIPrompt(title: "解释", prompt: "用简单的中文解释下面的内容，不超过 120 字。"),
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

/// 一个组件的配置：`id`、`type`，其余键都是这个组件自己的选项
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
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "组件缺少 id"))
        }
        self.id = id
        self.type = values.removeValue(forKey: "type")?.string ?? id
        self.options = Options(values)
    }
}

// MARK: - 解码辅助

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
