//
//  MissionControlView.swift
//  agent-touchbar
//
//  A 1004 pt Edge-to-Edge Full-Width Panoramic HUD for Apple Touch Bar.
//  Aggregates:
//  - Collapse button & Agent status
//  - 60 FPS Metal AI Reasoning Pulse
//  - 60 FPS Dual Metal CPU & Memory Sparkline curves
//  - 60 FPS Continuous Hardware Volume Slider
//  - Quick Action shortcuts (Activity Monitor, Mute, Play/Pause)
//

import AgentTouchbarCore
import AppKit

@MainActor
final class MissionControlView: NSView {
    private let env: Env
    var onDismiss: (() -> Void)?

    // Interactive Components
    private var collapseBtn: ActionButton!
    private var agentPill: NSTextField!
    private var pulseCanvas: AgentPulseCanvasView!
    private var cpuSparkline: MetalSparklineCanvasView!
    private var ramSparkline: MetalSparklineCanvasView!
    private var volumeSlider: MetalSliderCanvasView!
    private var muteBtn: ActionButton!
    private var activityBtn: ActionButton!

    // Auto-dismiss safety timer
    private nonisolated(unsafe) var inactivityTimer: Timer?
    private nonisolated(unsafe) var refreshTimer: Timer?

    init(env: Env) {
        self.env = env
        super.init(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(red: 0.015, green: 0.015, blue: 0.025, alpha: 1.0).cgColor
        self.allowedTouchTypes = [.direct]

        setupComponents()
        layoutHUD()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        inactivityTimer?.invalidate()
        refreshTimer?.invalidate()
    }

    private func setupComponents() {
        // 1. Collapse button
        collapseBtn = ActionButton(title: " ✕ 收起", icon: Icon.image("sf:chevron.down.circle.fill", size: 13)) {
            [weak self] in
            self?.onDismiss?()
        }
        collapseBtn.bezelColor = NSColor.systemRed.withAlphaComponent(0.4)

        // 2. Agent Status Pill
        agentPill = UI.label("🤖 AGENT", size: 10, weight: .bold, color: .systemPurple)

        // 3. AI Reasoning Pulse
        pulseCanvas = AgentPulseCanvasView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))

        // 4. CPU Sparkline
        cpuSparkline = MetalSparklineCanvasView(frame: NSRect(x: 0, y: 0, width: 110, height: 30))

        // 5. RAM Sparkline
        ramSparkline = MetalSparklineCanvasView(frame: NSRect(x: 0, y: 0, width: 110, height: 30))

        // 6. Volume Slider & Mute
        muteBtn = ActionButton(title: "", icon: Icon.image("sf:speaker.wave.2.fill", size: 13)) { [weak self] in
            Audio.toggleMute()
            self?.resetInactivityTimer()
            self?.updateVolume()
        }
        muteBtn.isBordered = false

        volumeSlider = MetalSliderCanvasView(frame: NSRect(x: 0, y: 0, width: 140, height: 30))
        volumeSlider.onValueChanged = { [weak self] val in
            self?.resetInactivityTimer()
            Audio.setVolume(Int(val * 100))
        }

        // 7. Quick Actions
        activityBtn = ActionButton(title: "", icon: Icon.image("sf:chart.bar.xaxis", size: 13)) { [weak self] in
            self?.resetInactivityTimer()
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
        activityBtn.isBordered = false
    }

    private func layoutHUD() {
        // Build the 1004pt panoramic layout
        let cpuLabel = UI.label("CPU", size: 9, weight: .bold, color: .systemTeal)
        let ramLabel = UI.label("RAM", size: 9, weight: .bold, color: .systemPurple)

        let leftGroup = UI.row([collapseBtn, agentPill, pulseCanvas], spacing: 6)
        let centerGroup = UI.row([cpuLabel, cpuSparkline, ramLabel, ramSparkline], spacing: 6)
        let rightGroup = UI.row([muteBtn, volumeSlider, activityBtn], spacing: 6)

        let fullRow = NSStackView(views: [leftGroup, centerGroup, rightGroup])
        fullRow.orientation = .horizontal
        fullRow.alignment = .centerY
        fullRow.distribution = .equalSpacing
        fullRow.spacing = 10
        fullRow.frame = NSRect(x: 8, y: 0, width: 988, height: 30)
        fullRow.autoresizingMask = [.width, .height]
        addSubview(fullRow)
    }

    func start() {
        pulseCanvas.startDisplayLink()
        cpuSparkline.startDisplayLink()
        ramSparkline.startDisplayLink()
        volumeSlider.startDisplayLink()

        resetInactivityTimer()
        startPeriodicUpdate()
        updateData()
        updateVolume()
    }

    func stopAll() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil

        pulseCanvas.stopDisplayLink()
        cpuSparkline.stopDisplayLink()
        ramSparkline.stopDisplayLink()
        volumeSlider.stopDisplayLink()
    }

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDismiss?()
            }
        }
    }

    private func startPeriodicUpdate() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateData()
            }
        }
    }

    private func updateData() {
        // Update Agent pulse
        let activeCount = env.agents.active.filter { $0.state != .ended }.count
        pulseCanvas.activityLevel = activeCount > 0 ? 1.0 : 0.0
        agentPill.stringValue = activeCount > 0 ? "⚡️ \(activeCount) AGENTS" : "🤖 IDLE"

        // Update CPU and RAM
        cpuSparkline.pushSample(Float(env.stats.cpu))
        ramSparkline.pushSample(Float(env.stats.memory))
    }

    private func updateVolume() {
        Audio.volume { [weak self] vol, muted in
            guard let self = self else { return }
            if let vol = vol {
                self.volumeSlider.value = Float(vol) / 100.0
            }
            let iconName =
                muted || vol == 0
                ? "sf:speaker.slash.fill" : (vol ?? 50) < 50 ? "sf:speaker.wave.1.fill" : "sf:speaker.wave.2.fill"
            self.muteBtn.image = Icon.image(iconName, size: 13)
        }
    }

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        resetInactivityTimer()
    }
}
