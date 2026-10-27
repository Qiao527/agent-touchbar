import Foundation

/// Minimal HTTP/1.1 parser for the local server. Uses explicit body framing; no transfer encoding, pipelining, or keep-alive.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]  // keys are lowercased
    public var body: Data

    public enum ParseResult: Equatable, Sendable {
        case complete(HTTPRequest)
        case needMore
        case invalid(String)
    }

    public static let maxSize = 1 << 20  // 1 MB

    public static func parse(_ data: Data) -> ParseResult {
        if data.count > maxSize { return .invalid("Request too large") }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return .needMore
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid("Headers are not UTF-8")
        }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3,
            isToken(String(requestLine[0])),
            requestLine[1].hasPrefix("/"),
            requestLine[1].utf8.allSatisfy({ $0 > 32 && $0 != 127 }),
            requestLine[2] == "HTTP/1.1" || requestLine[2] == "HTTP/1.0"
        else { return .invalid("Malformed request line") }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid("Malformed header") }
            let key = String(line[..<colon]).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard isToken(key), headers[key] == nil,
                value.utf8.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) })
            else { return .invalid("Invalid or duplicate header") }
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { return .invalid("Transfer-Encoding is unsupported") }
        let rawLength = headers["content-length"] ?? "0"
        guard !rawLength.isEmpty, rawLength.utf8.allSatisfy({ (48...57).contains($0) }),
            let length = Int(rawLength)
        else { return .invalid("Invalid Content-Length") }
        let bodyStart = headerEnd.upperBound
        guard length <= maxSize - data.distance(from: data.startIndex, to: bodyStart) else {
            return .invalid("Request too large")
        }
        let available = data.endIndex - bodyStart
        if available < length { return .needMore }
        guard available == length else { return .invalid("Unexpected data after request body") }
        let body = data[bodyStart..<(bodyStart + length)]

        return .complete(
            HTTPRequest(
                method: String(requestLine[0]).uppercased(),
                path: String(requestLine[1]),
                headers: headers,
                body: Data(body)))
    }

    private static func isToken(_ text: String) -> Bool {
        let punctuation = Set("!#$%&'*+-.^_`|~".utf8)
        return !text.isEmpty
            && text.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || punctuation.contains($0)
            }
    }

    public var bearerToken: String? {
        guard let value = headers["authorization"], value.lowercased().hasPrefix("bearer ") else { return nil }
        return String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data("{}".utf8)) {
        self.status = status
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: (try? JSONEncoder().encode(value)) ?? Data("{}".utf8))
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(["error": message], status: status)
    }

    public func serialized() -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 413: reason = "Payload Too Large"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
