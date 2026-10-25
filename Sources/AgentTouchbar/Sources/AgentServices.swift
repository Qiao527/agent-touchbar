import AppKit
import AgentTouchbarCore
import Network
import SQLite3

// MARK: - 本地 HTTP 服务

/// 只监听 127.0.0.1，每个请求都要带 token
@MainActor
final class AgentServer {
    typealias Responder = (HTTPResponse) -> Void
    var handler: ((HTTPRequest, @escaping Responder) -> Void)?
    private var listener: NWListener?
    private let token: String
    private(set) var port: Int = 0
    private(set) var lastError: String?

    init(token: String) {
        self.token = token
    }

    func start(port: Int) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    if case .failed(let error) = state {
                        self?.lastError = "端口 \(port) 启动失败：\(error)"
                        Log.error(self?.lastError ?? "")
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            self.port = port
            lastError = nil
            Log.info("本地服务已启动：127.0.0.1:\(port)")
        } catch {
            lastError = "端口 \(port) 启动失败：\(error.localizedDescription)"
            Log.error(lastError ?? "")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        // 再确认一次对方来自本机
        if case .hostPort(let host, _) = connection.endpoint {
            // 地址可能带网卡后缀，例如 127.0.0.1%lo0
            let text = "\(host)"
            guard text.hasPrefix("127.") || text.hasPrefix("::1") || text.hasPrefix("localhost") else {
                connection.cancel()
                return
            }
        }
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequest.parse(buffer) {
                case .needMore where !isComplete && error == nil:
                    self.receive(connection, buffer: buffer)
                case .complete(let request):
                    self.handle(request, connection)
                case .invalid(let reason):
                    self.reply(connection, .error(400, reason))
                default:
                    connection.cancel()
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest, _ connection: NWConnection) {
        guard let provided = request.bearerToken, Token.matches(provided, token) else {
            return reply(connection, .error(401, "token 不正确"))
        }
        if request.path == "/v1/health" {
            return reply(connection, .json(["ok": true]))
        }
        guard let handler else { return reply(connection, .error(404, "未就绪")) }
        handler(request) { [weak self] response in
            self?.reply(connection, response)
        }
    }

    private func reply(_ connection: NWConnection, _ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - Claude Code / Codex 会话

@MainActor
final class AgentTracker {
    struct Session: Equatable {
        var agent: String
        var id: String
        var state: AgentState
        var detail: String?
        var cwd: String?
        var terminal: String?
        var updated: Date
        var started: Date

        var displayName: String {
            switch agent.lowercased() {
            case "claude": return "Claude"
            case "codex": return "Codex"
            default: return agent
            }
        }

        var project: String? {
            cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
    }

    private(set) var sessions: [String: Session] = [:]
    var onChange: (() -> Void)?
    private let alerts: AlertCenter
    private var timer: Timer?
    /// 等待 Touch Bar 点击的权限请求
    private var pendingPermissions: [String: (PermissionDecision) -> Void] = [:]

    init(alerts: AlertCenter) {
        self.alerts = alerts
    }

    func start() {
        // 两小时没动静的会话视为已结束
        timer = repeatingTimer(60, fireNow: false) { [weak self] in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-7200)
            let before = self.sessions.count
            self.sessions = self.sessions.filter { $0.value.updated > cutoff }
            if self.sessions.count != before { self.onChange?() }
        }
    }

    /// 按状态排序：等你确认的最前，然后是正在运行、已完成
    var active: [Session] {
        sessions.values.sorted { a, b in
            func rank(_ s: AgentState) -> Int {
                switch s {
                case .waiting: return 0
                case .running: return 1
                case .done: return 2
                case .idle: return 3
                case .ended: return 4
                }
            }
            if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
            return a.updated > b.updated
        }
    }

    /// 最近活动的会话所在目录，给 git 分支组件用
    var latestCwd: String? {
        sessions.values.max { $0.updated < $1.updated }?.cwd
    }

    func handle(_ event: AgentEvent) {
        let key = "\(event.agent):\(event.session)"
        if event.state == .ended {
            sessions[key] = nil
            alerts.dismissAll { $0.payload["session"] == key }
            onChange?()
            return
        }
        let now = Date()
        var session = sessions[key] ?? Session(agent: event.agent, id: event.session, state: event.state,
                                               cwd: event.cwd, terminal: event.terminal, updated: now, started: now)
        let previous = session.state
        session.state = event.state
        session.detail = event.detail ?? (event.state == previous ? session.detail : nil)
        session.cwd = event.cwd ?? session.cwd
        session.terminal = event.terminal ?? session.terminal
        session.updated = now
        if previous == .done || previous == .idle, event.state == .running { session.started = now }
        sessions[key] = session
        onChange?()

        let name = session.displayName + (session.project.map { " · \($0)" } ?? "")
        let jump = AlertAction(id: "jump", title: "跳回", color: "blue")
        switch event.state {
        case .done where previous != .done:
            alerts.dismissAll { $0.payload["session"] == key && $0.kind != AlertKind.agentDone }
            alerts.post(kind: AlertKind.agentDone, id: "agent-done-\(key)", source: event.agent,
                        title: "\(name) 完成了", detail: session.detail, icon: "sf:checkmark.circle.fill",
                        color: "green", actions: [jump], tapAction: "jump", payload: ["session": key]) { [weak self] action in
                if action == "jump" || action == "tap" { self?.jump(to: key) }
            }
        case .waiting:
            // 权限请求已经在 Touch Bar 上显示时，不重复提醒
            guard !alerts.queue.alerts.contains(where: { $0.payload["session"] == key && $0.kind == AlertKind.agentPermission })
            else { return }
            alerts.post(kind: AlertKind.agentPermission, id: "agent-wait-\(key)", source: event.agent,
                        title: "\(name) 等你回复", detail: session.detail, icon: "sf:hand.raised.fill",
                        color: "orange", actions: [jump], tapAction: "jump", payload: ["session": key]) { [weak self] action in
                if action == "jump" || action == "tap" { self?.jump(to: key) }
            }
        case .running:
            alerts.dismissAll { $0.payload["session"] == key }
        default:
            break
        }
    }

    /// 权限请求：在 Touch Bar 上显示"允许 / 拒绝 / 去终端"，等你点击或超时
    func requestPermission(_ request: PermissionRequestMessage, reply: @escaping (PermissionDecision) -> Void) {
        let key = "\(request.agent):\(request.session)"
        handle(AgentEvent(agent: request.agent, session: request.session, state: .waiting,
                          detail: request.summary, cwd: request.cwd, terminal: request.terminal))
        alerts.dismiss(id: "agent-wait-\(key)")

        let alertID = "perm-\(UUID().uuidString)"
        var finished = false
        let finish: (PermissionDecision) -> Void = { [weak self] decision in
            guard !finished else { return }
            finished = true
            self?.pendingPermissions[alertID] = nil
            reply(decision)
        }
        pendingPermissions[alertID] = finish

        let name = (sessions[key]?.displayName ?? request.agent) + (sessions[key]?.project.map { " · \($0)" } ?? "")
        alerts.post(
            kind: AlertKind.agentPermission, id: alertID, source: request.agent,
            title: "\(name) 请求权限", detail: request.summary, icon: "sf:lock.shield.fill", color: "orange",
            actions: [
                AlertAction(id: "allow", title: "允许", color: "green"),
                AlertAction(id: "deny", title: "拒绝", color: "red"),
                AlertAction(id: "terminal", title: "去终端", color: "gray"),
            ],
            payload: ["session": key], ttl: Double(request.wait)
        ) { [weak self] action in
            switch action {
            case "allow": finish(.allow)
            case "deny": finish(.deny)
            case "terminal":
                finish(.none)
                self?.jump(to: key)
            default: finish(.none)   // 超时或被清除
            }
        }

        // 保险：alert 规则可能是 sticky，这里按请求的等待时间强制结束
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(request.wait)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingPermissions[alertID] != nil else { return }
                self.alerts.dismiss(id: alertID)
                finish(.none)
            }
        }
    }

    func jump(to key: String) {
        AppActivator.activate(terminal: sessions[key]?.terminal)
    }
}

// MARK: - 验证码（读取"信息"数据库）

@MainActor
final class MessagesWatcher {
    private var db: OpaquePointer?
    private var lastRowID: Int64 = 0
    private var timer: Timer?
    var extraKeywords: [String] = []
    var onCode: ((VerificationCode) -> Void)?
    private(set) var needsFullDiskAccess = false

    func start() {
        guard timer == nil else { return }
        timer = repeatingTimer(2) { [weak self] in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let db { sqlite3_close(db) }
        db = nil
    }

    private func open() -> Bool {
        if db != nil { return true }
        let path = Paths.home.appendingPathComponent("Library/Messages/chat.db").path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2("file:\(path)?mode=ro", &handle, flags, nil) == SQLITE_OK,
              sqlite3_exec(handle, "SELECT 1 FROM message LIMIT 1", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            if !needsFullDiskAccess { Log.error("无法读取信息数据库，需要完全磁盘访问权限") }
            needsFullDiskAccess = true
            return false
        }
        needsFullDiskAccess = false
        db = handle
        // 从当前最新的一条开始，不处理旧短信
        lastRowID = query("SELECT IFNULL(MAX(ROWID), 0) FROM message", []).first.flatMap { Int64($0[0] ?? "") } ?? 0
        return true
    }

    private func poll() {
        guard open() else { return }
        let sql = """
        SELECT m.ROWID, m.text, h.id, m.attributedBody FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.ROWID > ? AND m.is_from_me = 0 ORDER BY m.ROWID ASC LIMIT 50
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // 数据库被替换等情况：关掉重新打开
            sqlite3_close(db)
            db = nil
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastRowID)
        while sqlite3_step(statement) == SQLITE_ROW {
            lastRowID = sqlite3_column_int64(statement, 0)
            var text = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let sender = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            if text?.isEmpty ?? true, let blob = sqlite3_column_blob(statement, 3) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 3)))
                text = AttributedBodyDecoder.text(from: data)
            }
            guard let text, let code = VerificationCodeExtractor.extract(
                from: text, sender: sender, extraKeywords: extraKeywords) else { continue }
            onCode?(code)
        }
    }

    private func query(_ sql: String, _ args: [Int64]) -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        for (i, arg) in args.enumerated() { sqlite3_bind_int64(statement, Int32(i + 1), arg) }
        var rows: [[String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = sqlite3_column_count(statement)
            rows.append((0..<count).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
        return rows
    }
}
