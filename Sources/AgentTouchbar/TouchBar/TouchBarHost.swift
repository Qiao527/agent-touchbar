import AgentTouchbarCore
import AppKit

/// Owns our global Touch Bar: the three regions, show/hide, and waking the panel.
@MainActor
final class TouchBarHost: NSObject, NSTouchBarDelegate {
    private static let leftID = NSTouchBarItem.Identifier("agentTouchbar.left")
    private static let islandID = NSTouchBarItem.Identifier("agentTouchbar.island")
    private static let rightID = NSTouchBarItem.Identifier("agentTouchbar.right")
    private static let dashboardID = NSTouchBarItem.Identifier("agentTouchbar.dashboard")
    static let trayID = NSTouchBarItem.Identifier("agentTouchbar.tray")

    private let touchBar = NSTouchBar()
    private let leftItem = NSCustomTouchBarItem(identifier: TouchBarHost.leftID)
    private let islandItem = NSCustomTouchBarItem(identifier: TouchBarHost.islandID)
    private let rightItem = NSCustomTouchBarItem(identifier: TouchBarHost.rightID)
    private let trayItem = NSCustomTouchBarItem(identifier: TouchBarHost.trayID)

    private var dashboardTouchBar: NSTouchBar?
    private var dashboardView: MissionControlView?
    private(set) var isDashboardActive = false

    private(set) var isShown = false
    var fullWidth = true
    var wakeOnAlert = true

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.leftID, Self.islandID, .flexibleSpace, Self.rightID]

        let trayButton = ActionButton(title: "", icon: Icon.image("sf:sparkles", size: 14)) { [weak self] in
            self?.toggle()
        }
        trayButton.isBordered = false
        trayItem.view = trayButton
    }

    var isAvailable: Bool { DFR.canPresent }

    func touchBar(
        _ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.leftID: return leftItem
        case Self.islandID: return islandItem
        case Self.rightID: return rightItem
        case Self.dashboardID:
            guard let dashboardView else { return nil }
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = dashboardView
            return item
        default: return nil
        }
    }

    func render(left: NSView, island: NSView, right: NSView) {
        leftItem.view = left
        islandItem.view = island
        rightItem.view = right
    }

    // MARK: - Mission Control Full-Width Dashboard (1004 pt)

    func showDashboard(env: Env) {
        guard DFR.canPresent, !isDashboardActive else { return }
        let view = MissionControlView(env: env)
        view.onDismiss = { [weak self] in
            self?.hideDashboard()
        }
        self.dashboardView = view

        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.dashboardID]
        self.dashboardTouchBar = bar

        DFR.present(bar, tray: Self.trayID, fullWidth: true)
        view.start()
        isDashboardActive = true
        Log.info("Entered 1004pt Mission Control Dashboard")
    }

    func hideDashboard() {
        guard isDashboardActive else { return }
        dashboardView?.stopAll()
        if let bar = dashboardTouchBar {
            DFR.dismiss(bar)
        }
        isDashboardActive = false
        dashboardTouchBar = nil
        dashboardView = nil

        // Restore regular Touch Bar
        show()
        Log.info("Exited Mission Control Dashboard")
    }

    func toggleDashboard(env: Env) {
        isDashboardActive ? hideDashboard() : showDashboard(env: env)
    }

    func show() {
        guard DFR.canPresent else {
            Log.error("Global Touch Bar private API is not available on this system")
            return
        }
        DFR.addTrayItem(trayItem)
        DFR.setTrayPresence(Self.trayID, visible: true)
        DFR.showCloseBox(!fullWidth)
        DFR.present(touchBar, tray: Self.trayID, fullWidth: fullWidth)
        isShown = true
    }

    func hide() {
        DFR.dismiss(touchBar)
        isShown = false
    }

    func toggle() {
        isShown ? hide() : show()
    }

    /// Called on new alerts. If the Touch Bar is dark, tries to light it up, gentlest method first.
    func wakeIfNeeded() {
        guard wakeOnAlert else { return }
        if !isShown { show() }
        guard DFR.isDark == true else { return }
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated {
                guard DFR.isDark == true else { return }
                DFR.declareUserActivity()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        if DFR.isDark == true {
                            Log.info("Waking for alert via DFRBrightnessClient")
                            DFR.turnPanelOn()
                        }
                    }
                }
            }
        }
    }
}
