import AgentTouchbarCore
import AppKit

// MARK: - Spotify

final class NowPlayingWidget: Widget {
    override func refresh() {
        let spotify = env.spotify
        guard let track = spotify.track else { return setContent([]) }
        var views: [NSView] = []
        if let artwork = spotify.artwork {
            views.append(UI.imageView(artwork, size: 26))
        }
        let title = UI.label(
            "\(track.name) – \(track.artist)", size: 12, color: track.playing ? .labelColor : .secondaryLabelColor)
        title.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(options.double("max_width", default: 180)))
            .isActive = true
        views.append(title)
        views.append(button("", icon: "sf:backward.fill", size: 12) { spotify.command("previous track") })
        views.append(
            button("", icon: track.playing ? "sf:pause.fill" : "sf:play.fill", size: 12) {
                spotify.command("playpause")
            })
        views.append(button("", icon: "sf:forward.fill", size: 12) { spotify.command("next track") })
        setContent(views)
    }
}

// MARK: - Claude Code / Codex

final class AgentsWidget: Widget {
    override var refreshInterval: TimeInterval? { 1 }

    override func refresh() {
        let sessions = env.agents.active.filter { $0.state != .ended }.prefix(3)
        guard !sessions.isEmpty else {
            return setContent(
                options.bool("hide_when_empty", default: true)
                    ? []
                    : [UI.label(L("No agents running"), size: 12, color: .secondaryLabelColor)])
        }
        setContent(
            sessions.map { session in
                let color: String
                let status: String
                switch session.state {
                case .running:
                    color = "blue"
                    status = Text.duration(Date().timeIntervalSince(session.started))
                case .waiting:
                    color = "orange"
                    status = L("Waiting")
                case .done:
                    color = "green"
                    status = L("Done")
                case .idle, .ended:
                    color = "gray"
                    status = L("Idle")
                }
                let name = session.displayName + (session.project.map { "·" + Text.truncate($0, 10) } ?? "")
                let key = "\(session.agent):\(session.id)"
                return button("\(name) \(status)", icon: "sf:circle.fill", color: color, size: 8) { [weak self] in
                    self?.env.agents.jump(to: key)
                }
            })
    }
}

// MARK: - Pomodoro and water / stand-up reminders

@MainActor
final class PomodoroService {
    private(set) var pomodoro = Pomodoro()
    private var timer: Timer?
    private var lastWater = Date()
    private var lastStand = Date()
    var waterEvery: Double = 0
    var standEvery: Double = 0
    var alerts: AlertCenter?
    var onChange: (() -> Void)?

    func configure(_ options: Options) {
        pomodoro.focusMinutes = options.double("focus_minutes", default: 25)
        pomodoro.restMinutes = options.double("rest_minutes", default: 5)
        waterEvery = options.double("water_every", default: 0)
        standEvery = options.double("stand_every", default: 0)
        if timer == nil {
            timer = repeatingTimer(1, fireNow: false) { [weak self] in self?.tick() }
        }
    }

    func startFocus() {
        pomodoro.startFocus()
        alerts?.dismiss(id: "pomodoro")
        onChange?()
    }

    func stop() {
        pomodoro.stop()
        alerts?.dismiss(id: "pomodoro")
        onChange?()
    }

    private func tick() {
        let now = Date()
        if let finished = pomodoro.tick(at: now) {
            let focusDone = finished == .focus
            alerts?.post(
                kind: AlertKind.pomodoro, id: "pomodoro", source: "pomodoro",
                title: focusDone ? L("🍅 Focus done, take a break") : L("Break over"),
                detail: L("Rounds today: {0}", pomodoro.completedRounds), icon: "sf:timer", color: "red",
                actions: focusDone
                    ? [
                        AlertAction(id: "rest", title: L("Break"), color: "green"),
                        AlertAction(id: "again", title: L("One more"), color: "red"),
                        AlertAction(id: "snooze", title: L("In 5 min"), color: "gray"),
                    ]
                    : [
                        AlertAction(id: "again", title: L("Focus"), color: "red"),
                        AlertAction(id: "stop", title: L("Stop"), color: "gray"),
                    ]
            ) { [weak self] action in
                guard let self else { return }
                switch action {
                case "rest": self.pomodoro.startRest()
                case "again": self.pomodoro.startFocus()
                case "snooze": self.pomodoro.snooze()
                default: self.pomodoro.stop()
                }
                self.onChange?()
            }
        }
        // Time while the screen is locked or asleep does not count
        if waterEvery > 0, now.timeIntervalSince(lastWater) >= waterEvery * 60 {
            lastWater = now
            alerts?.post(
                kind: AlertKind.reminder, id: "water", source: "reminder", title: L("💧 Time for some water"),
                icon: "sf:drop.fill", color: "blue", actions: [AlertAction(id: "ok", title: L("OK"))])
        }
        if standEvery > 0, now.timeIntervalSince(lastStand) >= standEvery * 60 {
            lastStand = now
            alerts?.post(
                kind: AlertKind.reminder, id: "stand", source: "reminder", title: L("🧍 Time to stand up and move"),
                icon: "sf:figure.walk", color: "green", actions: [AlertAction(id: "ok", title: L("OK"))])
        }
        if pomodoro.endsAt != nil { onChange?() }
    }

    /// Restart the water and stand-up timers after the Mac wakes from sleep
    func resetReminders() {
        lastWater = Date()
        lastStand = Date()
    }
}

final class PomodoroWidget: Widget {
    override func refresh() {
        let service = env.pomodoro
        let p = service.pomodoro
        if let remaining = p.remaining() {
            let isFocus = p.phase == .focus
            setContent([
                button("\(isFocus ? "🍅" : "☕️") \(Text.duration(remaining))", color: isFocus ? "red" : "green") {
                    service.stop()
                }
            ])
        } else {
            setContent([button("🍅", color: nil) { service.startFocus() }])
        }
    }
}

// MARK: - Meeting controls

/// Tencent Meeting and Feishu (Lark) have no public API, so this sends their keyboard shortcuts,
/// which requires Accessibility permission. Shortcuts are configured per app name.
final class MeetingWidget: Widget {
    private var startedAt = Date()

    override var refreshInterval: TimeInterval? { 1 }

    override func appear() {
        startedAt = Date()
        super.appear()
    }

    override func refresh() {
        let app = meetingApp()
        let keys = keyMap(for: app)
        let micOn = env.context.context.micInUse
        var views: [NSView] = [
            UI.imageView(
                Icon.image(micOn ? "sf:mic.fill" : "sf:mic.slash.fill", size: 13),
                tint: micOn ? .systemGreen : .secondaryLabelColor, size: 18),
            UI.label(Text.duration(Date().timeIntervalSince(startedAt)), size: 12),
        ]
        for (action, title, icon, color) in [
            ("mute", L("Mute"), "sf:mic.slash.fill", "orange"),
            ("camera", L("Camera"), "sf:video.fill", "blue"),
            ("leave", L("Leave"), "sf:phone.down.fill", "red"),
        ] {
            guard let combo = keys[action] else { continue }
            views.append(
                button(title, icon: icon, color: color, size: 12) { [weak self] in
                    self?.send(combo, to: app)
                })
        }
        if let event = env.calendar.current, let link = event.link, app == nil {
            views.append(
                button(L("Join meeting"), icon: "sf:video.fill", color: "green") { NSWorkspace.shared.open(link) })
        }
        setContent(views)
    }

    /// The app currently in a meeting: the frontmost app first, then any running meeting app
    private func meetingApp() -> String? {
        let configured = Array((options["keys"]?.object ?? [:]).keys)
        let front = NSWorkspace.shared.frontmostApplication
        let frontNames = [front?.localizedName, front?.bundleIdentifier].compactMap { $0?.lowercased() }
        if let match = configured.first(where: { frontNames.contains($0.lowercased()) }) { return match }
        let running = NSWorkspace.shared.runningApplications.flatMap {
            [$0.localizedName, $0.bundleIdentifier].compactMap { $0?.lowercased() }
        }
        return configured.first { running.contains($0.lowercased()) }
    }

    private func keyMap(for app: String?) -> [String: String] {
        guard let app, let map = options["keys"]?.object?[app]?.object else { return [:] }
        return map.compactMapValues(\.string)
    }

    private func send(_ combo: String, to app: String?) {
        if let app { AppActivator.activate(appNamed: app) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated { Keyboard.send(combo) }
        }
    }
}

// MARK: - Web video

final class VideoWidget: Widget {
    private lazy var slider: NSSlider = {
        let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(seek))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: CGFloat(options.double("width", default: 160))).isActive = true
        return slider
    }()
    private let time = UI.label("", size: 11, color: .secondaryLabelColor)
    private var duration: Double = 0
    private var rate: Double = 1
    private var hasVideo = false
    private var lastSeek = Date.distantPast

    override var refreshInterval: TimeInterval? { 1 }

    override func refresh() {
        Browser.video("return v.currentTime+','+v.duration+','+v.paused+','+v.playbackRate;") { [weak self] output in
            guard let self else { return }
            let parts = (output ?? "").split(separator: ",").map(String.init)
            guard parts.count == 4, let current = Double(parts[0]), let duration = Double(parts[1]), duration.isFinite
            else {
                if self.hasVideo || self.stack.views.isEmpty == false {
                    self.hasVideo = false
                    self.setContent([])
                }
                return
            }
            self.duration = duration
            self.rate = Double(parts[3]) ?? 1
            if !self.hasVideo { self.build(paused: parts[2] == "true") }
            self.hasVideo = true
            if Date().timeIntervalSince(self.lastSeek) > 1.5 {
                self.slider.doubleValue = duration > 0 ? current / duration : 0
            }
            self.time.stringValue = "\(Text.duration(current)) / \(Text.duration(duration))"
        }
    }

    private func build(paused: Bool) {
        let skip = Int(options.double("skip_seconds", default: 85))
        setContent([
            button("", icon: "sf:gobackward.10", size: 13) { Browser.video("v.currentTime-=10;") },
            button("", icon: "sf:playpause.fill", size: 13) { Browser.video("v.paused?v.play():v.pause();") },
            button("", icon: "sf:goforward.10", size: 13) { Browser.video("v.currentTime+=10;") },
            slider,
            time,
            button(L("Skip intro"), icon: "sf:forward.end.fill", size: 12) { Browser.video("v.currentTime+=\(skip);") },
            button(L("Speed"), icon: "sf:gauge.with.dots.needle.67percent", size: 12) { [weak self] in
                guard let self else { return }
                let rates: [Double] = [1, 1.25, 1.5, 2]
                let next = rates.first { $0 > self.rate + 0.01 } ?? 1
                Browser.video("v.playbackRate=\(next);")
                self.env.alerts.post(
                    kind: AlertKind.custom, id: "video-rate", source: "video", title: L("Speed {0}×", next),
                    icon: "sf:gauge.with.dots.needle.67percent", ttl: 2)
            },
        ])
    }

    @objc private func seek() {
        lastSeek = Date()
        Browser.video("v.currentTime=\(slider.doubleValue * duration);")
    }
}

// MARK: - Browser

final class BrowserWidget: Widget {
    override func refresh() {
        guard stack.views.isEmpty else { return }
        setContent([
            button(L("Tabs"), icon: "sf:square.on.square") { [weak self] in self?.showTabs() },
            button(L("Summarize"), icon: "sf:text.append") { [weak self] in self?.summarize() },
            button(L("Translate"), icon: "sf:character.bubble") { Self.translate() },
        ])
    }

    private func showTabs() {
        Browser.tabs { [weak self] titles in
            guard let self, !titles.isEmpty else { return }
            let buttons = titles.prefix(8).enumerated().map { index, title in
                self.button(Text.truncate(title, 12)) {
                    Browser.selectTab(index)
                    self.env.hideOverlay()
                }
            }
            self.env.showOverlay(L("Tabs"), buttons)
        }
    }

    private func summarize() {
        Browser.run("document.title+'\\n'+document.body.innerText.slice(0,8000)") { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                self.env.alerts.post(
                    kind: AlertKind.custom, source: "browser", title: L("Can't read the page"),
                    detail: L("Turn on \"Allow JavaScript from Apple Events\" in the browser menu"),
                    icon: "sf:exclamationmark.triangle",
                    color: "orange")
                return
            }
            self.env.runAI(
                promptTitle: L("Page summary"),
                prompt: L("Summarize the main points of this web page as a bulleted list of at most 8 items."),
                text: text,
                canReplace: false)
        }
    }

    /// Open the current page in Google Translate
    private static func translate() {
        Browser.currentURL { url in
            guard let url, let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let target = URL(
                    string:
                        "https://translate.google.com/translate?sl=auto&tl=\(Localization.language == .simplifiedChinese ? "zh-CN" : "en")&u=\(encoded)"
                )
            else { return }
            NSWorkspace.shared.open(target)
        }
    }
}
