//
//  DeveloperWidgets.swift
//  agent-touchbar
//
//  Killer workflow widgets for Designers, Frontend, Backend & Full-Stack Developers:
//  1. ColorPickerWidget: Instant screen pixel sampler (NSColorSampler) with automatic Hex copy.
//  2. PortGuardWidget: Local dev port watcher (3000, 5173, 8080...) with 1-tap zombie process kill.
//

import AgentTouchbarCore
import AppKit

// MARK: - ColorPickerWidget (For Designers & Frontend Developers)

final class ColorPickerWidget: Widget {
    private var lastHex: String?
    private var lastColor: NSColor?

    override func refresh() {
        let buttonTitle = lastHex ?? L("Pick Color")
        let iconName = lastHex != nil ? "sf:paintpalette.fill" : "sf:eyedropper.halffull"

        let btn = ActionButton(
            title: buttonTitle,
            icon: Icon.image(iconName, size: 14),
            color: lastColor
        ) { [weak self] in
            self?.pickColor()
        }
        setContent([btn])
    }

    private func pickColor() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] selectedColor in
            MainActor.assumeIsolated {
                guard let self = self, let color = selectedColor else { return }
                guard let rgbColor = color.usingColorSpace(.sRGB) else { return }

                let r = Int(round(rgbColor.redComponent * 255))
                let g = Int(round(rgbColor.greenComponent * 255))
                let b = Int(round(rgbColor.blueComponent * 255))
                let hex = String(format: "#%02X%02X%02X", r, g, b)

                self.lastHex = hex
                self.lastColor = rgbColor

                // Copy to macOS clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)

                // Notify on Touch Bar
                self.env.alerts.post(
                    kind: AlertKind.custom,
                    id: "color-picked",
                    source: "color_picker",
                    title: L("Copied {0}", hex),
                    detail: L("Hex color code saved to clipboard"),
                    icon: "sf:checkmark.circle.fill",
                    color: "green",
                    ttl: 3
                )

                self.refresh()
            }
        }
    }
}

// MARK: - PortGuardWidget (For Backend & Full-Stack Developers)

final class PortGuardWidget: Widget {
    private struct ActivePort {
        let port: Int
        let pid: Int
        let command: String
    }

    private var activePorts: [ActivePort] = []
    private var isChecking = false

    override var refreshInterval: TimeInterval? { 3 }

    private var watchedPorts: [Int] {
        let list = options.strings("ports").compactMap { Int($0) }
        return list.isEmpty ? [3000, 5173, 8000, 8080, 5432, 6379, 27017] : list
    }

    override func refresh() {
        checkPorts()
    }

    private func checkPorts() {
        guard !isChecking else { return }
        isChecking = true

        let portsArg = watchedPorts.map { String($0) }.joined(separator: ",")
        Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(portsArg)", "-sTCP:LISTEN"]) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.isChecking = false
                self.activePorts = self.parseLsof(result.output)
                self.updateUI()
            }
        }
    }

    private func parseLsof(_ output: String) -> [ActivePort] {
        var found: [ActivePort] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }
            let cmd = String(parts[0])
            guard let pid = Int(parts[1]) else { continue }

            let nameField = String(parts[8])
            // Look for :PORT at the end of the address
            if let colonIdx = nameField.lastIndex(of: ":") {
                let portStr = nameField[nameField.index(after: colonIdx)...]
                if let port = Int(portStr) {
                    found.append(ActivePort(port: port, pid: pid, command: cmd))
                }
            }
        }
        return found
    }

    private func updateUI() {
        let hideWhenEmpty = options.bool("hide_when_empty", default: false)
        if activePorts.isEmpty {
            if hideWhenEmpty {
                setContent([])
            } else {
                let btn = button(L("0 Ports"), icon: "sf:network", color: nil) { [weak self] in
                    self?.showEmptyOverlay()
                }
                setContent([btn])
            }
            return
        }

        let summary =
            activePorts.count == 1
            ? ":\(activePorts[0].port) (\(activePorts[0].command))"
            : "\(activePorts.count) " + L("Ports Active")

        let btn = button(summary, icon: "sf:bolt.fill", color: "orange") { [weak self] in
            self?.showPortsOverlay()
        }
        setContent([btn])
    }

    private func showEmptyOverlay() {
        let label = UI.label(L("No watched dev ports currently active."))
        env.showOverlay(L("Port Guard"), [label])
    }

    private func showPortsOverlay() {
        var views: [NSView] = []
        for item in activePorts {
            let desc = "\(item.command) (PID \(item.pid)) on :\(item.port)"
            let label = UI.label(desc, size: 12)

            let killBtn = ActionButton(
                title: "Kill",
                icon: Icon.image("sf:xmark.octagon.fill", size: 12),
                color: NSColor.systemRed.withAlphaComponent(0.6)
            ) { [weak self] in
                self?.killProcess(pid: item.pid, port: item.port)
            }

            let openBtn = ActionButton(
                title: "Open",
                icon: Icon.image("sf:safari", size: 12),
                color: nil
            ) {
                if let url = URL(string: "http://localhost:\(item.port)") {
                    NSWorkspace.shared.open(url)
                }
            }

            views.append(UI.row([label, openBtn, killBtn], spacing: 6))
        }

        env.showOverlay(L("Active Dev Ports ({0})", activePorts.count), views)
    }

    private func killProcess(pid: Int, port: Int) {
        kill(pid_t(pid), SIGTERM)
        env.hideOverlay()

        env.alerts.post(
            kind: AlertKind.custom,
            id: "port-killed",
            source: "port_guard",
            title: L("Terminated PID {0}", pid),
            detail: L("Freed port :{0}", port),
            icon: "sf:trash.fill",
            color: "red",
            ttl: 3
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                self?.checkPorts()
            }
        }
    }
}
