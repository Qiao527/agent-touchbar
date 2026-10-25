import AppKit
import IOKit.pwr_mgt

/// 唯一调用私有 API 的地方。全部通过 dlsym 和 selector 动态查找：
/// 系统更新后某个接口不见了，程序会降级而不是崩溃。
@MainActor
enum DFR {
    private nonisolated(unsafe) static let foundation = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
    private nonisolated(unsafe) static let brightness = dlopen(
        "/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_NOW)

    private typealias GetStatus = @convention(c) () -> Int
    private typealias SetPresence = @convention(c) (NSString, Bool) -> Void
    private typealias SetCloseBox = @convention(c) (Bool) -> Void

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let foundation, let address = dlsym(foundation, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    private static let getStatus = symbol("DFRGetStatus", as: GetStatus.self)
    private static let setPresence = symbol("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self)
    private static let setCloseBox = symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: SetCloseBox.self)

    private static let selPresentPlacement = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    private static let selPresent = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private static let selDismiss = NSSelectorFromString("dismissSystemModalTouchBar:")
    private static let selMinimize = NSSelectorFromString("minimizeSystemModalTouchBar:")
    private static let selAddTray = NSSelectorFromString("addSystemTrayItem:")

    private static func hasClassMethod(_ cls: AnyClass, _ sel: Selector) -> Bool {
        class_getClassMethod(cls, sel) != nil
    }

    static var canPresent: Bool {
        hasClassMethod(NSTouchBar.self, selPresentPlacement) || hasClassMethod(NSTouchBar.self, selPresent)
    }

    /// nil 表示无法读取
    static var isDark: Bool? { getStatus.map { $0() & 0x4 != 0 } }

    static func addTrayItem(_ item: NSTouchBarItem) {
        guard hasClassMethod(NSTouchBarItem.self, selAddTray) else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selAddTray, with: item)
    }

    static func setTrayPresence(_ identifier: NSTouchBarItem.Identifier, visible: Bool) {
        setPresence?(identifier.rawValue as NSString, visible)
    }

    static func showCloseBox(_ visible: Bool) {
        setCloseBox?(visible)
    }

    /// fullWidth 为 true 时占满整条 Touch Bar；不支持时退回只占左侧区域
    @discardableResult
    static func present(_ bar: NSTouchBar, tray: NSTouchBarItem.Identifier, fullWidth: Bool) -> Bool {
        if fullWidth, let method = class_getClassMethod(NSTouchBar.self, selPresentPlacement) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
            let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            fn(NSTouchBar.self as AnyObject, selPresentPlacement, bar, 1, tray.rawValue as NSString)
            return true
        }
        if hasClassMethod(NSTouchBar.self, selPresent) {
            _ = (NSTouchBar.self as AnyObject).perform(selPresent, with: bar, with: tray.rawValue as NSString)
            return true
        }
        return false
    }

    static func dismiss(_ bar: NSTouchBar) {
        if hasClassMethod(NSTouchBar.self, selDismiss) {
            _ = (NSTouchBar.self as AnyObject).perform(selDismiss, with: bar)
        } else if hasClassMethod(NSTouchBar.self, selMinimize) {
            _ = (NSTouchBar.self as AnyObject).perform(selMinimize, with: bar)
        }
    }

    /// DFRBrightnessClient 是系统自己做闲置变暗时用的类
    @discardableResult
    static func turnPanelOn() -> Bool {
        _ = brightness
        guard let cls = NSClassFromString("DFRBrightnessClient") as? NSObject.Type else { return false }
        let client = cls.init()
        let sel = NSSelectorFromString("turnOn")
        guard client.responds(to: sel) else { return false }
        typealias Call = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(client.method(for: sel), to: Call.self)(client, sel)
    }

    /// 公开 API：声明有用户操作，重置闲置计时
    static func declareUserActivity() {
        var id: IOPMAssertionID = 0
        if IOPMAssertionDeclareUserActivity("agentTouchbar alert" as CFString, kIOPMUserActiveLocal, &id) == kIOReturnSuccess {
            IOPMAssertionRelease(id)
        }
    }
}
