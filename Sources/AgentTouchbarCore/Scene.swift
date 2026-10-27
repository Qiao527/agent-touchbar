import Foundation

/// Current environment, sampled periodically by the app.
public struct Context: Equatable, Sendable {
    public var frontmostBundleID: String?
    public var frontmostAppName: String?
    public var micInUse: Bool
    /// App currently playing audio, e.g. "spotify"
    public var nowPlaying: String?
    public var onBattery: Bool
    public var inMeeting: Bool
    public var date: Date

    public init(
        frontmostBundleID: String? = nil,
        frontmostAppName: String? = nil,
        micInUse: Bool = false,
        nowPlaying: String? = nil,
        onBattery: Bool = false,
        inMeeting: Bool = false,
        date: Date = Date()
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.frontmostAppName = frontmostAppName
        self.micInUse = micInUse
        self.nowPlaying = nowPlaying
        self.onBattery = onBattery
        self.inMeeting = inMeeting
        self.date = date
    }
}

/// A scene rule.
public struct Scene: Decodable, Equatable, Sendable {
    public var name: String
    public var when: Condition
    public var left: [String]?
    public var island: [String]?
    public var right: [String]?
    public var hide: [String]

    enum CodingKeys: String, CodingKey { case name, when, left, island, right, hide }

    public init(
        name: String, when: Condition, left: [String]? = nil, island: [String]? = nil,
        right: [String]? = nil, hide: [String] = []
    ) {
        self.name = name
        self.when = when
        self.left = left
        self.island = island
        self.right = right
        self.hide = hide
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.value(.name, default: L("Untitled scene"))
        when = try c.value(.when, default: Condition())
        left = try c.decodeIfPresent([String].self, forKey: .left)
        island = try c.decodeIfPresent([String].self, forKey: .island)
        right = try c.decodeIfPresent([String].self, forKey: .right)
        hide = try c.value(.hide, default: [])
    }
}

/// Scene trigger. All listed conditions must hold by default; with `match: any`, one is enough.
public struct Condition: Decodable, Equatable, Sendable {
    /// Bundle id or name of the frontmost app
    public var app: [String]?
    public var micInUse: Bool?
    /// App currently playing, e.g. spotify
    public var playing: String?
    /// "HH:mm-HH:mm"; may wrap past midnight
    public var time: String?
    /// 1 = Monday … 7 = Sunday
    public var weekdays: [Int]?
    public var onBattery: Bool?
    public var inMeeting: Bool?
    public var matchAny: Bool = false

    enum CodingKeys: String, CodingKey {
        case app, playing, time, weekdays, match
        case micInUse = "mic_in_use"
        case onBattery = "on_battery"
        case inMeeting = "in_meeting"
    }

    public init(
        app: [String]? = nil, micInUse: Bool? = nil, playing: String? = nil, time: String? = nil,
        weekdays: [Int]? = nil, onBattery: Bool? = nil, inMeeting: Bool? = nil, matchAny: Bool = false
    ) {
        self.app = app
        self.micInUse = micInUse
        self.playing = playing
        self.time = time
        self.weekdays = weekdays
        self.onBattery = onBattery
        self.inMeeting = inMeeting
        self.matchAny = matchAny
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.app), try !c.decodeNil(forKey: .app) {
            if let single = try? c.decode(String.self, forKey: .app) {
                app = [single]
            } else {
                app = try c.decode([String].self, forKey: .app)
            }
        }
        micInUse = try c.decodeIfPresent(Bool.self, forKey: .micInUse)
        playing = try c.decodeIfPresent(String.self, forKey: .playing)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays)
        onBattery = try c.decodeIfPresent(Bool.self, forKey: .onBattery)
        inMeeting = try c.decodeIfPresent(Bool.self, forKey: .inMeeting)
        matchAny = (try c.decodeIfPresent(String.self, forKey: .match))?.lowercased() == "any"
    }

    public func matches(_ context: Context, calendar: Calendar = .current) -> Bool {
        var checks: [Bool] = []

        if let app {
            let candidates = [context.frontmostBundleID, context.frontmostAppName]
                .compactMap { $0?.lowercased() }
            checks.append(app.contains { candidates.contains($0.lowercased()) })
        }
        if let micInUse { checks.append(context.micInUse == micInUse) }
        if let playing { checks.append(context.nowPlaying?.lowercased() == playing.lowercased()) }
        if let time { checks.append(TimeRange(time)?.contains(context.date, calendar: calendar) ?? false) }
        if let weekdays {
            // Calendar weekday is 1 = Sunday; convert to 1 = Monday
            let weekday = calendar.component(.weekday, from: context.date)
            let mondayBased = weekday == 1 ? 7 : weekday - 1
            checks.append(weekdays.contains(mondayBased))
        }
        if let onBattery { checks.append(context.onBattery == onBattery) }
        if let inMeeting { checks.append(context.inMeeting == inMeeting) }

        // A scene with no conditions always matches and works as a fallback
        guard !checks.isEmpty else { return true }
        return matchAny ? checks.contains(true) : !checks.contains(false)
    }
}

/// A time range such as "22:00-06:00".
public struct TimeRange: Equatable, Sendable {
    public var start: Int  // minutes since midnight
    public var end: Int

    public init?(_ text: String) {
        let parts = text.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let start = Self.minutes(parts[0]), let end = Self.minutes(parts[1]) else {
            return nil
        }
        self.start = start
        self.end = end
    }

    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
            (0...24).contains(h), (0..<60).contains(m), (h < 24 || m == 0)
        else { return nil }
        return h * 60 + m
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start <= end { return now >= start && now < end }
        return now >= start || now < end  // wraps past midnight
    }
}

/// Widgets each zone should show after applying scene rules.
public struct ResolvedLayout: Equatable, Sendable {
    public var sceneName: String?
    public var left: [String]
    public var island: [String]
    public var right: [String]

    public init(sceneName: String?, left: [String], island: [String], right: [String]) {
        self.sceneName = sceneName
        self.left = left
        self.island = island
        self.right = right
    }
}

public enum SceneMatcher {
    /// The first matching scene wins; with no match, the default layout is used.
    public static func resolve(
        layout: Layout, scenes: [Scene], context: Context,
        calendar: Calendar = .current
    ) -> ResolvedLayout {
        guard let scene = scenes.first(where: { $0.when.matches(context, calendar: calendar) }) else {
            return ResolvedLayout(sceneName: nil, left: layout.left, island: layout.island, right: layout.right)
        }
        let hidden = Set(scene.hide)
        return ResolvedLayout(
            sceneName: scene.name,
            left: (scene.left ?? layout.left).filter { !hidden.contains($0) },
            island: (scene.island ?? layout.island).filter { !hidden.contains($0) },
            right: (scene.right ?? layout.right).filter { !hidden.contains($0) }
        )
    }
}
