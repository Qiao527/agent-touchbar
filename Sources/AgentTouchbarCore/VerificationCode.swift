import Foundation

/// A verification code extracted from a text message.
public struct VerificationCode: Equatable, Sendable {
    public var code: String
    /// Source, e.g. the 【Brand】 prefix of an SMS; falls back to the sender number.
    public var source: String?

    public init(code: String, source: String?) {
        self.code = code
        self.source = source
    }
}

public enum VerificationCodeExtractor {
    public static let defaultKeywords = [
        "验证码", "校验码", "动态码", "确认码", "安全码", "激活码", "认证码", "动态密码", "登录码", "取件码",
        "verification code", "security code", "passcode", "one-time", "otp", "code",
    ]

    /// When these precede a number, it is not a code (card number suffix, amount, ...).
    private static let excludedPrefixes = ["尾号", "末四位", "末4位", "ending in", "ending", "¥", "￥", "$", "金额"]
    /// When these follow a number, it is not a code.
    private static let excludedSuffixes = [
        "元", "分钟", "秒", "小时", "minutes", "minute", "mins", "min", "seconds", "hours", "%",
    ]

    public static func extract(
        from text: String, sender: String? = nil,
        extraKeywords: [String] = []
    ) -> VerificationCode? {
        let lower = text.lowercased()
        let keywords = (defaultKeywords + extraKeywords).map { $0.lowercased() }

        // Offsets of keywords in the text
        var keywordPositions: [Int] = []
        for keyword in keywords where !keyword.isEmpty {
            var searchStart = lower.startIndex
            while let range = lower.range(of: keyword, range: searchStart..<lower.endIndex) {
                keywordPositions.append(lower.distance(from: lower.startIndex, to: range.lowerBound))
                searchStart = range.upperBound
            }
        }
        guard !keywordPositions.isEmpty else { return nil }

        let candidates = findCandidates(in: text)
        guard !candidates.isEmpty else { return nil }

        // Pick the candidate closest to a keyword; purely numeric beats alphanumeric
        let best = candidates.min { a, b in
            let da = distance(a.offset, keywordPositions)
            let db = distance(b.offset, keywordPositions)
            if a.isNumeric != b.isNumeric { return a.isNumeric }
            return da < db
        }
        guard let best else { return nil }
        return VerificationCode(code: best.value, source: brand(in: text) ?? sender)
    }

    private struct Candidate {
        var value: String
        var offset: Int
        var isNumeric: Bool
    }

    private static func findCandidates(in text: String) -> [Candidate] {
        // Must not touch letters or digits on either side, so we never grab part of a longer number
        let pattern = #"(?<![A-Za-z0-9])[A-Za-z0-9]{4,8}(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var result: [Candidate] = []

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range)
            let hasDigit = value.contains { $0.isNumber }
            let hasLetter = value.contains { $0.isLetter }
            guard hasDigit else { continue }  // plain words don't count

            // Alphanumeric codes need single-case letters and at least 2 digits, so ordinary words are not taken as codes
            if hasLetter {
                let digits = value.filter(\.isNumber).count
                let letters = value.filter(\.isLetter)
                guard digits >= 2, letters == letters.uppercased() || letters == letters.lowercased() else { continue }
            }

            let before = ns.substring(to: match.range.location).lowercased()
            let afterStart = match.range.location + match.range.length
            let after = ns.substring(from: afterStart).lowercased()
                .trimmingCharacters(in: .whitespaces)
            let beforeTrimmed = before.trimmingCharacters(in: .whitespaces)
            if excludedPrefixes.contains(where: { beforeTrimmed.hasSuffix($0) }) { continue }
            if excludedSuffixes.contains(where: { after.hasPrefix($0) }) { continue }
            // Dates and times such as 2026-10-25 or 12:30
            if let last = beforeTrimmed.last, [":", "-", "/", "."].contains(last), !hasLetter,
                beforeTrimmed.dropLast().last?.isNumber == true
            {
                continue
            }
            if let first = after.first, [":", "/"].contains(first) { continue }

            result.append(Candidate(value: value, offset: match.range.location, isNumeric: !hasLetter))
        }
        return result
    }

    private static func distance(_ offset: Int, _ positions: [Int]) -> Int {
        positions.map { abs($0 - offset) }.min() ?? Int.max
    }

    /// The 【brand】 or [brand] tag in an SMS.
    static func brand(in text: String) -> String? {
        let pattern = #"[【\[]([^】\]]{1,20})[】\]]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
            match.numberOfRanges > 1
        else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}

/// Recent macOS versions of Messages store the body in `attributedBody` (NSArchiver typedstream format).
/// We only pull out the plain text instead of fully decoding it.
public enum AttributedBodyDecoder {
    public static func text(from data: Data) -> String? {
        let bytes = [UInt8](data)
        let marker = Array("NSString".utf8)
        guard let markerIndex = find(marker, in: bytes) else { return nil }

        // "NSString" is followed by 5 bytes of type info, then the length
        var index = markerIndex + marker.count + 5
        guard index < bytes.count else { return nil }

        var length: Int
        if bytes[index] == 0x81 {
            guard index + 2 < bytes.count else { return nil }
            length = Int(bytes[index + 1]) | (Int(bytes[index + 2]) << 8)
            index += 3
        } else if bytes[index] == 0x82 {
            guard index + 4 < bytes.count else { return nil }
            length =
                Int(bytes[index + 1]) | (Int(bytes[index + 2]) << 8)
                | (Int(bytes[index + 3]) << 16) | (Int(bytes[index + 4]) << 24)
            index += 5
        } else {
            length = Int(bytes[index])
            index += 1
        }
        guard length > 0, index + length <= bytes.count else { return nil }
        return String(bytes: bytes[index..<(index + length)], encoding: .utf8)
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
            if Array(haystack[start..<(start + needle.count)]) == needle { return start }
        }
        return nil
    }

    /// For tests: encodes text in the same format.
    public static func encodeForTesting(_ text: String) -> Data {
        var bytes: [UInt8] = Array("streamtyped".utf8) + [0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84]
        bytes += Array("NSAttributedString".utf8) + [0x00, 0x84, 0x84]
        bytes += Array("NSObject".utf8) + [0x00, 0x85, 0x92, 0x84, 0x84, 0x84]
        bytes += Array("NSString".utf8) + [0x01, 0x94, 0x84, 0x01, 0x2B]
        let utf8 = Array(text.utf8)
        if utf8.count < 0x80 {
            bytes.append(UInt8(utf8.count))
        } else {
            bytes += [0x81, UInt8(utf8.count & 0xFF), UInt8((utf8.count >> 8) & 0xFF)]
        }
        bytes += utf8 + [0x86, 0x84]
        return Data(bytes)
    }
}
