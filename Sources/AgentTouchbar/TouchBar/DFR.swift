import AppKit
import IOKit.pwr_mgt

/// The only place that touches private API. Everything is looked up at runtime via dlsym and selectors,
/// so if an OS update removes something, the app degrades instead of crashing.
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

    private static let selPresentPlacement = NSSelectorFromString(
        "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
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

    /// nil means the status could not be read.
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

    /// With fullWidth, the bar spans the whole Touch Bar; falls back to the left region when unsupported.
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

    /// DFRBrightnessClient is the class the system itself uses for idle dimming.
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

    /// Public API: declares user activity, which resets the idle timer.
    static func declareUserActivity() {
        var id: IOPMAssertionID = 0
        if IOPMAssertionDeclareUserActivity("agentTouchbar alert" as CFString, kIOPMUserActiveLocal, &id)
            == kIOReturnSuccess
        {
            IOPMAssertionRelease(id)
        }
    }
}
