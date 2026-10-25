import Foundation

/// Open-Meteo（免费，不需要 API key）的当前天气
public struct WeatherNow: Equatable, Sendable {
    public var temperature: Double
    public var code: Int

    public init(temperature: Double, code: Int) {
        self.temperature = temperature
        self.code = code
    }

    public static func url(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    public static func parse(_ data: Data) -> WeatherNow? {
        struct Response: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double
                var weather_code: Int
            }
            var current: Current
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return WeatherNow(temperature: response.current.temperature_2m, code: response.current.weather_code)
    }

    /// WMO 天气代码 → SF Symbols 图标和中文描述
    public var symbol: (name: String, label: String) {
        switch code {
        case 0: return ("sun.max.fill", "晴")
        case 1, 2: return ("cloud.sun.fill", "多云")
        case 3: return ("cloud.fill", "阴")
        case 45, 48: return ("cloud.fog.fill", "雾")
        case 51...57: return ("cloud.drizzle.fill", "毛毛雨")
        case 61...67, 80...82: return ("cloud.rain.fill", "雨")
        case 71...77, 85, 86: return ("cloud.snow.fill", "雪")
        case 95...99: return ("cloud.bolt.rain.fill", "雷雨")
        default: return ("thermometer.medium", "")
        }
    }

    public var text: String { "\(Int(temperature.rounded()))°" }
}

/// 从 `system_profiler SPBluetoothDataType -json` 的输出里找耳机电量。
/// 不同系统版本字段名略有差异，这里匹配所有名字里带 batteryLevel 的字段。
public struct BluetoothBattery: Equatable, Sendable {
    public var device: String
    public var levels: [String: Int]   // left / right / case / main → 百分比

    public init(device: String, levels: [String: Int]) {
        self.device = device
        self.levels = levels
    }

    public var lowest: Int? { levels.values.min() }

    public static func parse(_ data: Data) -> [BluetoothBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var result: [BluetoothBattery] = []
        collect(root, into: &result)
        return result
    }

    private static func collect(_ node: Any, into result: inout [BluetoothBattery]) {
        if let array = node as? [Any] {
            for item in array { collect(item, into: &result) }
        } else if let dict = node as? [String: Any] {
            for (key, value) in dict {
                // 设备一般表示为 { "AirPods Pro": { "device_batteryLevelLeft": "80%", ... } }
                if let fields = value as? [String: Any] {
                    let levels = batteryLevels(fields)
                    if !levels.isEmpty {
                        result.append(BluetoothBattery(device: key, levels: levels))
                        continue
                    }
                }
                collect(value, into: &result)
            }
        }
    }

    private static func batteryLevels(_ fields: [String: Any]) -> [String: Int] {
        var levels: [String: Int] = [:]
        for (key, value) in fields where key.lowercased().contains("batterylevel") {
            let text = "\(value)".replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            guard let percent = Int(text) else { continue }
            let lower = key.lowercased()
            let part = lower.contains("left") ? "left"
                : lower.contains("right") ? "right"
                : lower.contains("case") ? "case" : "main"
            levels[part] = percent
        }
        return levels
    }
}
