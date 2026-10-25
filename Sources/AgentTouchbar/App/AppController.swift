import AgentTouchbarCore
import AppKit
import ServiceManagement

/// Wires everything together: config → data sources → scenes → Touch Bar rendering.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let env = Env()
    private let store = ConfigStore()
    private let host = TouchBarHost()
    private let messages = MessagesWatcher()
    private let downloads = DownloadsWatcher()
    private var server: AgentServer?
    private var token = ""

    private var widgets: [String: Widget] = [:]
    private var visible: Set<ObjectIdentifier> = []
    private var backgroundWidgets: [Widget] = []
    private var overlay: (title: String, views: [NSView])?
    private var overlayTimer: Timer?
    private var renderScheduled = false
    private(set) var sceneName: String?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            token = try Token.loadOrCreate()
        } catch {
            Log.error("Failed to create token: \(error.localizedDescription)")
        }
        setUpStatusItem()
        wireEnvironment()
        wireSources()

        store.onChange = { [weak self] config in self?.apply(config) }
        store.onError = { [weak self] error in self?.configError(error) }
        store.start()

        env.alerts.start()
        env.agents.start()
        env.battery.start()
        env.stats.start()
        env.spotify.start()
        env.calendar.start()
        env.context.start()

        host.show()
        if !host.isAvailable {
            env.alerts.post(
                kind: AlertKind.custom, id: "no-dfr", source: "app",
                title: L("This system does not support a global Touch Bar"),
                detail: L("Private API unavailable; alerts will appear in the menu bar instead"),
                icon: "sf:exclamationmark.triangle.fill",
                color: "red", ttl: 0)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.host.show()
                self?.env.pomodoro.resetReminders()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.host.show() }
        }
        Log.info("agentTouchbar started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        host.hide()
    }

    // MARK: Config

    private func apply(_ config: AppConfig) {
        env.config = config
        env.alerts.config = config
        UI.apply(config.theme)

        let fullWidth = config.touchbar.mode != "app_region"
        let modeChanged = fullWidth != host.fullWidth
        host.fullWidth = fullWidth
        host.wakeOnAlert = config.touchbar.wakeOnAlert

        env.battery.threshold = config.battery.lowThreshold
        env.bluetooth.threshold = config.battery.lowThreshold
        env.calendar.leadMinutes = config.calendar.leadMinutes
        env.ai.settings = config.ai

        messages.extraKeywords = config.verificationCodes.extraKeywords
        config.verificationCodes.enabled ? messages.start() : messages.stop()
        config.clipboard.enabled ? env.clipboard.start(limit: config.clipboard.maxItems) : env.clipboard.stop()
        config.downloads.enabled ? downloads.start(path: config.downloads.path) : downloads.stop()

        let pomodoroConfig = config.widgets.first { $0.type == "pomodoro" } ?? config.widget(id: "pomodoro")
        env.pomodoro.configure(pomodoroConfig.options)

        if server == nil || server?.port != config.server.port {
            startServer(port: config.server.port)
        }

        // Rebuild all widgets. State lives in the data sources, so nothing is lost.
        for widget in widgets.values { widget.disappear() }
        backgroundWidgets.forEach { $0.disappear() }
        widgets.removeAll()
        visible.removeAll()
        overlay = nil
        backgroundWidgets = config.widgets
            .filter { $0.type == "script" && $0.options.bool("background", default: false) }
            .map { WidgetFactory.make($0, env: env) }
        backgroundWidgets.forEach { $0.appear() }

        if modeChanged || !host.isShown { host.show() }
        env.context.update()
        scheduleRender()
    }

    private func configError(_ error: String?) {
        if let error {
            env.alerts.post(
                kind: AlertKind.custom, id: "config-error", source: "config", title: L("Config file has errors"),
                detail: error, icon: "sf:exclamationmark.triangle.fill", color: "red",
                actions: [AlertAction(id: "open", title: L("Open"))], ttl: 0
            ) { [weak self] action in
                if action == "open" || action == "tap" { self?.openConfig() }
            }
        } else {
            env.alerts.dismiss(id: "config-error")
        }
        updateStatusIcon()
    }

    // MARK: Widgets and rendering

    private func widget(_ id: String) -> Widget {
        if let existing = widgets[id] { return existing }
        let widget = WidgetFactory.make(env.config.widget(id: id), env: env)
        widgets[id] = widget
        return widget
    }

    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.renderScheduled = false
                self?.render()
            }
        }
    }

    private func render() {
        let config = env.config
        let layout = SceneMatcher.resolve(layout: config.layout, scenes: config.scenes, context: env.context.context)
        sceneName = layout.sceneName

        var used = Set<String>()
        func views(_ ids: [String]) -> [Widget] {
            ids.compactMap { id in
                guard used.insert(id).inserted else { return nil }
                return widget(id)
            }
        }

        let left = views(layout.left)
        let right = views(layout.right)
        var shown = left + right
        let island: NSView

        if let overlay {
            let close = ActionButton(title: "", icon: Icon.image("sf:xmark.circle.fill"), color: nil) { [weak self] in
                self?.hideOverlay()
            }
            close.isBordered = false
            let row = UI.row([close, UI.label(overlay.title, size: 11, color: .secondaryLabelColor)] + overlay.views)
            island = row
            shown += widgets.values.filter { w in overlay.views.contains { $0 === w.view } }
        } else if let alert = env.alerts.focused {
            island = alertView(alert)
        } else {
            let islandWidgets = views(layout.island)
            shown += islandWidgets
            island = UI.row(islandWidgets.map(\.view), spacing: UI.spacing * 1.5)
        }

        // Only visible widgets get refreshed.
        let shownIDs = Set(shown.map(ObjectIdentifier.init))
        for widget in widgets.values where !shownIDs.contains(ObjectIdentifier(widget)) {
            widget.disappear()
        }
        for widget in shown { widget.appear() }
        visible = shownIDs

        host.render(left: UI.row(left.map(\.view)), island: island, right: UI.row(right.map(\.view)))
        updateStatusIcon()
    }

    private func refreshVisible() {
        for widget in widgets.values where visible.contains(ObjectIdentifier(widget)) {
            widget.refresh()
        }
    }

    private func alertView(_ alert: Alert) -> NSView {
        let color = NSColor.from(alert.color, fallback: UI.accent)
        var views: [NSView] = []
        if let icon = Icon.image(alert.icon, size: 15) {
            views.append(UI.imageView(icon, tint: color, size: 22))
        }

        // The body text is a button too: tapping it runs tapAction.
        let text = ActionButton(title: "") { [weak self] in
            self?.env.alerts.perform(alertID: alert.id, actionID: alert.tapAction ?? "tap")
        }
        text.isBordered = false
        let attributed = NSMutableAttributedString(
            string: alert.title,
            attributes: [.font: NSFont.systemFont(ofSize: UI.fontSize + 1, weight: .semibold), .foregroundColor: color])
        if let detail = alert.detail, !detail.isEmpty {
            attributed.append(
                NSAttributedString(
                    string: "  " + Text.truncate(detail, 48),
                    attributes: [
                        .font: NSFont.systemFont(ofSize: UI.fontSize - 1),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]))
        }
        text.attributedTitle = attributed
        text.lineBreakMode = .byTruncatingTail
        text.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        views.append(text)

        for action in alert.actions {
            views.append(
                ActionButton(title: action.title, color: NSColor.from(action.color, fallback: .systemGray)) {
                    [weak self] in
                    self?.env.alerts.perform(alertID: alert.id, actionID: action.id)
                })
        }
        let others = env.alerts.queue.count - 1
        if others > 0 {
            views.append(
                ActionButton(title: "+\(others)", color: .darkGray) { [weak self] in
                    self?.env.alerts.focusNext()
                })
        }
        let close = ActionButton(title: "", icon: Icon.image("sf:xmark", size: 11)) { [weak self] in
            self?.env.alerts.perform(alertID: alert.id, actionID: "dismiss")
        }
        close.isBordered = false
        views.append(close)
        return UI.row(views, spacing: 8)
    }

    private func showOverlay(_ title: String, _ views: [NSView]) {
        overlay = (title, views)
        overlayTimer?.invalidate()
        overlayTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideOverlay() }
        }
        render()
    }

    private func hideOverlay() {
        guard overlay != nil else { return }
        overlay = nil
        overlayTimer?.invalidate()
        render()
    }

    // MARK: Data sources

    private func wireEnvironment() {
        env.showOverlay = { [weak self] title, views in self?.showOverlay(title, views) }
        env.hideOverlay = { [weak self] in self?.hideOverlay() }
        env.widgetNamed = { [weak self] id in self?.widget(id) }
        env.requestRender = { [weak self] in self?.scheduleRender() }
        env.pomodoro.alerts = env.alerts

        env.alerts.onChange = { [weak self] in self?.scheduleRender() }
        env.alerts.onNewAlert = { [weak self] in self?.host.wakeIfNeeded() }
        env.context.nowPlaying = { [weak self] in self?.env.spotify.isPlaying == true ? "spotify" : nil }
        env.context.onBattery = { [weak self] in self?.env.battery.state?.onBattery ?? false }
        env.context.inMeeting = { [weak self] in self?.env.calendar.inMeeting ?? false }
        env.context.onChange = { [weak self] _ in self?.scheduleRender() }

        let refresh: () -> Void = { [weak self] in self?.refreshVisible() }
        env.spotify.onChange = refresh
        env.calendar.onChange = refresh
        env.clipboard.onChange = refresh
        env.weather.onChange = refresh
        env.bluetooth.onChange = refresh
        env.pomodoro.onChange = refresh
        env.agents.onChange = refresh
    }

    private func wireSources() {
        messages.onCode = { [weak self] code in self?.showCode(code) }

        env.calendar.onMeetingSoon = { [weak self] event in
            guard let self else { return }
            var actions: [AlertAction] = []
            if event.link != nil { actions.append(AlertAction(id: "join", title: L("Join"), color: "green")) }
            self.env.alerts.post(
                kind: AlertKind.meetingSoon, id: "meeting-\(event.id)", source: "calendar",
                title: "\(Text.countdown(to: event.start)) · \(event.title)", icon: "sf:calendar.badge.clock",
                color: "blue", actions: actions, tapAction: event.link == nil ? nil : "join"
            ) { action in
                if action == "join" || action == "tap", let link = event.link { NSWorkspace.shared.open(link) }
            }
        }

        env.battery.onLow = { [weak self] percent in
            self?.env.alerts.post(
                kind: AlertKind.batteryLow, id: "battery-low", source: "battery",
                title: L("Battery at {0}%", percent), detail: L("Plug in the charger"), icon: "sf:battery.25percent",
                color: "red")
        }

        env.bluetooth.onLow = { [weak self] device in
            self?.env.alerts.post(
                kind: AlertKind.batteryLow, id: "bt-low-\(device.device)", source: "bluetooth",
                title: L("{0} battery low", device.device), detail: L("Lowest {0}%", device.lowest ?? 0),
                icon: "sf:airpodspro", color: "orange")
        }

        downloads.onFinished = { [weak self] url in
            self?.env.alerts.post(
                kind: AlertKind.downloadDone, id: "download-\(url.path)", source: "downloads",
                title: L("Downloaded"), detail: url.lastPathComponent, icon: "sf:arrow.down.circle.fill", color: "blue",
                actions: [
                    AlertAction(id: "open", title: L("Open"), color: "blue"),
                    AlertAction(id: "reveal", title: L("Show in Finder"), color: "gray"),
                ],
                tapAction: "open"
            ) { action in
                switch action {
                case "open", "tap": NSWorkspace.shared.open(url)
                case "reveal": NSWorkspace.shared.activateFileViewerSelecting([url])
                default: break
                }
            }
        }
    }

    private func showCode(_ code: VerificationCode) {
        let clearAfter = env.config.verificationCodes.clearClipboardAfter
        env.alerts.post(
            kind: AlertKind.verificationCode, id: "code-\(code.code)", source: "messages",
            title: code.code, detail: code.source.map { L("From {0}", $0) }, icon: "sf:key.fill", color: "yellow",
            actions: [
                AlertAction(id: "paste", title: L("Paste"), color: "green"),
                AlertAction(id: "copy", title: L("Copy"), color: "gray"),
            ],
            tapAction: "paste"
        ) { action in
            guard ["paste", "tap", "copy"].contains(action) else { return }
            if action == "copy" {
                Keyboard.copy(code.code, concealed: true)
            } else {
                Keyboard.paste(code.code, concealed: true)
            }
            // After a while, clear the clipboard if it still holds this code.
            DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
                MainActor.assumeIsolated {
                    if NSPasteboard.general.string(forType: .string) == code.code {
                        NSPasteboard.general.clearContents()
                    }
                }
            }
        }
    }

    // MARK: Local server

    private func startServer(port: Int) {
        server?.stop()
        let server = AgentServer(token: token)
        server.handler = { [weak self] request, respond in
            self?.handle(request, respond) ?? respond(.error(503, "Not ready"))
        }
        server.start(port: port)
        self.server = server
    }

    private func handle(_ request: HTTPRequest, _ respond: @escaping (HTTPResponse) -> Void) {
        let decoder = JSONDecoder()
        guard request.method == "POST" else { return respond(.error(405, "Only POST is supported")) }
        switch request.path {
        case "/v1/agent":
            guard let event = try? decoder.decode(AgentEvent.self, from: request.body) else {
                return respond(.error(400, "Malformed AgentEvent"))
            }
            env.agents.handle(event)
            respond(.json(["ok": true]))
        case "/v1/permission":
            guard let message = try? decoder.decode(PermissionRequestMessage.self, from: request.body) else {
                return respond(.error(400, "Malformed PermissionRequest"))
            }
            env.agents.requestPermission(message) { decision in
                respond(.json(PermissionResponse(decision: decision)))
            }
        case "/v1/notify":
            guard let note = try? decoder.decode(NotifyRequest.self, from: request.body) else {
                return respond(.error(400, "Malformed NotifyRequest"))
            }
            env.alerts.post(
                kind: note.kind ?? AlertKind.custom, id: note.id, source: "atb", title: note.title,
                detail: note.detail, icon: note.icon ?? "sf:bell.fill", color: note.color,
                actions: note.actions ?? [], priority: note.priority, ttl: note.ttl)
            respond(.json(["ok": true]))
        default:
            respond(.error(404, "No such endpoint"))
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "agentTouchbar")
        item.button?.image?.isTemplate = true
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func updateStatusIcon() {
        let warning = store.lastError != nil || messages.needsFullDiskAccess || server?.lastError != nil
        let alerting = !host.isShown && !env.alerts.queue.isEmpty
        let name =
            warning ? "exclamationmark.triangle.fill" : alerting ? "bell.badge.fill" : "rectangle.topthird.inset.filled"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "agentTouchbar")
        statusItem?.button?.image?.isTemplate = !alerting
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled && action != nil
            menu.addItem(item)
        }

        add(L("Scene: {0}", sceneName ?? L("Default")), nil, enabled: false)
        if let server, server.lastError == nil {
            add(L("Local server: 127.0.0.1:{0}", server.port), nil, enabled: false)
        }
        let sessions = env.agents.active.count
        if sessions > 0 { add(L("Agent sessions: {0}", sessions), nil, enabled: false) }

        if let error = store.lastError {
            add(L("⚠️ Config error: {0}", Text.truncate(error, 60)), #selector(openConfig))
        }
        if let error = server?.lastError { add("⚠️ \(error)", nil, enabled: false) }
        if !host.isAvailable { add("⚠️ " + L("This system does not support a global Touch Bar"), nil, enabled: false) }
        if messages.needsFullDiskAccess {
            add(L("⚠️ Verification codes need Full Disk Access…"), #selector(openFullDiskAccess))
        }
        if !AXIsProcessTrusted() {
            add(L("⚠️ Pasting and shortcuts need Accessibility permission…"), #selector(openAccessibility))
        }

        menu.addItem(.separator())
        add(host.isShown ? L("Hide Touch Bar") : L("Show Touch Bar"), #selector(toggleTouchBar))
        add(L("Send test alert"), #selector(testAlert))
        menu.addItem(.separator())
        add(L("Open config file"), #selector(openConfig))
        add(L("Reload config"), #selector(reloadConfig))
        add(L("Open config folder"), #selector(openConfigFolder))
        add(L("Copy Claude Code hooks config"), #selector(copyClaudeHooks))
        add(L("Copy Codex hooks config"), #selector(copyCodexHooks))
        add(L("View log"), #selector(openLog))
        menu.addItem(.separator())
        let login = NSMenuItem(title: L("Launch at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(
            NSMenuItem(
                title: L("Quit agentTouchbar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleTouchBar() { host.toggle(); updateStatusIcon() }

    @objc private func testAlert() {
        env.alerts.post(
            kind: AlertKind.custom, source: "menu", title: L("Test alert"), detail: L("agentTouchbar is working"),
            icon: "sf:sparkles", color: "purple", actions: [AlertAction(id: "ok", title: L("OK"), color: "green")])
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(
            [Paths.configFile], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func reloadConfig() { store.reload(force: true) }
    @objc private func openConfigFolder() { NSWorkspace.shared.open(Paths.configDirectory) }
    @objc private func openLog() { NSWorkspace.shared.open(Paths.logFile) }
    @objc private func openFullDiskAccess() { Permissions.openFullDiskAccessSettings() }
    @objc private func openAccessibility() {
        _ = Permissions.accessibility(prompt: true)
        Permissions.openAccessibilitySettings()
    }

    @objc private func copyClaudeHooks() { copyHooks("claude") }
    @objc private func copyCodexHooks() { copyHooks("codex") }

    private func copyHooks(_ agent: String) {
        guard let atb = Bundle.main.url(forAuxiliaryExecutable: "atb")?.path else { return }
        Shell.run(atb, ["hooks", agent]) { [weak self] result in
            Keyboard.copy(result.output)
            self?.env.alerts.post(
                kind: AlertKind.custom, source: "menu",
                title: L("Copied {0} hooks config", agent == "claude" ? "Claude Code" : "Codex"),
                detail: L("Paste into {0}", agent == "claude" ? "~/.claude/settings.json" : "~/.codex/config.toml"),
                icon: "sf:doc.on.clipboard", color: "green")
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.error("Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}
