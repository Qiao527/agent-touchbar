import AgentTouchbarCore
import AppKit

// MARK: - esc

final class EscWidget: Widget {
    override func refresh() {
        guard stack.views.isEmpty else { return }
        let esc = button("esc") { Keyboard.send(KeyCombo(keyCode: 0x35)) }
        esc.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        setContent([esc])
    }
}

// MARK: - Clock and time zones

final class ClockWidget: Widget {
    private let label = UI.label()
    private lazy var formatters: [(String, DateFormatter)] = {
        let zones = options.strings("zones")
        let format = options.string("format", default: "HH:mm") ?? "HH:mm"
        let identifiers = zones.isEmpty ? [TimeZone.current.identifier] : zones
        return identifiers.compactMap { id in
            guard let zone = TimeZone(identifier: id) else { return nil }
            let formatter = DateFormatter()
            formatter.timeZone = zone
            formatter.dateFormat = format
            let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
            return (Self.cityNames[id] ?? city, formatter)
        }
    }()

    private static let cityNames = [
        "Asia/Shanghai": L("Beijing"), "Asia/Hong_Kong": L("Hong Kong"), "Asia/Tokyo": L("Tokyo"),
        "Asia/Singapore": L("Singapore"), "America/Los_Angeles": L("San Francisco"), "America/New_York": L("New York"),
        "Europe/London": L("London"), "Europe/Paris": L("Paris"), "Europe/Berlin": L("Berlin"),
        "Australia/Sydney": L("Sydney"),
    ]

    override var refreshInterval: TimeInterval? {
        (options.string("format") ?? "").contains("s") ? 1 : 5
    }

    override func refresh() {
        let now = Date()
        if formatters.count <= 1 {
            label.stringValue = formatters.first?.1.string(from: now) ?? ""
            setContent([label])
        } else {
            // Several zones: the first in large type, up to two more as two small lines
            label.stringValue = formatters[0].1.string(from: now)
            let others = formatters.dropFirst().prefix(2).map { "\($0.0) \($0.1.string(from: now))" }
            let small = UI.twoLines(others[0], others.count > 1 ? others[1] : "")
            setContent([label, small])
        }
    }
}

// MARK: - Battery

final class BatteryWidget: Widget {
    override var refreshInterval: TimeInterval? { 30 }

    override func refresh() {
        guard let state = env.battery.state else { return setContent([]) }
        let level = state.percent
        let symbol =
            state.charging
            ? "battery.100percent.bolt"
            : level > 87
                ? "battery.100percent"
                : level > 62
                    ? "battery.75percent"
                    : level > 37 ? "battery.50percent" : level > 12 ? "battery.25percent" : "battery.0percent"
        let color: NSColor = level <= env.config.battery.lowThreshold && !state.charging ? .systemRed : .labelColor
        setContent([
            UI.imageView(Icon.image("sf:\(symbol)", size: 15), tint: color, size: 24),
            UI.label("\(level)%", size: 12, color: color),
        ])
    }
}

// MARK: - CPU and memory

final class StatsWidget: Widget {
    override var refreshInterval: TimeInterval? { 2 }

    override func refresh() {
        let cpu = Int(env.stats.cpu * 100), memory = Int(env.stats.memory * 100)
        let color: NSColor = cpu > 80 || memory > 90 ? .systemOrange : .labelColor
        let button = ActionButton(title: "") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
        button.isBordered = false
        button.attributedTitle = UI.twoLines("CPU \(cpu)%", L("Mem {0}%", memory), color: color).attributedStringValue
        setContent([button])
    }
}

// MARK: - Volume

final class VolumeWidget: Widget {
    private lazy var slider: NSSlider = {
        let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: self, action: #selector(changed))
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: CGFloat(options.double("width", default: 110))).isActive = true
        return slider
    }()
    private lazy var mute = button("", icon: "sf:speaker.wave.2.fill") { [weak self] in
        Audio.toggleMute()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { self?.refresh() } }
    }
    private var lastChange = Date.distantPast

    override var refreshInterval: TimeInterval? { 5 }

    override func refresh() {
        if stack.views.isEmpty { setContent([mute, slider]) }
        // Right after the slider moves, don't overwrite it with a stale reading
        guard Date().timeIntervalSince(lastChange) > 2 else { return }
        Audio.volume { [weak self] value, muted in
            guard let self else { return }
            if let value { self.slider.doubleValue = Double(value) }
            let symbol =
                muted || value == 0
                ? "speaker.slash.fill" : (value ?? 50) < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
            self.mute.image = Icon.image("sf:\(symbol)")
        }
    }

    @objc private func changed() {
        lastChange = Date()
        Audio.setVolume(Int(slider.doubleValue))
    }
}

// MARK: - Brightness

final class BrightnessWidget: Widget {
    override func refresh() {
        guard stack.views.isEmpty else { return }
        setContent([
            button("", icon: "sf:sun.min.fill") { Keyboard.systemKey(Keyboard.brightnessDown) },
            button("", icon: "sf:sun.max.fill") { Keyboard.systemKey(Keyboard.brightnessUp) },
        ])
    }
}

// MARK: - Weather

final class WeatherWidget: Widget {
    override func appear() {
        env.weather.start(
            latitude: options.double("latitude", default: 31.23),
            longitude: options.double("longitude", default: 121.47))
        super.appear()
    }

    override func refresh() {
        guard let now = env.weather.now else { return setContent([]) }
        let symbol = now.symbol
        setContent([UI.imageView(Icon.image("sf:\(symbol.name)", size: 14), size: 20), UI.label(now.text, size: 12)])
    }
}

// MARK: - Next calendar event

final class NextEventWidget: Widget {
    override var refreshInterval: TimeInterval? { 30 }

    override func refresh() {
        let calendar = env.calendar
        let now = Date()
        let maxWidth = CGFloat(options.double("max_width", default: 260))
        if let current = calendar.current {
            let title = "\(Text.truncate(current.title, 14)) · \(Text.timeLeft(until: current.end, from: now))"
            setContent([eventButton(title, current, color: "blue", maxWidth: maxWidth)])
        } else if let next = calendar.next, next.start.timeIntervalSince(now) < 12 * 3600 {
            let title = "\(Text.truncate(next.title, 14)) · \(Text.countdown(to: next.start, from: now))"
            setContent([eventButton(title, next, color: nil, maxWidth: maxWidth)])
        } else {
            setContent([])
        }
    }

    private func eventButton(
        _ title: String, _ event: CalendarService.Event, color: String?, maxWidth: CGFloat
    ) -> NSView {
        let b = button(title, icon: event.link == nil ? "sf:calendar" : "sf:video.fill", color: color) {
            if let link = event.link {
                NSWorkspace.shared.open(link)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            }
        }
        b.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true
        b.lineBreakMode = .byTruncatingTail
        return b
    }
}

// MARK: - Bluetooth headphone battery

final class AirPodsWidget: Widget {
    override func appear() {
        env.bluetooth.start()
        super.appear()
    }

    override func refresh() {
        guard let device = env.bluetooth.headphones else { return setContent([]) }
        let labels: [(String, (Int) -> String)] = [
            ("left", { L("L{0}", $0) }), ("right", { L("R{0}", $0) }),
            ("case", { L("Case {0}", $0) }),
        ]
        let parts = labels.compactMap { key, label in
            device.levels[key].map(label)
        }
        let text = parts.isEmpty ? device.levels["main"].map { "\($0)%" } ?? "" : parts.joined(separator: " ")
        let low = (device.lowest ?? 100) <= env.config.battery.lowThreshold
        setContent([
            UI.imageView(Icon.image("sf:airpodspro", size: 14), tint: low ? .systemRed : nil, size: 20),
            UI.label(text, size: 11, color: low ? .systemRed : .labelColor),
        ])
    }
}

// MARK: - Static text

final class TextWidget: Widget {
    override func refresh() {
        guard stack.views.isEmpty else { return }
        let color = NSColor.from(options.string("color"), fallback: .secondaryLabelColor)
        var views: [NSView] = []
        if let icon = Icon.image(options.string("icon")) { views.append(UI.imageView(icon, tint: color)) }
        views.append(UI.label(options.string("text", default: "") ?? "", color: color))
        setContent(views)
    }
}
