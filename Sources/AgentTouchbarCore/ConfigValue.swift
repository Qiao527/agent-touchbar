import Foundation

/// 配置文件里任意结构的值。组件的选项千差万别，统一用它表示，由各组件自己读取。
public enum ConfigValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([ConfigValue])
    case object([String: ConfigValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ConfigValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ConfigValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法识别的配置值")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var string: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    public var int: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    public var bool: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes", "on": return true
            case "false", "no", "off": return false
            default: return nil
            }
        default: return nil
        }
    }

    public var array: [ConfigValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: ConfigValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// 字符串或字符串数组都接受，方便配置里写 `app: com.foo` 或 `app: [com.foo, com.bar]`
    public var stringList: [String]? {
        if let array { return array.compactMap(\.string) }
        if let string { return [string] }
        return nil
    }
}

/// 组件选项的便捷读取
public struct Options: Equatable, Sendable {
    public var values: [String: ConfigValue]

    public init(_ values: [String: ConfigValue] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> ConfigValue? { values[key] }

    public func string(_ key: String, default value: String? = nil) -> String? { values[key]?.string ?? value }
    public func int(_ key: String, default value: Int) -> Int { values[key]?.int ?? value }
    public func double(_ key: String, default value: Double) -> Double { values[key]?.double ?? value }
    public func bool(_ key: String, default value: Bool) -> Bool { values[key]?.bool ?? value }
    public func strings(_ key: String) -> [String] { values[key]?.stringList ?? [] }
    public func objects(_ key: String) -> [Options] {
        (values[key]?.array ?? []).compactMap { $0.object.map(Options.init) }
    }
}
