// agentTouchbar 探针
//
// 在真机上回答两个问题：
//   1. 全局显示 Touch Bar 用的私有 API 在这台 Mac 的 macOS 上还能不能用？
//   2. Touch Bar 闲置熄灭后，程序能不能把它重新点亮？用哪种方法？
//
// 全程自动运行，结果实时写入 ~/Desktop/agentTouchbar-probe.txt。
// 只调用系统自带的 DFRFoundation / DFRBrightness 私有框架，结束时恢复原状。

import AppKit
import IOKit.pwr_mgt

// MARK: - 报告

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

// MARK: - 私有 API

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

    // macOS 15.5 上观察到：0x1 = 亮，0x5 = 暗，即 0x4 位表示熄灭（来自 gbili/touchbar-off）
    static var status: Int? { getStatus?() }
    static var isDark: Bool? { status.map { $0 & 0x4 != 0 } }
    static var statusText: String {
        guard let status else { return "未知（DFRGetStatus 不可用）" }
        let hex = String(status, radix: 16, uppercase: true)
        return "0x\(hex)（\(status & 0x4 != 0 ? "暗" : "亮")）"
    }

    // NSTouchBar / NSTouchBarItem 上的私有类方法
    static let selPresentPlacement = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    static let selPresent = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    static let selDismiss = NSSelectorFromString("dismissSystemModalTouchBar:")
    static let selMinimize = NSSelectorFromString("minimizeSystemModalTouchBar:")
    static let selAddTray = NSSelectorFromString("addSystemTrayItem:")

    static func hasClassMethod(_ cls: AnyClass, _ sel: Selector) -> Bool {
        class_getClassMethod(cls, sel) != nil
    }

    /// placement 1 = 占满整条 Touch Bar（包括右侧 Control Strip），MTMR 用的就是这种
    static func presentFullWidth(_ bar: NSTouchBar, tray: String) -> Bool {
        guard let method = class_getClassMethod(NSTouchBar.self, selPresentPlacement) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self as AnyObject, selPresentPlacement, bar, 1, tray as NSString)
        return true
    }

    /// 只覆盖左侧"程序区域"，右侧 Control Strip 保留
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

    /// DFRBrightnessClient：TouchBarServer 自己做闲置变暗时用的类
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
            return "失败：找不到 DFRBrightnessClient"
        }
        let client = cls.init()
        let sel = NSSelectorFromString(on ? "turnOn" : "turnOff")
        guard client.responds(to: sel) else { return "失败：不响应 \(sel)" }
        typealias Call = @convention(c) (AnyObject, Selector) -> Bool
        let ok = unsafeBitCast(client.method(for: sel), to: Call.self)(client, sel)
        return ok ? "调用成功" : "调用返回 false"
    }
}

/// 公开 API：声明"用户有操作"，系统会像有人碰了键盘一样重置闲置计时
func declareUserActivity() -> String {
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionDeclareUserActivity("agentTouchbar probe" as CFString, kIOPMUserActiveLocal, &id)
    if result == kIOReturnSuccess {
        IOPMAssertionRelease(id)
        return "调用成功"
    }
    return "调用失败，错误码 \(result)"
}

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "未知" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "未知" }
    return String(cString: buffer)
}

// MARK: - 测试用的 Touch Bar

@MainActor
final class ProbeBar: NSObject {
    let touchBar = NSTouchBar()
    private(set) var tapped = false
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let button = NSButton(title: "点我", target: nil, action: nil)

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
        if !tapped { note("  ✅ 收到点击") }
        tapped = true
        show("收到点击 ✅", color: .systemGreen)
    }
}

// MARK: - 测试流程

@MainActor
final class Probe: NSObject, NSApplicationDelegate {
    private let bar = ProbeBar()
    private let trayID = "atb.probe.tray"
    private var results: [String] = []
    /// 第 2 步里实际可用的显示方式：true = 整条，false = 左侧区域
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

    /// 每 0.5 秒检查一次条件，同时记录 Touch Bar 状态的每次变化
    private func waitUntil(timeout: Double, _ condition: () -> Bool) async -> Bool {
        let start = Date()
        var lastStatus = DFR.status
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            let status = DFR.status
            if status != lastStatus {
                note("  状态变化：\(DFR.statusText)，第 \(Int(Date().timeIntervalSince(start))) 秒")
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
        note("========== agentTouchbar 探针 ==========")
        note("系统：\(ProcessInfo.processInfo.operatingSystemVersionString)")
        note("机型：\(sysctlString("hw.model"))")
        let mode = UserDefaults(suiteName: "com.apple.touchbar.agent")?.string(forKey: "PresentationModeGlobal")
        note("系统设置里 Touch Bar 显示模式：\(mode ?? "未读取到")")

        // ---------- 1. 检查私有 API 是否存在 ----------
        note("")
        note("【1】检查私有 API 是否还在")
        let checks: [(String, Bool)] = [
            ("DFRFoundation 框架", DFR.foundationHandle != nil),
            ("DFRBrightness 框架", DFR.brightnessHandle != nil),
            ("DFRGetStatus", DFR.getStatus != nil),
            ("DFRElementSetControlStripPresenceForIdentifier", DFR.setPresence != nil),
            ("DFRSystemModalShowsCloseBoxWhenFrontMost", DFR.setCloseBox != nil),
            ("NSTouchBar presentSystemModalTouchBar:placement:…（整条）", DFR.hasClassMethod(NSTouchBar.self, DFR.selPresentPlacement)),
            ("NSTouchBar presentSystemModalTouchBar:systemTrayItemIdentifier:（左侧）", DFR.hasClassMethod(NSTouchBar.self, DFR.selPresent)),
            ("NSTouchBar dismissSystemModalTouchBar:", DFR.hasClassMethod(NSTouchBar.self, DFR.selDismiss)),
            ("NSTouchBarItem addSystemTrayItem:", DFR.hasClassMethod(NSTouchBarItem.self, DFR.selAddTray)),
            ("DFRBrightnessClient turnOn / turnOff", DFR.brightnessClientAvailable),
        ]
        for (name, ok) in checks { note("  \(ok ? "✅" : "❌") \(name)") }
        note("  当前 Touch Bar 状态：\(DFR.statusText)")
        let missing = checks.filter { !$0.1 }.map { $0.0 }
        result(missing.isEmpty ? "私有 API 全部存在" : "缺少：\(missing.joined(separator: "、"))")

        // ---------- 2. 全局显示 + 触摸 ----------
        note("")
        note("【2】全局显示测试")
        let tray = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(trayID))
        let trayButton = NSButton(title: "ATB", target: nil, action: nil)
        tray.view = trayButton
        if DFR.addTrayItem(tray) { DFR.setPresence?(trayID as NSString, true) }
        DFR.setCloseBox?(false)

        var displayed = false
        if DFR.hasClassMethod(NSTouchBar.self, DFR.selPresentPlacement) {
            usesFullWidth = true
            bar.show("agentTouchbar 测试：看到这行字，请点右边的按钮 →")
            present()
            note("  已用『整条』方式显示。请在 30 秒内点 Touch Bar 上紫色的『点我』")
            displayed = await waitUntil(timeout: 30) { bar.tapped }
            result(displayed ? "整条显示：可用（能显示，也能点）" : "整条显示：30 秒内没有收到点击")
        }
        if !displayed, DFR.hasClassMethod(NSTouchBar.self, DFR.selPresent) {
            DFR.dismiss(bar.touchBar)
            bar.resetTap()
            usesFullWidth = false
            bar.show("换一种方式：看到这行字，请点右边的按钮 →")
            present()
            note("  改用『左侧区域』方式显示。请在 30 秒内点『点我』")
            displayed = await waitUntil(timeout: 30) { bar.tapped }
            result(displayed ? "左侧区域显示：可用" : "左侧区域显示：30 秒内没有收到点击")
        }
        guard displayed else {
            result("无法确认全局显示可用，后面的测试跳过")
            return
        }
        await wait(1.5)

        // ---------- 3. 强制熄灭再点亮 ----------
        note("")
        note("【3】强制熄灭再点亮（3 秒后 Touch Bar 会黑一下，不用操作）")
        bar.show("3 秒后会熄灭一下，然后自动亮起", color: .systemYellow)
        await wait(3)
        note("  熄灭：\(DFR.setPanel(on: false))")
        await wait(2)
        note("  熄灭后状态：\(DFR.statusText)")
        bar.show("如果你看到这行字，说明程序成功点亮了 Touch Bar", color: .systemGreen)
        note("  点亮：\(DFR.setPanel(on: true))")
        await wait(1.5)
        note("  点亮后状态：\(DFR.statusText)")
        result(DFR.isDark == false ? "DFRBrightnessClient 能熄灭并点亮" : "DFRBrightnessClient 点亮失败")
        await wait(2)

        // ---------- 4. 自然熄灭后能否唤醒 ----------
        note("")
        note("【4】自然熄灭后唤醒（这一步最关键）")
        note("  ⚠️ 现在请完全不要碰键盘和触控板，Touch Bar 大约 1 分钟后会自己变暗熄灭。最多等 3 分钟。")
        bar.show("请不要碰键盘和触控板，等我自己熄灭…", color: .secondaryLabelColor)
        let start = Date()
        let wentDark = await waitUntil(timeout: 180) { DFR.isDark == true }
        guard wentDark else {
            result("180 秒内没有熄灭，可能中途碰了键盘或触控板。可以重新运行再测一次")
            return
        }
        note("  闲置 \(Int(Date().timeIntervalSince(start))) 秒后熄灭")
        await wait(5)

        // 4a：只更新内容（最理想：什么都不用做）
        bar.show("🔔 新提醒（只更新了内容）", color: .systemOrange)
        await wait(2)
        var woke = DFR.isDark == false
        result("方法 A 只更新内容：\(woke ? "能唤醒" : "不能唤醒")")

        // 4b：重新调用一次全局显示
        if !woke {
            bar.show("🔔 新提醒（重新显示了一次）", color: .systemOrange)
            present()
            await wait(2)
            woke = DFR.isDark == false
            result("方法 B 重新显示：\(woke ? "能唤醒" : "不能唤醒")")
        }

        // 4c：公开 API，声明有用户操作（副作用：主屏幕如果暗了也会亮）
        if !woke {
            bar.show("🔔 新提醒（声明了用户操作）", color: .systemOrange)
            note("  \(declareUserActivity())")
            await wait(2)
            woke = DFR.isDark == false
            result("方法 C IOPMAssertionDeclareUserActivity：\(woke ? "能唤醒" : "不能唤醒")")
        }

        // 4d：私有 API 直接点亮
        if !woke {
            bar.show("🔔 新提醒（用私有 API 点亮）", color: .systemOrange)
            note("  \(DFR.setPanel(on: true))")
            await wait(2)
            woke = DFR.isDark == false
            result("方法 D DFRBrightnessClient turnOn：\(woke ? "能唤醒" : "不能唤醒")")
        }

        guard woke else {
            result("所有方法都没能唤醒")
            return
        }

        // 唤醒后能亮多久（决定提醒要不要定期重新点亮）
        note("  继续别碰键盘，测一下唤醒后能亮多久（最多 2 分钟）")
        bar.show("唤醒成功 ✅ 继续别碰，测一下能亮多久", color: .systemGreen)
        let litAt = Date()
        let darkAgain = await waitUntil(timeout: 120) { DFR.isDark == true }
        result(darkAgain
            ? "唤醒后亮了 \(Int(Date().timeIntervalSince(litAt))) 秒又熄灭"
            : "唤醒后 2 分钟内一直亮着（或者中途被碰了）")
    }

    private func cleanUp() {
        DFR.dismiss(bar.touchBar)
        DFR.setPresence?(trayID as NSString, false)
        _ = DFR.setPanel(on: true)
        note("")
        note("========== 结论 ==========")
        for line in results { note("• \(line)") }
        note("报告已保存：\(Report.shared.url.path)")
        note("请把这个文件的内容复制给 Kiro。")
    }
}

let app = NSApplication.shared
let delegate = Probe()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
