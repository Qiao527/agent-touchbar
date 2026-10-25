import AppKit
import AgentTouchbarCore

/// 管理我们的全局 Touch Bar：三个区域、显示/隐藏、唤醒
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

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
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
            Log.error("当前系统不支持全局 Touch Bar 私有接口")
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

    /// 有新提醒时调用：Touch Bar 熄灭了就按从温和到强硬的顺序尝试点亮
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
                            Log.info("提醒唤醒：使用 DFRBrightnessClient")
                            DFR.turnPanelOn()
                        }
                    }
                }
            }
        }
    }
}
