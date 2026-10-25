import XCTest

@testable import AgentTouchbarCore

final class LocalizationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every L("...") literal in the code base must have a Chinese translation.
    func testEveryLocalizedStringHasATranslation() throws {
        let literals = try localizedLiterals()
        XCTAssertFalse(literals.isEmpty, "found no L(...) calls; is the scanner broken?")
        let missing = literals.filter { Localization.simplifiedChinese[$0.key] == nil }
        let report = missing.map { "\($0.file): \($0.key)" }.sorted().joined(separator: "\n")
        XCTAssertTrue(missing.isEmpty, "missing zh-Hans translations:\n\(report)")
    }

    /// Translations must keep the same {0}, {1}, ... placeholders.
    func testPlaceholdersMatch() {
        for (english, chinese) in Localization.simplifiedChinese {
            XCTAssertEqual(
                placeholders(in: english), placeholders(in: chinese), "placeholder mismatch for \"\(english)\"")
        }
    }

    /// Translations nobody uses any more are probably leftovers.
    func testNoUnusedTranslations() throws {
        let used = Set(try localizedLiterals().map(\.key))
        let unused = Localization.simplifiedChinese.keys.filter { !used.contains($0) }.sorted()
        XCTAssertTrue(unused.isEmpty, "unused zh-Hans translations:\n\(unused.joined(separator: "\n"))")
    }

    func testFormatting() {
        XCTAssertEqual(Localization.format("{0} of {1}", [3, "five"]), "3 of five")
        XCTAssertEqual(
            Localization.detect(environment: ["AGENT_TOUCHBAR_LANG": "zh"], preferred: ["en-US"]), .simplifiedChinese)
        XCTAssertEqual(Localization.detect(environment: [:], preferred: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(Localization.detect(environment: [:], preferred: ["en-US"]), .english)
    }

    // MARK: - Helpers

    private struct Literal {
        var file: String
        var key: String
    }

    private func localizedLiterals() throws -> [Literal] {
        // L(" not preceded by an identifier character, so URL(" or LABEL(" do not match
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])L\("((?:[^"\\]|\\.)*)""#)
        var result: [Literal] = []
        for folder in ["Sources", "probe"] {
            let base = root.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in files where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let ns = text as NSString
                for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let raw = ns.substring(with: match.range(at: 1))
                    result.append(Literal(file: url.lastPathComponent, key: unescape(raw)))
                }
            }
        }
        return result
    }

    private func unescape(_ literal: String) -> String {
        literal.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func placeholders(in text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"\{\d+\}"#)
        let ns = text as NSString
        return Set(
            regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        )
    }
}
