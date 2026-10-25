import AgentTouchbarCore
import AppKit
import CoreAudio
import IOKit.ps

// MARK: - Config

/// Loads the config file and checks its modification time every second, reloading on change.
/// If the new config is invalid, the previous one stays in effect and the error is reported via lastError.
@MainActor
final class ConfigStore {
    private(set) var config: AppConfig = .default
    private(set) var lastError: String?
    var onChange: ((AppConfig) -> Void)?
    var onError: ((String?) -> Void)?
    private var modified: Date?
    private var timer: Timer?

    func start() {
        let url = Paths.configFile
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? DefaultConfig.yaml.write(to: url, atomically: true, encoding: .utf8)
            Log.info("Wrote default config: \(url.path)")
        }
        reload(force: true)
        timer = repeatingTimer(1, fireNow: false) { [weak self] in self?.reload(force: false) }
    }

    func reload(force: Bool) {
        let url = Paths.configFile
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard force || date != modified else { return }
        modified = date
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            config = try AppConfig.parse(yaml: text)
            lastError = nil
            Log.info("Config loaded")
            onChange?(config)
        } catch {
            lastError = Self.describe(error)
            Log.error("Config file error: \(lastError ?? "")")
        }
        onError?(lastError)
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let c), .keyNotFound(_, let c), .typeMismatch(_, let c), .valueNotFound(_, let c):
                let path = c.codingPath.map(\.stringValue).joined(separator: ".")
                return path.isEmpty ? c.debugDescription : "\(path): \(c.debugDescription)"
            @unknown default:
                break
            }
        }
        return "\(error)"
    }
}

// MARK: - Alerts

@MainActor
final class AlertCenter {
    private(set) var queue = AlertQueue()
    private var handlers: [String: (String) -> Void] = [:]
    private var timer: Timer?
    var config: AppConfig = .default
    var onChange: (() -> Void)?
    /// Called for new alerts (not updates); used to wake the Touch Bar.
    var onNewAlert: (() -> Void)?
    /// Index of the alert currently shown.
    private(set) var focusedIndex = 0

    func start() {
        timer = repeatingTimer(1, fireNow: false) { [weak self] in self?.prune() }
    }

    var focused: Alert? {
        guard !queue.isEmpty else { return nil }
        return queue.alerts[min(focusedIndex, queue.count - 1)]
    }

    /// Posts an alert. The handler receives the tapped action id; "tap" means the body text was tapped.
    func post(
        kind: String, id: String? = nil, source: String, title: String, detail: String? = nil,
        icon: String? = nil, color: String? = nil, actions: [AlertAction] = [], tapAction: String? = nil,
        payload: [String: String] = [:], priority: Int? = nil, ttl: Double? = nil,
        handler: ((String) -> Void)? = nil
    ) {
        let rule = config.alertRule(for: kind)
        guard rule.enabled else { return }
        let now = Date()
        var expiry = rule.expiry(from: now)
        if let ttl, !rule.sticky { expiry = ttl > 0 ? now.addingTimeInterval(ttl) : nil }
        let alert = Alert(
            id: id ?? UUID().uuidString, kind: kind, source: source, title: title, detail: detail,
            icon: icon, color: color, priority: priority ?? rule.priority, createdAt: now,
            expiresAt: expiry, actions: actions, tapAction: tapAction, payload: payload)
        if let handler { handlers[alert.id] = handler }
        let isNew = queue.push(alert)
        if isNew, queue.top?.id == alert.id { focusedIndex = 0 }
        onChange?()
        if isNew { onNewAlert?() }
    }

    func perform(alertID: String, actionID: String) {
        guard let alert = queue.alert(id: alertID) else { return }
        let action = alert.actions.first { $0.id == actionID }
        if let command = action?.run { Shell.shell(command) }
        handlers[alertID]?(actionID)
        if actionID == "dismiss" || action?.dismisses ?? (actionID == "tap") {
            dismiss(id: alertID)
        }
    }

    func dismiss(id: String) {
        guard queue.remove(id: id) != nil else { return }
        handlers[id] = nil
        clampFocus()
        onChange?()
    }

    func dismissAll(where predicate: (Alert) -> Bool) {
        let ids = queue.alerts.filter(predicate).map(\.id)
        guard !ids.isEmpty else { return }
        ids.forEach { handlers[$0] = nil }
        queue.removeAll(where: predicate)
        clampFocus()
        onChange?()
    }

    func focusNext() {
        guard queue.count > 1 else { return }
        focusedIndex = (focusedIndex + 1) % queue.count
        onChange?()
    }

    private func prune() {
        let expired = queue.prune(at: Date())
        guard !expired.isEmpty else { return }
        for alert in expired {
            // Notify on expiry too, e.g. a timed-out permission request hands control back to the terminal.
            handlers[alert.id]?("expired")
            handlers[alert.id] = nil
        }
        clampFocus()
        onChange?()
    }

    private func clampFocus() {
        if focusedIndex >= queue.count { focusedIndex = 0 }
    }
}

// MARK: - Context (frontmost app, microphone)

@MainActor
final class ContextMonitor {
    private(set) var context = Context()
    var onChange: ((Context) -> Void)?
    var nowPlaying: () -> String? = { nil }
    var onBattery: () -> Bool = { false }
    var inMeeting: () -> Bool = { false }
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer = repeatingTimer(2) { [weak self] in self?.update() }
    }

    func update() {
        let app = NSWorkspace.shared.frontmostApplication
        var next = Context(
            frontmostBundleID: app?.bundleIdentifier,
            frontmostAppName: app?.localizedName,
            micInUse: Audio.isInputInUse(),
            nowPlaying: nowPlaying(),
            onBattery: onBattery(),
            inMeeting: inMeeting(),
            date: Date()
        )
        // The time always differs, so compare only down to the minute.
        let minute = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next.date)
        let oldMinute = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: context.date)
        if minute == oldMinute { next.date = context.date }
        guard next != context else { return }
        context = next
        onChange?(context)
    }
}

// MARK: - Audio (CoreAudio)

enum Audio {
    struct Device: Equatable {
        var id: AudioDeviceID
        var name: String
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = address(selector)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// Whether the default microphone is in use by any app (one signal that a meeting is in progress).
    static func isInputInUse() -> Bool {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else { return false }
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    static func outputDevices() -> [Device] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else {
            return []
        }
        return ids.compactMap { id in
            var streams = self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else {
                return nil
            }
            return Device(id: id, name: name(of: id) ?? L("Device {0}", id))
        }
    }

    static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
            let value = name?.takeRetainedValue()
        else { return nil }
        return value as String
    }

    static var currentOutput: AudioDeviceID? { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }

    static func setOutput(_ id: AudioDeviceID) {
        var device = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = address(selector)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &device)
        }
    }

    /// 0–100. Read and written via AppleScript so it works with every output device.
    static func volume(_ completion: @escaping @MainActor (Int?, Bool) -> Void) {
        Shell.osascript(
            "set s to get volume settings\nreturn (output volume of s as string) & \",\" & (output muted of s as string)"
        ) { result in
            let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
            completion(parts.first.flatMap { Int($0) }, parts.last == "true")
        }
    }

    static func setVolume(_ value: Int) {
        Shell.osascript("set volume output volume \(max(0, min(100, value))) without output muted")
    }

    static func toggleMute() {
        Shell.osascript("set volume output muted (not (output muted of (get volume settings)))")
    }
}

// MARK: - Battery

@MainActor
final class BatteryService {
    struct State: Equatable {
        var percent: Int
        var charging: Bool
        var onBattery: Bool
    }

    private(set) var state: State?
    var threshold = 20
    var onLow: ((Int) -> Void)?
    private var warned = false
    private var timer: Timer?

    func start() {
        timer = repeatingTimer(30) { [weak self] in self?.update() }
    }

    func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }
        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let percent = current * 100 / max
            let onBattery = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            state = State(percent: percent, charging: charging, onBattery: onBattery)

            if onBattery && percent <= threshold && !warned {
                warned = true
                onLow?(percent)
            } else if !onBattery || percent > threshold + 5 {
                warned = false
            }
            return
        }
    }
}

// MARK: - CPU and memory

@MainActor
final class SystemStats {
    private(set) var cpu: Double = 0  // 0–1
    private(set) var memory: Double = 0  // 0–1
    private var previous: host_cpu_load_info?
    private var timer: Timer?

    func start() {
        timer = repeatingTimer(2) { [weak self] in self?.update() }
    }

    private func update() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            if let previous {
                let user = Double(info.cpu_ticks.0 &- previous.cpu_ticks.0)
                let system = Double(info.cpu_ticks.1 &- previous.cpu_ticks.1)
                let idle = Double(info.cpu_ticks.2 &- previous.cpu_ticks.2)
                let nice = Double(info.cpu_ticks.3 &- previous.cpu_ticks.3)
                let total = user + system + idle + nice
                if total > 0 { cpu = (user + system + nice) / total }
            }
            previous = info
        }

        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = Double(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
            memory = used / Double(ProcessInfo.processInfo.physicalMemory)
        }
    }
}
