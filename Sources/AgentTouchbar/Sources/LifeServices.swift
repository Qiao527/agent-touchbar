import AgentTouchbarCore
import AppKit
import EventKit

// MARK: - Spotify

@MainActor
final class SpotifyService {
    struct Track: Equatable {
        var playing: Bool
        var name: String
        var artist: String
        var artworkURL: String
    }

    private(set) var track: Track?
    private(set) var artwork: NSImage?
    private var artworkFor: String?
    var onChange: (() -> Void)?
    private var timer: Timer?

    var isPlaying: Bool { track?.playing == true }

    func start() {
        timer = repeatingTimer(2) { [weak self] in self?.poll() }
    }

    private func poll() {
        // Only query while Spotify is running, so AppleScript does not launch it.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            if track != nil {
                track = nil
                onChange?()
            }
            return
        }
        let script = """
            tell application "Spotify"
                set t to current track
                return (player state as string) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (artwork url of t)
            end tell
            """
        Shell.osascript(script) { [weak self] result in
            guard let self else { return }
            let lines = result.output.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
            let next =
                lines.count >= 4
                ? Track(playing: lines[0] == "playing", name: lines[1], artist: lines[2], artworkURL: lines[3])
                : nil
            guard next != self.track else { return }
            self.track = next
            self.loadArtwork()
            self.onChange?()
        }
    }

    private func loadArtwork() {
        guard let urlString = track?.artworkURL, urlString != artworkFor, let url = URL(string: urlString) else {
            return
        }
        artworkFor = urlString
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            onMain {
                guard let self, self.artworkFor == urlString else { return }
                self.artwork = image
                self.onChange?()
            }
        }.resume()
    }

    func command(_ verb: String) {
        Shell.osascript("tell application \"Spotify\" to \(verb)") { [weak self] _ in self?.poll() }
    }
}

// MARK: - Calendar

@MainActor
final class CalendarService {
    struct Event: Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var link: URL?
    }

    private let store = EKEventStore()
    private(set) var upcoming: [Event] = []
    private(set) var authorized = false
    private var alerted: Set<String> = []
    private var timer: Timer?
    var leadMinutes = 5
    var onChange: (() -> Void)?
    var onMeetingSoon: ((Event) -> Void)?

    private var enabled = false
    private var generation = 0
    private var observer: NSObjectProtocol?

    func start() {
        guard !enabled else { return }
        enabled = true
        generation += 1
        let requestedGeneration = generation
        store.requestFullAccessToEvents { [weak self] granted, error in
            onMain {
                guard let self, self.enabled, self.generation == requestedGeneration else { return }
                self.authorized = granted
                if !granted { Log.error("No calendar access: \(error?.localizedDescription ?? "denied by user")") }
                self.timer = repeatingTimer(30) { [weak self] in self?.refresh() }
            }
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        enabled = false
        generation += 1
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        authorized = false
        upcoming = []
        alerted = []
        onChange?()
    }

    func refresh() {
        guard enabled, authorized else { return }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3 * 3600),
            end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Event(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? L("(No title)"), start: event.startDate, end: event.endDate,
                    link: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
            }
        if events != upcoming {
            upcoming = events
            onChange?()
        }
        alerted.formIntersection(Set(events.map(\.id)))
        for event in events where !alerted.contains(event.id) {
            let until = event.start.timeIntervalSince(now)
            if until <= Double(leadMinutes * 60) && until > -60 {
                alerted.insert(event.id)
                onMeetingSoon?(event)
            }
        }
    }

    var current: Event? { upcoming.first { $0.start <= Date() && $0.end > Date() } }
    var next: Event? { upcoming.first { $0.start > Date() } }
    /// True when the current event has a meeting link.
    var inMeeting: Bool { current?.link != nil }
}

// MARK: - Clipboard

@MainActor
final class ClipboardService {
    private(set) var history = ClipboardHistory()
    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    var onChange: (() -> Void)?

    private static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
    ]

    func start(limit: Int) {
        history.limit = limit
        guard timer == nil else { return }
        timer = repeatingTimer(0.5, fireNow: false) { [weak self] in self?.check() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        history.clear()
    }

    private func check() {
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        let types = Set((board.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.ignoredTypes), let text = board.string(forType: .string) else { return }
        history.add(text)
        onChange?()
    }
}

// MARK: - Finished downloads

@MainActor
final class DownloadsWatcher {
    private var known: Set<String> = []
    private var pending: [String: Int] = [:]  // file name → last seen size
    private var timer: Timer?
    private var path = ""
    var onFinished: ((URL) -> Void)?

    private static let temporaryExtensions: Set<String> = [
        "crdownload", "download", "part", "tmp", "partial", "opdownload",
    ]

    func start(path: String) {
        stop()
        self.path = Paths.expand(path)
        known = Set(list())
        timer = repeatingTimer(3, fireNow: false) { [weak self] in self?.check() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func list() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.filter { !$0.hasPrefix(".") } ?? []
    }

    private func check() {
        for name in list() where !known.contains(name) {
            let ext = (name as NSString).pathExtension.lowercased()
            if Self.temporaryExtensions.contains(ext) { continue }
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? -1
            // A download counts as finished once its size is unchanged across two checks.
            if pending[name] == size {
                pending[name] = nil
                known.insert(name)
                onFinished?(url)
            } else {
                pending[name] = size
            }
        }
    }
}

// MARK: - Weather

@MainActor
final class WeatherService {
    private(set) var now: WeatherNow?
    private var timer: Timer?
    private var location: (Double, Double)?
    var onChange: (() -> Void)?

    func start(latitude: Double, longitude: Double) {
        if let location, location == (latitude, longitude), timer != nil { return }
        location = (latitude, longitude)
        timer?.invalidate()
        timer = repeatingTimer(30 * 60) { [weak self] in self?.fetch() }
    }

    private func fetch() {
        guard let (lat, lon) = location, let url = WeatherNow.url(latitude: lat, longitude: lon) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let weather = WeatherNow.parse(data) else { return }
            onMain {
                self?.now = weather
                self?.onChange?()
            }
        }.resume()
    }
}

// MARK: - Bluetooth headphone battery

@MainActor
final class BluetoothService {
    private(set) var devices: [BluetoothBattery] = []
    private var warned: Set<String> = []
    private var timer: Timer?
    var threshold = 20
    var onLow: ((BluetoothBattery) -> Void)?
    var onChange: (() -> Void)?

    func start() {
        guard timer == nil else { return }
        // system_profiler is slow; checking every 5 minutes is enough.
        timer = repeatingTimer(300) { [weak self] in self?.refresh() }
    }

    func refresh() {
        Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 20) { [weak self] result in
            guard let self else { return }
            self.devices = BluetoothBattery.parse(Data(result.output.utf8))
            for device in self.devices {
                guard let lowest = device.lowest else { continue }
                if lowest <= self.threshold, !self.warned.contains(device.device) {
                    self.warned.insert(device.device)
                    self.onLow?(device)
                } else if lowest > self.threshold + 10 {
                    self.warned.remove(device.device)
                }
            }
            self.onChange?()
        }
    }

    /// Prefers AirPods / Beats.
    var headphones: BluetoothBattery? {
        devices.first {
            $0.device.localizedCaseInsensitiveContains("airpods") || $0.device.localizedCaseInsensitiveContains("beats")
        }
            ?? devices.first { $0.levels["left"] != nil }
    }
}
