import AgentTouchbarCore
import AppKit

/// Owns our global Touch Bar: the three regions, show/hide, and waking the panel.
@MainActor
final class TouchBarHost: NSObject, NSTouchBarDelegate {
    private static let leftID = NSTouchBarItem.Identifier("agentTouchbar.left")
    private static let islandID = NSTouchBarItem.Identifier("agentTouchbar.island")
    private static let rightID = NSTouchBarItem.Identifier("agentTouchbar.right")
    static let trayID = NSTouchBarItem.Identifier("agentTouchbar.tray")

    private let touchBar = NSTouchBar()
    private let leftItem = NSCustomTouchBarItem(identifier: TouchBarHost.leftID)
    private let islandItem = NSCustomTouchBarItem(identifier: TouchBarHost.islandID)
    private let rightItem = NSCustomTouchBarItem(identifier: TouchBarHost.rightID)
    private let trayItem = NSCustomTouchBarItem(identifier: TouchBarHost.trayID)

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
        default: return nil
        }
    }

    func render(left: NSView, island: NSView, right: NSView) {
        leftItem.view = left
        islandItem.view = island
        rightItem.view = right
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
