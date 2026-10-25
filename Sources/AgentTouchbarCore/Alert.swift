import Foundation

/// 提醒上的一个按钮
public struct AlertAction: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// 颜色名：green / red / orange / blue / purple / gray，或 #RRGGBB
    public var color: String?
    /// 点击后执行的 shell 命令（可选）
    public var run: String?
    /// 点击后是否关闭这条提醒
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
    /// `sf:符号名` 或图片路径
    public var icon: String?
    public var color: String?
    public var priority: Int
    public var createdAt: Date
    public var expiresAt: Date?
    public var actions: [AlertAction]
    /// 点击提醒正文时执行的动作 id
    public var tapAction: String?
    /// 附带数据，例如验证码本身、会议链接
    public var payload: [String: String]

    public init(id: String = UUID().uuidString, kind: String, source: String, title: String,
                detail: String? = nil, icon: String? = nil, color: String? = nil, priority: Int = 50,
                createdAt: Date = Date(), expiresAt: Date? = nil, actions: [AlertAction] = [],
                tapAction: String? = nil, payload: [String: String] = [:]) {
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

/// 提醒队列：按优先级排序，自动过期。同一个 id 再次发送会替换旧的。
public struct AlertQueue: Equatable, Sendable {
    public private(set) var alerts: [Alert] = []

    public init() {}

    /// 返回 true 表示这是一条新提醒（不是更新），程序可以借此决定是否唤醒 Touch Bar
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

    /// 删除过期提醒，返回被删除的提醒
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

    /// 下一个过期时间，用来安排定时器
    public var nextExpiry: Date? { alerts.compactMap(\.expiresAt).min() }

    private mutating func sort() {
        // 优先级高的在前；同优先级时新的在前
        alerts.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt > $1.createdAt
        }
    }
}
