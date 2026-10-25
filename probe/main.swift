// agentTouchbar probe
//
// Answers two questions on real hardware:
//   1. Do the private APIs for a global Touch Bar still work on this Mac's macOS version?
//   2. After the Touch Bar dims from inactivity, can a program light it up again? Which method works?
//
// Runs unattended and writes results live to ~/Desktop/agentTouchbar-probe.txt.
// Only calls the built-in DFRFoundation / DFRBrightness private frameworks and restores everything at the end.

import AppKit
import IOKit.pwr_mgt

// MARK: - Report

final class Report {
    static let shared = Report()
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/agentTouchbar-probe.txt")
    private let handle: FileHandle?

    private init() {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func write(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(time)] \(text)\n"
        print(line, terminator: "")
        fflush(stdout)
        handle?.write(Data(line.utf8))
    }
}

func note(_ text: String) { Report.shared.write(text) }

// MARK: - Private APIs

enum DFR {
    static let foundationHandle = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
    static let brightnessHandle = dlopen(
        "/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_NOW)

    typealias GetStatus = @convention(c) () -> Int
    typealias SetPresence = @convention(c) (NSString, Bool) -> Void
    typealias SetCloseBox = @convention(c) (Bool) -> Void

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = foundationHandle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    static let getStatus = symbol("DFRGetStatus", as: GetStatus.self)
    static let setPresence = symbol("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self)
    static let setCloseBox = symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: SetCloseBox.self)

    // Observed on macOS 15.5: 0x1 = lit, 0x5 = dark, so bit 0x4 means off (from gbili/touchbar-off)
    static var status: Int? { getStatus?() }
    static var isDark: Bool? { status.map { $0 & 0x4 != 0 } }
    static var statusText: String {
        guard let status else { return "unknown (DFRGetStatus unavailable)" }
        let hex = String(status, radix: 16, uppercase: true)
        return "0x\(hex) (\(status & 0x4 != 0 ? "dark" : "lit"))"
    }

    // Private class methods on NSTouchBar / NSTouchBarItem
    static let selPresentPlacement = NSSelectorFromString(
        "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    static let selPresent = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    static let selDismiss = NSSelectorFromString("dismissSystemModalTouchBar:")
    static let selMinimize = NSSelectorFromString("minimizeSystemModalTouchBar:")
    static let selAddTray = NSSelectorFromString("addSystemTrayItem:")

    static func hasClassMethod(_ cls: AnyClass, _ sel: Selector) -> Bool {
        class_getClassMethod(cls, sel) != nil
    }

    /// placement 1 = the whole Touch Bar (including the Control Strip on the right); this is what MTMR uses
    static func presentFullWidth(_ bar: NSTouchBar, tray: String) -> Bool {
        guard let method = class_getClassMethod(NSTouchBar.self, selPresentPlacement) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self as AnyObject, selPresentPlacement, bar, 1, tray as NSString)
        return true
    }

    /// Covers only the app region on the left and keeps the Control Strip on the right
    static func presentAppRegion(_ bar: NSTouchBar, tray: String) -> Bool {
        guard hasClassMethod(NSTouchBar.self, selPresent) else { return false }
        _ = (NSTouchBar.self as AnyObject).perform(selPresent, with: bar, with: tray as NSString)
        return true
    }

    static func dismiss(_ bar: NSTouchBar) {
        if hasClassMethod(NSTouchBar.self, selDismiss) {
            _ = (NSTouchBar.self as AnyObject).perform(selDismiss, with: bar)
        } else if hasClassMethod(NSTouchBar.self, selMinimize) {
            _ = (NSTouchBar.self as AnyObject).perform(selMinimize, with: bar)
        }
    }

    static func addTrayItem(_ item: NSTouchBarItem) -> Bool {
        guard hasClassMethod(NSTouchBarItem.self, selAddTray) else { return false }
        _ = (NSTouchBarItem.self as AnyObject).perform(selAddTray, with: item)
        return true
    }

    /// DFRBrightnessClient: the class TouchBarServer itself uses to dim when idle
    static var brightnessClientAvailable: Bool {
        _ = brightnessHandle
        guard let cls = NSClassFromString("DFRBrightnessClient") as? NSObject.Type else { return false }
        let client = cls.init()
        return client.responds(to: NSSelectorFromString("turnOn"))
            && client.responds(to: NSSelectorFromString("turnOff"))
    }

    static func setPanel(on: Bool) -> String {
        _ = brightnessHandle
        guard let cls = NSClassFromString("DFRBrightnessClient") as? NSObject.Type else {
            return "failed: DFRBrightnessClient not found"
        }
        let client = cls.init()
        let sel = NSSelectorFromString(on ? "turnOn" : "turnOff")
        guard client.responds(to: sel) else { return "failed: does not respond to \(sel)" }
        typealias Call = @convention(c) (AnyObject, Selector) -> Bool
        let ok = unsafeBitCast(client.method(for: sel), to: Call.self)(client, sel)
        return ok ? "call succeeded" : "call returned false"
    }
}

/// Public API: declare user activity, so the system resets its idle timer as if someone touched the keyboard
func declareUserActivity() -> String {
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionDeclareUserActivity("agentTouchbar probe" as CFString, kIOPMUserActiveLocal, &id)
    if result == kIOReturnSuccess {
        IOPMAssertionRelease(id)
        return "call succeeded"
    }
    return "call failed, error code \(result)"
}

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buffer)
}

// MARK: - Test Touch Bar

@MainActor
final class ProbeBar: NSObject {
    let touchBar = NSTouchBar()
    private(set) var tapped = false
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let button = NSButton(title: "Tap me", target: nil, action: nil)

    override init() {
        super.init()
        icon.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        button.bezelColor = .systemPurple
        button.target = self
        button.action = #selector(onTap)

        let stack = NSStackView(views: [icon, label, button])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY

        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("atb.probe.main"))
        item.view = stack
        touchBar.defaultItemIdentifiers = [item.identifier]
        touchBar.templateItems = [item]
    }

    func show(_ text: String, color: NSColor = .labelColor) {
        label.stringValue = text
        label.textColor = color
    }

    func resetTap() { tapped = false }

    @objc private func onTap() {
        if !tapped { note("  ✅ Tap received") }
        tapped = true
        show("Tap received ✅", color: .systemGreen)
    }
}

// MARK: - Test sequence

@MainActor
final class Probe: NSObject, NSApplicationDelegate {
    private let bar = ProbeBar()
    private let trayID = "atb.probe.tray"
    private var results: [String] = []
    /// Display mode that worked in step 2: true = full width, false = left app region
    private var usesFullWidth = true

    private func present() {
        if usesFullWidth {
            _ = DFR.presentFullWidth(bar.touchBar, tray: trayID)
        } else {
            _ = DFR.presentAppRegion(bar.touchBar, tray: trayID)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await run()
            cleanUp()
            NSApp.terminate(nil)
        }
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Checks the condition every 0.5 s and logs every Touch Bar status change
    private func waitUntil(timeout: Double, _ condition: () -> Bool) async -> Bool {
        let start = Date()
        var lastStatus = DFR.status
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            let status = DFR.status
            if status != lastStatus {
                note("  Status changed: \(DFR.statusText) at \(Int(Date().timeIntervalSince(start))) s")
                lastStatus = status
            }
            await wait(0.5)
        }
        return condition()
    }

    private func result(_ text: String) {
        results.append(text)
        note("  → \(text)")
    }

    private func run() async {
        note("========== agentTouchbar probe ==========")
        note("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        note("Model: \(sysctlString("hw.model"))")
        let mode = UserDefaults(suiteName: "com.apple.touchbar.agent")?.string(forKey: "PresentationModeGlobal")
        note("Touch Bar mode in System Settings: \(mode ?? "not found")")

        // ---------- 1. Check that the private APIs exist ----------
        note("")
        note("[1] Checking that the private APIs still exist")
        let checks: [(String, Bool)] = [
            ("DFRFoundation framework", DFR.foundationHandle != nil),
            ("DFRBrightness framework", DFR.brightnessHandle != nil),
            ("DFRGetStatus", DFR.getStatus != nil),
            ("DFRElementSetControlStripPresenceForIdentifier", DFR.setPresence != nil),
            ("DFRSystemModalShowsCloseBoxWhenFrontMost", DFR.setCloseBox != nil),
            (
                "NSTouchBar presentSystemModalTouchBar:placement:… (full width)",
                DFR.hasClassMethod(NSTouchBar.self, DFR.selPresentPlacement)
            ),
            (
                "NSTouchBar presentSystemModalTouchBar:systemTrayItemIdentifier: (left region)",
                DFR.hasClassMethod(NSTouchBar.self, DFR.selPresent)
            ),
            ("NSTouchBar dismissSystemModalTouchBar:", DFR.hasClassMethod(NSTouchBar.self, DFR.selDismiss)),
            ("NSTouchBarItem addSystemTrayItem:", DFR.hasClassMethod(NSTouchBarItem.self, DFR.selAddTray)),
            ("DFRBrightnessClient turnOn / turnOff", DFR.brightnessClientAvailable),
        ]
        for (name, ok) in checks { note("  \(ok ? "✅" : "❌") \(name)") }
        note("  Current Touch Bar status: \(DFR.statusText)")
        let missing = checks.filter { !$0.1 }.map { $0.0 }
        result(missing.isEmpty ? "All private APIs present" : "Missing: \(missing.joined(separator: ", "))")

        // ---------- 2. Global display + touch ----------
        note("")
        note("[2] Global display test")
        let tray = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(trayID))
        let trayButton = NSButton(title: "ATB", target: nil, action: nil)
        tray.view = trayButton
        if DFR.addTrayItem(tray) { DFR.setPresence?(trayID as NSString, true) }
        DFR.setCloseBox?(false)

        var displayed = false
        if DFR.hasClassMethod(NSTouchBar.self, DFR.selPresentPlacement) {
            usesFullWidth = true
            bar.show("agentTouchbar test: if you can read this, tap the button on the right →")
            present()
            note("  Shown in full-width mode. Tap the purple 'Tap me' button on the Touch Bar within 30 seconds")
            displayed = await waitUntil(timeout: 30) { bar.tapped }
            result(
                displayed
                    ? "Full-width display: works (visible and tappable)"
                    : "Full-width display: no tap within 30 seconds")
        }
        if !displayed, DFR.hasClassMethod(NSTouchBar.self, DFR.selPresent) {
            DFR.dismiss(bar.touchBar)
            bar.resetTap()
            usesFullWidth = false
            bar.show("Trying another mode: if you can read this, tap the button on the right →")
            present()
            note("  Switched to left-region mode. Tap 'Tap me' within 30 seconds")
            displayed = await waitUntil(timeout: 30) { bar.tapped }
            result(displayed ? "Left-region display: works" : "Left-region display: no tap within 30 seconds")
        }
        guard displayed else {
            result("Could not confirm the global display works; skipping the remaining tests")
            return
        }
        await wait(1.5)

        // ---------- 3. Force off, then back on ----------
        note("")
        note("[3] Force off, then back on (the Touch Bar goes dark briefly in 3 seconds; no action needed)")
        bar.show("Turning off in 3 seconds, then back on automatically", color: .systemYellow)
        await wait(3)
        note("  Off: \(DFR.setPanel(on: false))")
        await wait(2)
        note("  Status after off: \(DFR.statusText)")
        bar.show("If you can read this, the program turned the Touch Bar back on", color: .systemGreen)
        note("  On: \(DFR.setPanel(on: true))")
        await wait(1.5)
        note("  Status after on: \(DFR.statusText)")
        result(
            DFR.isDark == false
                ? "DFRBrightnessClient can turn it off and on" : "DFRBrightnessClient failed to turn it on")
        await wait(2)

        // ---------- 4. Wake after natural idle dimming ----------
        note("")
        note("[4] Wake after idle dimming (the most important step)")
        note(
            "  ⚠️ Do not touch the keyboard or trackpad now. The Touch Bar should dim and turn off by itself in about 1 minute. Waiting up to 3 minutes."
        )
        bar.show("Hands off the keyboard and trackpad, waiting for me to turn off…", color: .secondaryLabelColor)
        let start = Date()
        let wentDark = await waitUntil(timeout: 180) { DFR.isDark == true }
        guard wentDark else {
            result(
                "Did not turn off within 180 seconds; the keyboard or trackpad was probably touched. Run it again to retry"
            )
            return
        }
        note("  Turned off after \(Int(Date().timeIntervalSince(start))) s idle")
        await wait(5)

        // 4a: only update the content (ideal: nothing else needed)
        bar.show("🔔 New alert (content updated only)", color: .systemOrange)
        await wait(2)
        var woke = DFR.isDark == false
        result("Method A, update content only: \(woke ? "wakes" : "does not wake")")

        // 4b: call the global display again
        if !woke {
            bar.show("🔔 New alert (presented again)", color: .systemOrange)
            present()
            await wait(2)
            woke = DFR.isDark == false
            result("Method B, present again: \(woke ? "wakes" : "does not wake")")
        }

        // 4c: public API, declare user activity (side effect: also wakes the main display if it dimmed)
        if !woke {
            bar.show("🔔 New alert (declared user activity)", color: .systemOrange)
            note("  \(declareUserActivity())")
            await wait(2)
            woke = DFR.isDark == false
            result("Method C, IOPMAssertionDeclareUserActivity: \(woke ? "wakes" : "does not wake")")
        }

        // 4d: turn it on directly with the private API
        if !woke {
            bar.show("🔔 New alert (turned on with private API)", color: .systemOrange)
            note("  \(DFR.setPanel(on: true))")
            await wait(2)
            woke = DFR.isDark == false
            result("Method D, DFRBrightnessClient turnOn: \(woke ? "wakes" : "does not wake")")
        }

        guard woke else {
            result("No method woke it")
            return
        }

        // How long it stays lit after waking (decides whether alerts need to re-light it periodically)
        note("  Keep hands off the keyboard; measuring how long it stays lit after waking (up to 2 minutes)")
        bar.show("Woke up ✅ Keep hands off, measuring how long it stays lit", color: .systemGreen)
        let litAt = Date()
        let darkAgain = await waitUntil(timeout: 120) { DFR.isDark == true }
        result(
            darkAgain
                ? "Stayed lit for \(Int(Date().timeIntervalSince(litAt))) s after waking, then turned off"
                : "Stayed lit for 2 minutes after waking (or was touched in the meantime)")
    }

    private func cleanUp() {
        DFR.dismiss(bar.touchBar)
        DFR.setPresence?(trayID as NSString, false)
        _ = DFR.setPanel(on: true)
        note("")
        note("========== Summary ==========")
        for line in results { note("• \(line)") }
        note("Report saved: \(Report.shared.url.path)")
        note("Paste the contents of this file to Kiro.")
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Probe()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
