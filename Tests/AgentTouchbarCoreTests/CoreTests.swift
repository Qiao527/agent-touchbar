import XCTest
@testable import AgentTouchbarCore

final class ConfigTests: XCTestCase {
    func testDefaultConfigParses() throws {
        let config = try AppConfig.parse(yaml: DefaultConfig.yaml)
        XCTAssertEqual(config.layout.left, ["esc"])
        XCTAssertEqual(config.scenes.first?.name, "开会")
        XCTAssertEqual(config.alertRule(for: AlertKind.agentPermission).priority, 100)
        XCTAssertTrue(config.alertRule(for: AlertKind.agentPermission).sticky)
        XCTAssertEqual(config.widget(id: "weather").options.double("latitude", default: 0), 31.23, accuracy: 0.001)
        XCTAssertEqual(config.widget(id: "dev").options.objects("items").count, 3)
        let keys = config.widget(id: "meeting").options["keys"]?.object?["zoom.us"]?.object
        XCTAssertEqual(keys?["mute"]?.string, "cmd+shift+a")
    }

    func testExampleFileMatchesDefault() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("config/config.example.yaml")
        let example = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(example, DefaultConfig.yaml + "\n", "config/config.example.yaml 需要和 DefaultConfig.yaml 保持一致")
    }

    func testEmptyConfigUsesDefaults() throws {
        let config = try AppConfig.parse(yaml: "")
        XCTAssertEqual(config.layout, Layout())
        XCTAssertEqual(config.server.port, 47800)
        XCTAssertEqual(config.alertRule(for: AlertKind.verificationCode).priority, 90)
    }

    func testUserAlertOverridesDefault() throws {
        let config = try AppConfig.parse(yaml: "alerts:\n  verification_code: { priority: 10, ttl: 5 }\n")
        XCTAssertEqual(config.alertRule(for: AlertKind.verificationCode).priority, 10)
        XCTAssertEqual(config.alertRule(for: AlertKind.agentDone).priority, 60)
    }

    func testWidgetRequiresID() {
        XCTAssertThrowsError(try AppConfig.parse(yaml: "widgets:\n  - type: clock\n"))
    }

    func testWidgetTypeDefaultsToID() throws {
        let config = try AppConfig.parse(yaml: "widgets:\n  - id: clock\n    format: HH:mm:ss\n")
        XCTAssertEqual(config.widget(id: "clock").type, "clock")
        XCTAssertEqual(config.widget(id: "clock").options.string("format"), "HH:mm:ss")
        XCTAssertEqual(config.widget(id: "battery").type, "battery")
    }
}

final class SceneTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    func testAppMatchByNameOrBundleID() {
        let condition = Condition(app: ["iTerm2", "com.apple.Terminal"])
        XCTAssertTrue(condition.matches(Context(frontmostAppName: "iterm2")))
        XCTAssertTrue(condition.matches(Context(frontmostBundleID: "com.apple.terminal")))
        XCTAssertFalse(condition.matches(Context(frontmostAppName: "Safari")))
    }

    func testAllConditionsMustMatchByDefault() {
        let condition = Condition(app: ["zoom.us"], micInUse: true)
        XCTAssertFalse(condition.matches(Context(frontmostAppName: "zoom.us", micInUse: false)))
        XCTAssertTrue(condition.matches(Context(frontmostAppName: "zoom.us", micInUse: true)))
    }

    func testMatchAny() {
        let condition = Condition(app: ["zoom.us"], inMeeting: true, matchAny: true)
        XCTAssertTrue(condition.matches(Context(frontmostAppName: "Safari", inMeeting: true)))
        XCTAssertFalse(condition.matches(Context(frontmostAppName: "Safari")))
    }

    func testTimeRangeAcrossMidnight() {
        let range = TimeRange("23:00-06:00")!
        XCTAssertTrue(range.contains(date("2026-10-25 23:30"), calendar: calendar))
        XCTAssertTrue(range.contains(date("2026-10-26 05:59"), calendar: calendar))
        XCTAssertFalse(range.contains(date("2026-10-26 06:00"), calendar: calendar))
        XCTAssertFalse(range.contains(date("2026-10-26 12:00"), calendar: calendar))
        XCTAssertNil(TimeRange("25:00-06:00"))
    }

    func testWeekdaysAreMondayBased() {
        // 2026-10-25 是周日
        let condition = Condition(weekdays: [7])
        XCTAssertTrue(condition.matches(Context(date: date("2026-10-25 10:00")), calendar: calendar))
        XCTAssertFalse(condition.matches(Context(date: date("2026-10-26 10:00")), calendar: calendar))
    }

    func testResolverUsesFirstMatchAndHide() throws {
        let config = try AppConfig.parse(yaml: DefaultConfig.yaml)
        let coding = SceneMatcher.resolve(layout: config.layout, scenes: config.scenes,
                                          context: Context(frontmostAppName: "iTerm2", date: date("2026-10-25 10:00")),
                                          calendar: calendar)
        XCTAssertEqual(coding.sceneName, "写代码")
        XCTAssertEqual(coding.island, ["agents", "git_branch", "dev"])
        XCTAssertEqual(coding.right, config.layout.right)

        let night = SceneMatcher.resolve(layout: config.layout, scenes: config.scenes,
                                         context: Context(frontmostAppName: "Finder", date: date("2026-10-25 23:30")),
                                         calendar: calendar)
        XCTAssertEqual(night.sceneName, "夜间")
        XCTAssertFalse(night.right.contains("weather"))

        let none = SceneMatcher.resolve(layout: config.layout, scenes: config.scenes,
                                        context: Context(frontmostAppName: "Finder", date: date("2026-10-25 10:00")),
                                        calendar: calendar)
        XCTAssertNil(none.sceneName)
        XCTAssertEqual(none.island, config.layout.island)
    }
}

final class AlertQueueTests: XCTestCase {
    func testOrderingReplacementAndExpiry() {
        var queue = AlertQueue()
        let now = Date()
        XCTAssertTrue(queue.push(Alert(id: "a", kind: "x", source: "t", title: "低", priority: 10, createdAt: now)))
        XCTAssertTrue(queue.push(Alert(id: "b", kind: "x", source: "t", title: "高", priority: 90, createdAt: now,
                                       expiresAt: now.addingTimeInterval(5))))
        XCTAssertEqual(queue.top?.id, "b")
        XCTAssertFalse(queue.push(Alert(id: "a", kind: "x", source: "t", title: "低-更新", priority: 10, createdAt: now)))
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.alert(id: "a")?.title, "低-更新")
        XCTAssertEqual(queue.nextExpiry, now.addingTimeInterval(5))
        XCTAssertEqual(queue.prune(at: now.addingTimeInterval(6)).map(\.id), ["b"])
        XCTAssertEqual(queue.top?.id, "a")
    }

    func testSamePriorityNewestFirst() {
        var queue = AlertQueue()
        let now = Date()
        queue.push(Alert(id: "old", kind: "x", source: "t", title: "", priority: 50, createdAt: now))
        queue.push(Alert(id: "new", kind: "x", source: "t", title: "", priority: 50, createdAt: now.addingTimeInterval(1)))
        XCTAssertEqual(queue.top?.id, "new")
    }

    func testRuleExpiry() {
        let now = Date()
        XCTAssertEqual(AlertRule(priority: 1, ttl: 10).expiry(from: now), now.addingTimeInterval(10))
        XCTAssertNil(AlertRule(priority: 1, ttl: 10, sticky: true).expiry(from: now))
        XCTAssertNil(AlertRule(priority: 1, ttl: nil).expiry(from: now))
    }
}

final class VerificationCodeTests: XCTestCase {
    func extract(_ text: String) -> String? {
        VerificationCodeExtractor.extract(from: text)?.code
    }

    func testChineseBankMessage() {
        let code = VerificationCodeExtractor.extract(
            from: "【招商银行】您尾号1234的账户正在登录，验证码 482913，5分钟内有效，请勿泄露。")
        XCTAssertEqual(code, VerificationCode(code: "482913", source: "招商银行"))
    }

    func testCodeBeforeKeyword() {
        XCTAssertEqual(extract("482913 是你的验证码，请勿告诉他人"), "482913")
    }

    func testEnglishMessages() {
        XCTAssertEqual(extract("G-583920 is your Google verification code."), "583920")
        XCTAssertEqual(extract("Your Apple Account code is: 739102. Don't share it with anyone."), "739102")
    }

    func testAlphanumericCode() {
        XCTAssertEqual(extract("[Steam] Your login code: F7K2Q"), "F7K2Q")
    }

    func testIgnoresAmountsTimesAndMessagesWithoutKeyword() {
        XCTAssertEqual(extract("您的验证码为 6631，本次支付金额 1200元，有效期 10 分钟"), "6631")
        XCTAssertNil(extract("晚上 8 点一起吃饭，订了 2026 号包间"))
        XCTAssertNil(extract("会议号 123456789"))
    }

    func testExtraKeyword() {
        XCTAssertNil(VerificationCodeExtractor.extract(from: "口令 5521"))
        XCTAssertEqual(VerificationCodeExtractor.extract(from: "口令 5521", extraKeywords: ["口令"])?.code, "5521")
    }

    func testSenderFallback() {
        XCTAssertEqual(VerificationCodeExtractor.extract(from: "验证码 9922", sender: "106900")?.source, "106900")
    }

    func testAttributedBodyRoundTrip() {
        let short = "验证码 482913"
        XCTAssertEqual(AttributedBodyDecoder.text(from: AttributedBodyDecoder.encodeForTesting(short)), short)
        let long = String(repeating: "很长的短信内容", count: 30) + " 验证码 123456"
        XCTAssertEqual(AttributedBodyDecoder.text(from: AttributedBodyDecoder.encodeForTesting(long)), long)
        XCTAssertNil(AttributedBodyDecoder.text(from: Data("garbage".utf8)))
    }
}

final class HookTests: XCTestCase {
    func decode(_ json: String) throws -> HookInput {
        try HookInput.decode(Data(json.utf8))
    }

    func testClaudePermissionSummary() throws {
        let input = try decode("""
        {"session_id":"s1","cwd":"/tmp","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "tool_input":{"command":"rm -rf\\n node_modules","description":"清理"}}
        """)
        XCTAssertEqual(input.toolSummary, "Bash: rm -rf node_modules")
        XCTAssertNil(HookMapping.event(agent: "claude", input: input, terminal: nil))
    }

    func testCodexArrayCommand() throws {
        let input = try decode("""
        {"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":["git","push"]}}
        """)
        XCTAssertEqual(input.toolSummary, "Bash: git push")
        XCTAssertEqual(HookMapping.event(agent: "codex", input: input, terminal: nil)?.state, .running)
    }

    func testStateMapping() throws {
        let stop = try decode(#"{"session_id":"s","hook_event_name":"Stop","last_assistant_message":"完成了\n全部测试"}"#)
        let event = HookMapping.event(agent: "claude", input: stop, terminal: "iTerm.app")
        XCTAssertEqual(event?.state, .done)
        XCTAssertEqual(event?.detail, "完成了 全部测试")
        XCTAssertEqual(event?.terminal, "iTerm.app")

        let notify = try decode(#"{"session_id":"s","hook_event_name":"Notification","message":"需要权限","notification_type":"permission_prompt"}"#)
        XCTAssertEqual(HookMapping.event(agent: "claude", input: notify, terminal: nil)?.state, .waiting)

        let idle = try decode(#"{"session_id":"s","hook_event_name":"Notification","message":"等待输入","notification_type":"idle_prompt"}"#)
        XCTAssertEqual(HookMapping.event(agent: "claude", input: idle, terminal: nil)?.state, .done)

        let end = try decode(#"{"session_id":"s","hook_event_name":"SessionEnd"}"#)
        XCTAssertEqual(HookMapping.event(agent: "claude", input: end, terminal: nil)?.state, .ended)
    }

    func testUnknownFieldsAreIgnored() throws {
        let input = try decode(#"{"hook_event_name":"Stop","stop_hook_active":true,"background_tasks":[{"id":"1"}]}"#)
        XCTAssertEqual(HookMapping.event(agent: "claude", input: input, terminal: nil)?.session, "default")
    }

    func testPermissionOutput() throws {
        XCTAssertNil(HookMapping.permissionOutput(.none))
        let allow = try XCTUnwrap(HookMapping.permissionOutput(.allow))
        let object = try JSONSerialization.jsonObject(with: Data(allow.utf8)) as? [String: Any]
        let specific = object?["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(specific?["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((specific?["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        XCTAssertTrue(HookMapping.permissionOutput(.deny)!.contains("\"deny\""))
    }

    func testCodexNotify() {
        let json = #"{"type":"agent-turn-complete","thread-id":"t1","last-assistant-message":"已修复","cwd":"/x"}"#
        let event = HookMapping.codexNotifyEvent(json: Data(json.utf8), terminal: nil)
        XCTAssertEqual(event?.state, .done)
        XCTAssertEqual(event?.session, "t1")
        XCTAssertNil(HookMapping.codexNotifyEvent(json: Data(#"{"type":"other"}"#.utf8), terminal: nil))
    }
}

final class HTTPTests: XCTestCase {
    func testParseCompleteRequest() {
        let raw = "POST /v1/notify HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\nContent-Length: 4\r\n\r\ntest"
        guard case .complete(let request) = HTTPRequest.parse(Data(raw.utf8)) else { return XCTFail() }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/notify")
        XCTAssertEqual(request.bearerToken, "abc")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "test")
    }

    func testNeedMore() {
        XCTAssertEqual(HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc".utf8)), .needMore)
        XCTAssertEqual(HTTPRequest.parse(Data("POST / HTTP/1.1\r\n".utf8)), .needMore)
    }

    func testResponseSerialization() {
        let text = String(data: HTTPResponse(status: 401, body: Data("{}".utf8)).serialized(), encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{}"))
    }

    func testTokenCompare() {
        XCTAssertTrue(Token.matches("abc", "abc"))
        XCTAssertFalse(Token.matches("abc", "abd"))
        XCTAssertFalse(Token.matches("abc", "abcd"))
    }

    func testTokenFileCreatedWithPrivatePermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("token")
        let token = try Token.loadOrCreate(at: url)
        XCTAssertEqual(token.count, 48)
        XCTAssertEqual(try Token.loadOrCreate(at: url), token)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        try? FileManager.default.removeItem(at: dir)
    }
}

final class UtilityTests: XCTestCase {
    func testText() {
        XCTAssertEqual(Text.truncate("一二三四五六", 4), "一二三…")
        XCTAssertEqual(Text.truncate("短", 4), "短")
        XCTAssertEqual(Text.mask("6222020200001234"), "•••• 1234")
        let now = Date()
        XCTAssertEqual(Text.countdown(to: now.addingTimeInterval(299), from: now), "5 分钟后")
        XCTAssertEqual(Text.countdown(to: now.addingTimeInterval(30), from: now), "30 秒后")
        XCTAssertEqual(Text.countdown(to: now.addingTimeInterval(-5), from: now), "现在")
        XCTAssertEqual(Text.countdown(to: now.addingTimeInterval(5400), from: now), "1 小时 30 分后")
        XCTAssertEqual(Text.duration(65), "01:05")
        XCTAssertEqual(Text.duration(3725), "1:02:05")
    }

    func testMeetingLink() {
        let url = MeetingLink.find(in: [nil, "地点：3楼", "加入会议 https://meeting.tencent.com/dm/abc123 密码 1234"])
        XCTAssertEqual(url?.host, "meeting.tencent.com")
        XCTAssertEqual(MeetingLink.find(in: ["https://us02web.zoom.us/j/123"])?.host, "us02web.zoom.us")
        XCTAssertNil(MeetingLink.find(in: ["https://example.com/zoom.us"]))
    }

    func testScriptOutput() {
        let json = ScriptOutput.parse(#"{"text":"BTC 68,210","icon":"sf:bitcoinsign.circle","progress":1.5}"#)
        XCTAssertEqual(json.text, "BTC 68,210")
        XCTAssertEqual(json.icon, "sf:bitcoinsign.circle")
        XCTAssertEqual(json.progress, 1)
        XCTAssertEqual(ScriptOutput.parse("\n第一行\n第二行").text, "第一行")
        XCTAssertEqual(ScriptOutput.parse("{坏的 json").text, "{坏的 json")
    }

    func testClipboardHistory() {
        var history = ClipboardHistory(limit: 3)
        ["a", "b", "c", "a", "d", "  "].forEach { history.add($0) }
        XCTAssertEqual(history.items, ["d", "a", "c"])
    }

    func testPomodoro() {
        var pomodoro = Pomodoro(focusMinutes: 25, restMinutes: 5)
        let start = Date()
        pomodoro.startFocus(at: start)
        XCTAssertNil(pomodoro.tick(at: start.addingTimeInterval(60)))
        XCTAssertEqual(pomodoro.remaining(at: start.addingTimeInterval(60)), 24 * 60)
        XCTAssertEqual(pomodoro.tick(at: start.addingTimeInterval(25 * 60)), .focus)
        XCTAssertTrue(pomodoro.isWaitingForChoice)
        XCTAssertEqual(pomodoro.completedRounds, 1)
        pomodoro.startRest(at: start)
        XCTAssertEqual(pomodoro.phase, .rest)
        pomodoro.stop()
        XCTAssertEqual(pomodoro.phase, .idle)
    }

    func testColor() {
        XCTAssertEqual(RGBColor.parse("#FF0000"), RGBColor(red: 1, green: 0, blue: 0))
        XCTAssertNotNil(RGBColor.parse("green"))
        XCTAssertNil(RGBColor.parse("#12"))
        XCTAssertNil(RGBColor.parse(nil))
    }

    func testKeyCombo() {
        XCTAssertEqual(KeyCombo.parse("cmd+shift+a"), KeyCombo(command: true, shift: true, keyCode: 0x00))
        XCTAssertEqual(KeyCombo.parse("ctrl+opt+right")?.keyCode, 0x7C)
        XCTAssertNil(KeyCombo.parse("hyper+a"))
        XCTAssertNil(KeyCombo.parse("cmd+unknown"))
    }

    func testWeather() {
        let data = Data(#"{"current":{"time":"2026-10-25T10:00","temperature_2m":18.6,"weather_code":61}}"#.utf8)
        let weather = WeatherNow.parse(data)
        XCTAssertEqual(weather?.text, "19°")
        XCTAssertEqual(weather?.symbol.label, "雨")
        XCTAssertNotNil(WeatherNow.url(latitude: 31.2, longitude: 121.4))
    }

    func testBluetoothBattery() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Qiao 的 AirPods Pro":{"device_batteryLevelLeft":"80%",
          "device_batteryLevelRight":"15%","device_batteryLevelCase":"60%","device_address":"x"}},
          {"Magic Mouse":{"device_batteryLevelMain":"55%"}}]}]}
        """
        let devices = BluetoothBattery.parse(Data(json.utf8))
        let airpods = devices.first { $0.device.contains("AirPods") }
        XCTAssertEqual(airpods?.levels["right"], 15)
        XCTAssertEqual(airpods?.lowest, 15)
        XCTAssertEqual(devices.first { $0.device == "Magic Mouse" }?.levels["main"], 55)
    }
}
