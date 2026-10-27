import AgentTouchbarCore
import AppKit
import Network
import SQLite3

// MARK: - Local HTTP server

/// Listens on 127.0.0.1 only; every request must carry the token.
@MainActor
final class AgentServer {
    typealias Responder = (HTTPResponse) -> Void
    var handler: ((HTTPRequest, @escaping Responder) -> Void)?
    private var listener: NWListener?
    private let token: String
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var reading: Set<ObjectIdentifier> = []
    private(set) var port: Int = 0
    private(set) var lastError: String?

    init(token: String) {
        self.token = token
    }

    func start(port: Int) {
        stop()
        guard !token.isEmpty, (1...65535).contains(port),
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else {
            lastError = "Local server requires a valid port and a nonempty token"
            return
        }
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
                        self?.lastError = L("Failed to start on port {0}: {1}", port, "\(error)")
                        Log.error("Failed to start server on port \(port): \(error)")
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            self.port = port
            lastError = nil
            Log.info("Local server started: 127.0.0.1:\(port)")
        } catch {
            lastError = L("Failed to start on port {0}: {1}", port, error.localizedDescription)
            Log.error("Failed to start server on port \(port): \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let active = Array(connections.values)
        connections.removeAll()
        reading.removeAll()
        active.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        // Double-check that the peer is local.
        if case .hostPort(let host, _) = connection.endpoint {
            // The address may carry an interface suffix, e.g. 127.0.0.1%lo0.
            let text = "\(host)"
            guard text.hasPrefix("127.") || text.hasPrefix("::1") || text.hasPrefix("localhost") else {
                connection.cancel()
                return
            }
        }
        guard connections.count < 64 else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        reading.insert(id)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .cancelled, .failed:
                    self?.connections[id] = nil
                    self?.reading.remove(id)
                default: break
                }
            }
        }
        // Slow or incomplete requests cannot hold connections indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            MainActor.assumeIsolated {
                guard self?.reading.contains(id) == true else { return }
                connection?.cancel()
            }
        }
        // Permission polling is capped at 300 seconds, with a small response margin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 310) { [weak connection] in connection?.cancel() }
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequest.parse(buffer) {
                case .needMore where !isComplete && error == nil:
                    self.receive(connection, buffer: buffer)
                case .complete(let request):
                    self.reading.remove(ObjectIdentifier(connection))
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
            return reply(connection, .error(401, "Invalid token"))
        }
        if request.path == "/v1/health" {
            guard request.method == "GET" else {
                return reply(connection, .error(405, "Only GET is supported"))
            }
            return reply(connection, .json(["ok": true]))
        }
        guard let handler else { return reply(connection, .error(404, "Not ready")) }
        handler(request) { [weak self] response in
            self?.reply(connection, response)
        }
    }

    private func reply(_ connection: NWConnection, _ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - Claude Code / Codex sessions

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
    /// Permission requests waiting for a Touch Bar tap.
    private var pendingPermissions: [String: (PermissionDecision) -> Void] = [:]

    init(alerts: AlertCenter) {
        self.alerts = alerts
    }

    func start() {
        // Sessions with no activity for two hours are treated as ended.
        timer = repeatingTimer(60, fireNow: false) { [weak self] in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-7200)
            let before = self.sessions.count
            self.sessions = self.sessions.filter { $0.value.updated > cutoff }
            if self.sessions.count != before { self.onChange?() }
        }
    }

    /// Sorted by state: waiting on you first, then running, then done.
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

    /// Working directory of the most recently active session, used by the git branch widget.
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
        var session =
            sessions[key]
            ?? Session(
                agent: event.agent, id: event.session, state: event.state,
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
        let jump = AlertAction(id: "jump", title: L("Jump back"), color: "blue")
        switch event.state {
        case .done where previous != .done:
            alerts.dismissAll { $0.payload["session"] == key && $0.kind != AlertKind.agentDone }
            alerts.post(
                kind: AlertKind.agentDone, id: "agent-done-\(key)", source: event.agent,
                title: L("{0} finished", name), detail: session.detail, icon: "sf:checkmark.circle.fill",
                color: "green", actions: [jump], tapAction: "jump", payload: ["session": key]
            ) { [weak self] action in
                if action == "jump" || action == "tap" { self?.jump(to: key) }
            }
        case .waiting:
            // Skip the reminder if a permission request is already on the Touch Bar.
            guard
                !alerts.queue.alerts.contains(where: {
                    $0.payload["session"] == key && $0.kind == AlertKind.agentPermission
                })
            else { return }
            alerts.post(
                kind: AlertKind.agentPermission, id: "agent-wait-\(key)", source: event.agent,
                title: L("{0} is waiting for you", name), detail: session.detail, icon: "sf:hand.raised.fill",
                color: "orange", actions: [jump], tapAction: "jump", payload: ["session": key]
            ) { [weak self] action in
                if action == "jump" || action == "tap" { self?.jump(to: key) }
            }
        case .running:
            alerts.dismissAll { $0.payload["session"] == key }
        default:
            break
        }
    }

    /// Permission request: shows "Allow / Deny / Open terminal" on the Touch Bar and waits for a tap or timeout.
    func requestPermission(_ request: PermissionRequestMessage, reply: @escaping (PermissionDecision) -> Void) {
        let key = "\(request.agent):\(request.session)"
        handle(
            AgentEvent(
                agent: request.agent, session: request.session, state: .waiting,
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
            title: L("{0} requests permission", name), detail: request.summary, icon: "sf:lock.shield.fill",
            color: "orange",
            actions: [
                AlertAction(id: "allow", title: L("Allow"), color: "green"),
                AlertAction(id: "deny", title: L("Deny"), color: "red"),
                AlertAction(id: "terminal", title: L("Open terminal"), color: "gray"),
            ],
            payload: ["session": key], ttl: Double(max(5, min(request.wait, 300)))
        ) { [weak self] action in
            switch action {
            case "allow": finish(.allow)
            case "deny": finish(.deny)
            case "terminal":
                finish(.none)
                self?.jump(to: key)
            default: finish(.none)  // timed out or dismissed
            }
        }

        // Safety net: alert rules may make it sticky, so force-finish after the requested wait time.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(5, min(request.wait, 300)))) { [weak self] in
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

// MARK: - Verification codes (reads the Messages database)

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
            sqlite3_exec(handle, "SELECT 1 FROM message LIMIT 1", nil, nil, nil) == SQLITE_OK
        else {
            sqlite3_close(handle)
            if !needsFullDiskAccess { Log.error("Cannot read the Messages database; Full Disk Access is required") }
            needsFullDiskAccess = true
            return false
        }
        needsFullDiskAccess = false
        db = handle
        // Start from the newest message; ignore older ones.
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
            // The database may have been replaced; close and reopen.
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
            guard let text,
                let code = VerificationCodeExtractor.extract(
                    from: text, sender: sender, extraKeywords: extraKeywords)
            else { continue }
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
            rows.append(
                (0..<count).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
        }
        return rows
    }
}
