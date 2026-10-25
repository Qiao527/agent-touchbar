import Foundation

/// A button on an alert.
public struct AlertAction: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Color name (green / red / orange / blue / purple / gray) or #RRGGBB
    public var color: String?
    /// Optional shell command to run on tap
    public var run: String?
    /// Whether tapping dismisses the alert
    public var dismisses: Bool

    public init(id: String, title: String, color: String? = nil, run: String? = nil, dismisses: Bool = true) {
        self.id = id
        self.title = title
        self.color = color
        self.run = run
        self.dismisses = dismisses
    }

    enum CodingKeys: String, CodingKey { case id, title, color, run, dismisses }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? title
        color = try c.decodeIfPresent(String.self, forKey: .color)
        run = try c.decodeIfPresent(String.self, forKey: .run)
        dismisses = try c.decodeIfPresent(Bool.self, forKey: .dismisses) ?? true
    }
}

public struct Alert: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var source: String
    public var title: String
    public var detail: String?
    /// `sf:<symbol name>` or an image path
    public var icon: String?
    public var color: String?
    public var priority: Int
    public var createdAt: Date
    public var expiresAt: Date?
    public var actions: [AlertAction]
    /// Action id to run when the alert body is tapped
    public var tapAction: String?
    /// Extra data, e.g. the verification code or a meeting link
    public var payload: [String: String]

    public init(
        id: String = UUID().uuidString, kind: String, source: String, title: String,
        detail: String? = nil, icon: String? = nil, color: String? = nil, priority: Int = 50,
        createdAt: Date = Date(), expiresAt: Date? = nil, actions: [AlertAction] = [],
        tapAction: String? = nil, payload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.detail = detail
        self.icon = icon
        self.color = color
        self.priority = priority
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.actions = actions
        self.tapAction = tapAction
        self.payload = payload
    }

    public func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return date >= expiresAt
    }
}

/// Alert queue sorted by priority, with automatic expiry. Pushing an existing id replaces the old alert.
public struct AlertQueue: Equatable, Sendable {
    public private(set) var alerts: [Alert] = []

    public init() {}

    /// Returns true for a new alert (not an update), so the caller can decide whether to wake the Touch Bar.
    @discardableResult
    public mutating func push(_ alert: Alert) -> Bool {
        if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[index] = alert
            sort()
            return false
        }
        alerts.append(alert)
        sort()
        return true
    }

    @discardableResult
    public mutating func remove(id: String) -> Alert? {
        guard let index = alerts.firstIndex(where: { $0.id == id }) else { return nil }
        return alerts.remove(at: index)
    }

    public mutating func removeAll(where predicate: (Alert) -> Bool) {
        alerts.removeAll(where: predicate)
    }

    /// Removes expired alerts and returns them.
    @discardableResult
    public mutating func prune(at date: Date) -> [Alert] {
        let expired = alerts.filter { $0.isExpired(at: date) }
        alerts.removeAll { $0.isExpired(at: date) }
        return expired
    }

    public var top: Alert? { alerts.first }
    public var isEmpty: Bool { alerts.isEmpty }
    public var count: Int { alerts.count }

    public func alert(id: String) -> Alert? { alerts.first { $0.id == id } }

    /// Next expiry time, used to schedule a timer.
    public var nextExpiry: Date? { alerts.compactMap(\.expiresAt).min() }

    private mutating func sort() {
        // Higher priority first; newest first within the same priority
        alerts.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt > $1.createdAt
        }
    }
}
