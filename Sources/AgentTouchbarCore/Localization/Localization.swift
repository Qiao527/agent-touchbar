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
    /// Override with `AGENT_TOUCHBAR_LANG=en` or `AGENT_TOUCHBAR_LANG=zh`.
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
        if let forced = environment["AGENT_TOUCHBAR_LANG"]?.lowercased() {
            return forced.hasPrefix("zh") ? .simplifiedChinese : .english
        }
        return preferred.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
    }

    public static func translate(_ english: String) -> String {
        guard language == .simplifiedChinese else { return english }
        return simplifiedChinese[english] ?? english
    }

    /// Replaces `{0}`, `{1}`, ... with the given arguments.
    public static func format(_ template: String, _ arguments: [CustomStringConvertible]) -> String {
        var result = template
        for (index, argument) in arguments.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: argument.description)
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
