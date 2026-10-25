import Foundation

/// 当前环境，由程序定期采集
public struct Context: Equatable, Sendable {
    public var frontmostBundleID: String?
    public var frontmostAppName: String?
    public var micInUse: Bool
    /// 正在播放音乐的程序，例如 "spotify"
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

/// 一条场景规则
public struct Scene: Decodable, Equatable, Sendable {
    public var name: String
    public var when: Condition
    public var left: [String]?
    public var island: [String]?
    public var right: [String]?
    public var hide: [String]

    enum CodingKeys: String, CodingKey { case name, when, left, island, right, hide }

    public init(name: String, when: Condition, left: [String]? = nil, island: [String]? = nil,
                right: [String]? = nil, hide: [String] = []) {
        self.name = name
        self.when = when
        self.left = left
        self.island = island
        self.right = right
        self.hide = hide
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.value(.name, default: "未命名场景")
        when = try c.value(.when, default: Condition())
        left = try c.decodeIfPresent([String].self, forKey: .left)
        island = try c.decodeIfPresent([String].self, forKey: .island)
        right = try c.decodeIfPresent([String].self, forKey: .right)
        hide = try c.value(.hide, default: [])
    }
}

/// 场景的触发条件。写了的条件默认要全部满足；`match: any` 时满足任意一个即可。
public struct Condition: Decodable, Equatable, Sendable {
    /// 前台程序的 bundle id 或名字
    public var app: [String]?
    public var micInUse: Bool?
    /// 正在播放的程序，例如 spotify
    public var playing: String?
    /// "HH:mm-HH:mm"，可以跨午夜
    public var time: String?
    /// 1 = 周一 … 7 = 周日
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

    public init(app: [String]? = nil, micInUse: Bool? = nil, playing: String? = nil, time: String? = nil,
                weekdays: [Int]? = nil, onBattery: Bool? = nil, inMeeting: Bool? = nil, matchAny: Bool = false) {
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
        if let list = try? c.decodeIfPresent([String].self, forKey: .app) {
            app = list
        } else if let single = try? c.decodeIfPresent(String.self, forKey: .app) {
            app = [single]
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
            // Calendar 的 weekday：1 = 周日；换算成 1 = 周一
            let weekday = calendar.component(.weekday, from: context.date)
            let mondayBased = weekday == 1 ? 7 : weekday - 1
            checks.append(weekdays.contains(mondayBased))
        }
        if let onBattery { checks.append(context.onBattery == onBattery) }
        if let inMeeting { checks.append(context.inMeeting == inMeeting) }

        // 没写任何条件的场景永远匹配，可以当作兜底
        guard !checks.isEmpty else { return true }
        return matchAny ? checks.contains(true) : !checks.contains(false)
    }
}

/// "22:00-06:00" 这样的时间段
public struct TimeRange: Equatable, Sendable {
    public var start: Int   // 当天的分钟数
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
              (0...24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start <= end { return now >= start && now < end }
        return now >= start || now < end   // 跨午夜
    }
}

/// 根据场景规则算出每个区域该显示哪些组件
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
    /// 第一个匹配的场景生效；没有匹配时使用默认布局
    public static func resolve(layout: Layout, scenes: [Scene], context: Context,
                               calendar: Calendar = .current) -> ResolvedLayout {
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
