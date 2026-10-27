import Foundation

/// Minimal localization layer.
///
/// English strings are the keys. Chinese translations live in plain Swift
/// dictionaries in this folder, so they compile on Linux and can be checked by
/// unit tests. (The app bundle is assembled by hand, so `Bundle.module`
/// resources would need extra packaging for no real benefit.)
///
/// Placeholders are positional: `{0}`, `{1}`, ... Translations must use the
/// same set of placeholders; `LocalizationTests` enforces that.
public enum Localization {
    /// English by default. Set `AGENT_TOUCHBAR_LANG=zh` for Chinese or `auto` to follow the system.
    public static var language: Language = detect()

    public enum Language: Sendable {
        case english
        case simplifiedChinese
    }

    /// All Chinese tables merged. Each area of the code base owns one table.
    public static let simplifiedChinese: [String: String] = {
        var merged: [String: String] = [:]
        for table in [coreStrings, cliStrings, appStrings, widgetStrings] {
            merged.merge(table) { first, _ in first }
        }
        return merged
    }()

    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferred: [String] = Locale.preferredLanguages
    ) -> Language {
        let forced = environment["AGENT_TOUCHBAR_LANG"]?.lowercased() ?? "en"
        if forced == "auto" {
            return preferred.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
        }
        return forced.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    public static func translate(_ english: String) -> String {
        guard language == .simplifiedChinese else { return english }
        return simplifiedChinese[english] ?? english
    }

    /// Replaces `{0}`, `{1}`, ... with the given arguments.
    public static func format(_ template: String, _ arguments: [CustomStringConvertible]) -> String {
        // Substitute from the template only; argument text may itself contain placeholders.
        guard let regex = try? NSRegularExpression(pattern: #"\{(\d+)\}"#) else { return template }
        let source = template as NSString
        var result = template
        for match in regex.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let index = Int(source.substring(with: match.range(at: 1))),
                arguments.indices.contains(index), let range = Range(match.range, in: result)
            else { continue }
            result.replaceSubrange(range, with: arguments[index].description)
        }
        return result
    }
}

/// Localized string. Use a single-line string literal so the coverage test can find it:
///
///     L("Battery at {0}%", percent)
public func L(_ english: String, _ arguments: CustomStringConvertible...) -> String {
    Localization.format(Localization.translate(english), arguments)
}
