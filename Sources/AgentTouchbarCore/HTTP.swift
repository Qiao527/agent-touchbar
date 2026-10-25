import Foundation

/// Minimal HTTP/1.1 parser for the local server. Requires Content-Length; no chunked encoding or keep-alive.
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
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid("Malformed request line") }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid("Invalid Content-Length") }
        let bodyStart = headerEnd.upperBound
        let available = data.endIndex - bodyStart
        if available < length { return .needMore }
        let body = data[bodyStart..<(bodyStart + length)]

        return .complete(
            HTTPRequest(
                method: String(requestLine[0]).uppercased(),
                path: String(requestLine[1]),
                headers: headers,
                body: Data(body)))
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
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
