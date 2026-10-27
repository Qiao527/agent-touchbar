import Foundation
import XCTest

@testable import AgentTouchbarCore

final class RobustnessTests: XCTestCase {
    func testHTTPRejectsAmbiguousFraming() {
        let requests = [
            "POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab",
            "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
            "POST / HTTP/1.1\r\nContent-Length: +1\r\n\r\na",
            "POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
            "POST / HTTP/1.1\r\nContent-Length: 0\r\n\r\nGET / HTTP/1.1\r\n\r\n",
            "GET / HTTP/1.1\r\nAuthorization: Bearer a\r\nauthorization: Bearer b\r\n\r\n",
            "GET / HTTP/1.1\r\nBad header: x\r\n\r\n",
            "GET / HTTP/1.1\r\nmalformed\r\n\r\n",
            "GET / HTTP/1.1\r\nX-Test: a\u{0}b\r\n\r\n",
            "GET /\r\n\r\n",
            "GET / HTTP/2.0\r\n\r\n",
            "GET / HTTP/1.1 extra\r\n\r\n",
        ]
        for request in requests {
            guard case .invalid = HTTPRequest.parse(Data(request.utf8)) else {
                XCTFail("Accepted malformed request: \(request.debugDescription)")
                continue
            }
        }
    }

    func testHTTPRejectsOversizedDeclaredBodyBeforeReceivingIt() {
        let request = "POST / HTTP/1.1\r\nContent-Length: \(HTTPRequest.maxSize)\r\n\r\n"
        guard case .invalid = HTTPRequest.parse(Data(request.utf8)) else { return XCTFail() }
    }

    func testHTTPHandlesEveryFragmentBoundaryAndBinaryBody() throws {
        let body = Data([0, 255, 13, 10])
        let raw = Data("POST /v1/notify HTTP/1.1\r\nContent-Length: 4\r\n\r\n".utf8) + body
        for length in 0..<raw.count {
            XCTAssertEqual(HTTPRequest.parse(Data(raw.prefix(length))), .needMore)
        }
        guard case .complete(let request) = HTTPRequest.parse(raw) else { return XCTFail() }
        XCTAssertEqual(request.body, body)
    }

    func testInvalidConfigurationIsRejectedBeforeReload() {
        let invalid = [
            "version: 2", "server: {port: 0}", "server: {port: 65536}",
            "agents: {permission_wait: -1}", "clipboard: {max_items: -1}",
            "clipboard: {show: -1}", "theme: {font_size: .nan}",
            "theme: {density: unknown}", "touchbar: {mode: unknown}",
            "verification_codes: {clear_clipboard_after: .inf}",
            "battery: {low_threshold: 101}", "calendar: {lead_minutes: -1}",
            "alerts: {custom: {ttl: .nan}}",
            "widgets: [{id: video, skip_seconds: .inf}]",
            "widgets: [{id: clock}, {id: clock}]", "widgets: [{id: ''}]",
            "widgets: [{id: weather, latitude: 91}]",
            "widgets: [{id: script, interval: -1}]",
            "scenes: [{when: {app: {invalid: value}}}]",
            "scenes: [{when: {time: '24:30-06:00'}}]",
            "scenes: [{when: {weekdays: [0, 8]}}]",
        ]
        for yaml in invalid { XCTAssertThrowsError(try AppConfig.parse(yaml: yaml), yaml) }
    }

    func testExplicitNullTTLAndValidBoundaryConfiguration() throws {
        let config = try AppConfig.parse(
            yaml: """
                alerts: {custom: {ttl: null}}
                server: {port: 65535}
                clipboard: {max_items: 0, show: 0}
                scenes: [{when: {app: Terminal, time: '23:00-24:00'}}]
                """)
        XCTAssertNil(config.alertRule(for: "custom").ttl)
        XCTAssertEqual(config.scenes.first?.when.app, ["Terminal"])
        XCTAssertNil(TimeRange("24:01-06:00"))
    }

    func testNumericOptionConversionsDoNotTrap() {
        for value in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude, Double(Int.max)] {
            XCTAssertNil(ConfigValue.double(value).int)
        }
        XCTAssertEqual(ConfigValue.double(1.9).int, 1)
        XCTAssertEqual(ConfigValue.double(Double(Int.min)).int, Int.min)
    }

    func testNegativeClipboardLimitDoesNotTrap() {
        var history = ClipboardHistory(limit: -1)
        history.add("private")
        XCTAssertTrue(history.items.isEmpty)
        history.limit = 2
        history.add("one")
        history.add("two")
        history.limit = 0
        history.add("three")
        XCTAssertTrue(history.items.isEmpty)
    }

    func testTokenPersistenceFailuresAreReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try Token.loadOrCreate(at: dir))
        let blockingFile = dir.appendingPathComponent("file")
        try Data("existing".utf8).write(to: blockingFile)
        XCTAssertThrowsError(try Token.loadOrCreate(at: blockingFile.appendingPathComponent("token")))
        XCTAssertEqual(try String(contentsOf: blockingFile, encoding: .utf8), "existing")
    }

    func testCommandRunnerHandlesOutputExitAndLaunchFailure() {
        let result = CommandRunner.run("/bin/sh", ["-c", "printf hello; printf error >&2; exit 7"], timeout: 2)
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.output, "hello")
        XCTAssertEqual(result.error, "error")
        XCTAssertEqual(CommandRunner.run("/nonexistent/atb-command", [], timeout: 1).status, -1)
    }

    func testCommandRunnerTimesOutAfterStreamsClose() {
        let start = ProcessInfo.processInfo.systemUptime
        let result = CommandRunner.run("/bin/sh", ["-c", "exec 1>&- 2>&-; exec sleep 5"], timeout: 0.1)
        XCTAssertEqual(result.status, -2)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }

    func testCommandRunnerDrainsLargeOutputWithABoundedBuffer() {
        let result = CommandRunner.run("/usr/bin/head", ["-c", "2097152", "/dev/zero"], timeout: 5, outputLimit: 1024)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.utf8.count, 1024)
    }

    func testFormattingDoesNotInterpretArgumentPlaceholders() {
        XCTAssertEqual(Localization.format("{0}: {1}", ["literal {1}", "value"]), "literal {1}: value")
        XCTAssertEqual(
            Localization.format("{1} {0} {1} {9}", ["🙂", "long replacement"]), "long replacement 🙂 long replacement {9}"
        )
    }
}
