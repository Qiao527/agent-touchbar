import AppKit
import AgentTouchbarCore

/// 组件共用的环境：各种数据源，以及请求重绘、弹出子面板的入口
@MainActor
final class Env {
    var config: AppConfig = .default
    let alerts = AlertCenter()
    lazy var agents = AgentTracker(alerts: alerts)
    let spotify = SpotifyService()
    let calendar = CalendarService()
    let clipboard = ClipboardService()
    let battery = BatteryService()
    let stats = SystemStats()
    let weather = WeatherService()
    let bluetooth = BluetoothService()
    let ai = AIService()
    let context = ContextMonitor()
    let pomodoro = PomodoroService()

    /// 由 AppController 设置
    var showOverlay: (_ title: String, _ views: [NSView]) -> Void = { _, _ in }
    var hideOverlay: () -> Void = {}
    var widgetNamed: (String) -> Widget? = { _ in nil }
    var requestRender: () -> Void = {}

    func runAI(promptTitle: String, prompt: String, text: String, canReplace: Bool) {
        ResultPanel.shared.showLoading(promptTitle)
        ai.complete(system: prompt, user: text) { result in
            switch result {
            case .success(let output):
                ResultPanel.shared.show(title: promptTitle, text: output, canReplace: canReplace)
            case .failure(let error):
                ResultPanel.shared.show(title: "\(promptTitle)失败", text: error.localizedDescription, canReplace: false)
            }
        }
    }
}

/// 所有组件的基类。子类在 refresh() 里调用 setContent(_:) 更新显示。
@MainActor
class Widget: NSObject {
    let config: WidgetConfig
    unowned let env: Env
    let stack: NSStackView
    private var timer: Timer?
    private(set) var isVisible = false

    var options: Options { config.options }

    /// 需要定时刷新的组件返回间隔（秒）
    var refreshInterval: TimeInterval? { nil }

    required init(config: WidgetConfig, env: Env) {
        self.config = config
        self.env = env
        self.stack = UI.row([], spacing: 6)
        super.init()
    }

    var view: NSView { stack }

    func appear() {
        guard !isVisible else { return }
        isVisible = true
        refresh()
        if let interval = refreshInterval {
            timer = repeatingTimer(interval, fireNow: false) { [weak self] in self?.refresh() }
        }
    }

    func disappear() {
        isVisible = false
        timer?.invalidate()
        timer = nil
    }

    /// 数据变化或定时器触发时调用
    func refresh() {}

    func setContent(_ views: [NSView]) {
        stack.setViews(views, in: .leading)
        stack.isHidden = views.isEmpty
    }

    // 常用控件
    func button(_ title: String, icon: String? = nil, color: String? = nil, size: CGFloat = 14,
                _ handler: @escaping () -> Void) -> ActionButton {
        ActionButton(title: title, icon: Icon.image(icon, size: size),
                     color: color.map { NSColor.from($0, fallback: UI.accent) }, handler: handler)
    }
}

/// 组件类型 → 类
@MainActor
enum WidgetFactory {
    static let types: [String: Widget.Type] = [
        "esc": EscWidget.self,
        "clock": ClockWidget.self,
        "battery": BatteryWidget.self,
        "cpu": StatsWidget.self,
        "stats": StatsWidget.self,
        "volume": VolumeWidget.self,
        "brightness": BrightnessWidget.self,
        "now_playing": NowPlayingWidget.self,
        "spotify": NowPlayingWidget.self,
        "agents": AgentsWidget.self,
        "next_event": NextEventWidget.self,
        "weather": WeatherWidget.self,
        "buttons": ButtonsWidget.self,
        "snippets": SnippetsWidget.self,
        "clipboard": ClipboardWidget.self,
        "system": SystemWidget.self,
        "audio_output": AudioOutputWidget.self,
        "pomodoro": PomodoroWidget.self,
        "script": ScriptWidget.self,
        "git_branch": GitBranchWidget.self,
        "ai": AIWidget.self,
        "meeting": MeetingWidget.self,
        "video": VideoWidget.self,
        "browser": BrowserWidget.self,
        "airpods": AirPodsWidget.self,
        "text": TextWidget.self,
    ]

    static func make(_ config: WidgetConfig, env: Env) -> Widget {
        if let type = types[config.type] { return type.init(config: config, env: env) }
        Log.error("未知的组件类型：\(config.type)（id: \(config.id)）")
        return TextWidget(config: WidgetConfig(id: config.id, type: "text",
                                               options: Options(["text": .string("未知组件 \(config.type)")])), env: env)
    }
}
