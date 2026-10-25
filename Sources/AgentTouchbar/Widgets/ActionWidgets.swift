import AgentTouchbarCore
import AppKit

// MARK: - Custom buttons

/// Each button can: run (shell command), open (URL or app path), shortcut (Shortcuts name),
/// keys (key combo), paste (paste text), widget (show another widget). With confirm: true it needs two taps.
final class ButtonsWidget: Widget {
    private var armed: String?

    override func refresh() {
        let items = options.objects("items")
        setContent(
            items.enumerated().map { index, item in
                let key = "\(index)"
                let title = armed == key ? L("Sure?") : (item.string("title") ?? "")
                return button(title, icon: item.string("icon"), color: armed == key ? "red" : item.string("color")) {
                    [weak self] in
                    self?.tap(item, key: key)
                }
            })
    }

    private func tap(_ item: Options, key: String) {
        if item.bool("confirm", default: false), armed != key {
            armed = key
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.armed == key else { return }
                    self.armed = nil
                    self.refresh()
                }
            }
            return
        }
        armed = nil
        refresh()
        ButtonsWidget.perform(item, env: env)
    }

    static func perform(_ item: Options, env: Env) {
        if let command = item.string("run") {
            Shell.shell(command) { result in
                if result.status != 0 {
                    env.alerts.post(
                        kind: AlertKind.custom, source: "buttons", title: L("Command failed"),
                        detail: Text.truncate(Text.oneLine(result.error.isEmpty ? result.output : result.error), 80),
                        icon: "sf:exclamationmark.triangle.fill", color: "red")
                } else if item.bool("notify", default: false) {
                    env.alerts.post(
                        kind: AlertKind.custom, source: "buttons",
                        title: L("{0} done", item.string("title") ?? L("Command")),
                        detail: Text.truncate(Text.oneLine(result.output), 80), icon: "sf:checkmark.circle.fill",
                        color: "green")
                }
            }
        }
        if let target = item.string("open") {
            if let url = URL(string: target), url.scheme != nil {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: Paths.expand(target)))
            }
        }
        if let shortcut = item.string("shortcut") {
            Shell.run("/usr/bin/shortcuts", ["run", shortcut])
        }
        if let keys = item.string("keys") {
            Keyboard.send(keys)
        }
        if let text = item.string("paste") {
            Keyboard.paste(text)
        }
        if let id = item.string("widget"), let widget = env.widgetNamed(id) {
            env.showOverlay(item.string("title") ?? id, [widget.view])
        }
    }
}

// MARK: - Snippets

final class SnippetsWidget: Widget {
    override func refresh() {
        setContent(
            options.objects("items").map { item in
                button(item.string("title") ?? "", icon: item.string("icon")) { [weak self] in
                    guard let self else { return }
                    let text: String?
                    if let name = item.string("keychain") {
                        text = Keychain.read(service: "agentTouchbar.snippet", account: name)
                        if text == nil {
                            self.env.alerts.post(
                                kind: AlertKind.custom, source: "snippets",
                                title: L("\"{0}\" is not in the Keychain", name),
                                detail: L("Run atb set-secret {0} to save it", name), icon: "sf:key.fill",
                                color: "orange")
                        }
                    } else {
                        text = item.string("text")
                    }
                    guard let text else { return }
                    Keyboard.paste(text, concealed: item["keychain"] != nil)
                    self.env.hideOverlay()
                }
            })
    }
}

// MARK: - Clipboard history

final class ClipboardWidget: Widget {
    override func refresh() {
        let count = max(1, env.config.clipboard.show)
        let items = env.clipboard.history.items.prefix(count)
        if items.isEmpty {
            return setContent([UI.label(L("Clipboard is empty"), size: 12, color: .secondaryLabelColor)])
        }
        setContent(
            items.map { text in
                let title = Text.truncate(Text.oneLine(text), 14)
                return button(title) { [weak self] in
                    Keyboard.paste(text)
                    self?.env.hideOverlay()
                }
            })
    }
}

// MARK: - System toggles

final class SystemWidget: Widget {
    override func refresh() {
        guard stack.views.isEmpty else { return }
        let items =
            options.strings("items").isEmpty
            ? ["dark_mode", "dnd", "screenshot", "lock"] : options.strings("items")
        setContent(items.compactMap(make))
    }

    private func make(_ name: String) -> NSView? {
        switch name {
        case "dark_mode":
            return button("", icon: "sf:circle.lefthalf.filled") {
                Shell.osascript(
                    "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
                )
            }
        case "dnd":
            // Name of a user-created Shortcut; matches dnd_shortcut in the default config
            let shortcut = options.string("dnd_shortcut", default: "Toggle Focus") ?? "Toggle Focus"
            return button("", icon: "sf:moon.fill") { [weak self] in
                Shell.run("/usr/bin/shortcuts", ["run", shortcut]) { result in
                    if result.status != 0 {
                        self?.env.alerts.post(
                            kind: AlertKind.custom, source: "system", title: L("Shortcut \"{0}\" not found", shortcut),
                            detail: L("Create a shortcut in Shortcuts that toggles Do Not Disturb"),
                            icon: "sf:moon.fill", color: "orange")
                    }
                }
            }
        case "screenshot":
            return button("", icon: "sf:camera.viewfinder") {
                Shell.run("/usr/sbin/screencapture", ["-i", "-c"], timeout: 120)
            }
        case "lock":
            return button("", icon: "sf:lock.fill") {
                Shell.run("/usr/bin/pmset", ["displaysleepnow"])
            }
        case "audio_output":
            return button("", icon: "sf:hifispeaker.2.fill") { [weak self] in
                guard let self else { return }
                let widget =
                    self.env.widgetNamed("audio_output")
                    ?? AudioOutputWidget(
                        config: WidgetConfig(id: "audio_output", type: "audio_output", options: Options()),
                        env: self.env)
                self.env.showOverlay(L("Output device"), [widget.view])
            }
        case "brightness":
            return UI.row(
                [
                    button("", icon: "sf:sun.min.fill") { Keyboard.systemKey(Keyboard.brightnessDown) },
                    button("", icon: "sf:sun.max.fill") { Keyboard.systemKey(Keyboard.brightnessUp) },
                ], spacing: 4)
        default:
            return nil
        }
    }
}

// MARK: - Audio output switcher

final class AudioOutputWidget: Widget {
    override func refresh() {
        let current = Audio.currentOutput
        setContent(
            Audio.outputDevices().map { device in
                // "扬声器" matches built-in speakers on Chinese-language systems ("Speakers" in English)
                let icon =
                    device.name.localizedCaseInsensitiveContains("airpods")
                    ? "sf:airpodspro"
                    : device.name.localizedCaseInsensitiveContains("扬声器")
                        || device.name.localizedCaseInsensitiveContains("speaker")
                        ? "sf:laptopcomputer" : "sf:hifispeaker.fill"
                return button(Text.truncate(device.name, 14), icon: icon, color: device.id == current ? "blue" : nil) {
                    [weak self] in
                    Audio.setOutput(device.id)
                    self?.refresh()
                }
            })
    }
}

// MARK: - Script widget

final class ScriptWidget: Widget {
    private var output = ScriptOutput(text: "…")
    private var running = false
    private var lastAlert: String?

    override var refreshInterval: TimeInterval? { max(1, options.double("interval", default: 60)) }

    override func refresh() {
        render()
        guard !running, let command = options.string("command") else { return }
        running = true
        Shell.shell(Paths.expand(command), timeout: max(5, options.double("timeout", default: 20))) {
            [weak self] result in
            guard let self else { return }
            self.running = false
            self.output =
                result.status == 0
                ? ScriptOutput.parse(result.output)
                : ScriptOutput(text: L("Script error"), color: "red")
            if let alert = self.output.alert, alert.title != self.lastAlert {
                self.lastAlert = alert.title
                self.env.alerts.post(
                    kind: alert.kind ?? AlertKind.custom, id: alert.id, source: self.config.id,
                    title: alert.title, detail: alert.detail, icon: alert.icon, color: alert.color,
                    actions: alert.actions ?? [], priority: alert.priority, ttl: alert.ttl)
            }
            self.render()
        }
    }

    private func render() {
        var views: [NSView] = []
        let color = NSColor.from(output.color)
        if let image = output.image {
            views.append(UI.imageView(Icon.image(image, size: 18), size: 26))
        }
        let tap = output.tap ?? options.string("tap")
        let b = button(output.text, icon: output.icon, color: nil) { if let tap { Shell.shell(tap) } }
        b.isBordered = tap != nil
        b.contentTintColor = color
        views.append(b)
        if let progress = output.progress {
            let bar = ProgressBar(width: 60)
            bar.fraction = progress
            bar.color = output.color == nil ? UI.accent : color
            views.append(bar)
        }
        setContent(views)
    }
}

// MARK: - Git branch

final class GitBranchWidget: Widget {
    override var refreshInterval: TimeInterval? { 10 }

    override func refresh() {
        guard let path = options.string("path").map(Paths.expand) ?? env.agents.latestCwd else { return setContent([]) }
        Shell.run("/usr/bin/git", ["-C", path, "branch", "--show-current"], timeout: 5) { [weak self] result in
            guard let self else { return }
            let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, !branch.isEmpty else { return self.setContent([]) }
            let project = URL(fileURLWithPath: path).lastPathComponent
            self.setContent([
                UI.imageView(Icon.image("sf:arrow.triangle.branch", size: 13), size: 18),
                UI.label("\(Text.truncate(project, 12)) · \(Text.truncate(branch, 18))", size: 12),
            ])
        }
    }
}

// MARK: - AI text actions

final class AIWidget: Widget {
    override func refresh() {
        guard stack.views.isEmpty else { return }
        let prompts = options.objects("prompts").compactMap { item -> AIPrompt? in
            guard let title = item.string("title"), let prompt = item.string("prompt") else { return nil }
            return AIPrompt(title: title, prompt: prompt)
        }
        let list = prompts.isEmpty ? env.config.ai.prompts : prompts
        setContent(
            list.map { prompt in
                button(prompt.title, icon: "sf:sparkles") { [weak self] in
                    guard let self else { return }
                    Selection.read { text in
                        guard let text, !text.isEmpty else {
                            self.env.alerts.post(
                                kind: AlertKind.custom, source: "ai", title: L("Select some text first"),
                                icon: "sf:text.cursor", color: "orange", ttl: 5)
                            return
                        }
                        self.env.runAI(promptTitle: prompt.title, prompt: prompt.prompt, text: text, canReplace: true)
                    }
                }
            })
    }
}
