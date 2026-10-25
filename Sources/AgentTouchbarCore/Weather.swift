import Foundation

/// Current weather from Open-Meteo (free, no API key).
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

    /// WMO weather code → SF Symbol name and a localized label.
    public var symbol: (name: String, label: String) {
        switch code {
        case 0: return ("sun.max.fill", L("Clear"))
        case 1, 2: return ("cloud.sun.fill", L("Partly cloudy"))
        case 3: return ("cloud.fill", L("Overcast"))
        case 45, 48: return ("cloud.fog.fill", L("Fog"))
        case 51...57: return ("cloud.drizzle.fill", L("Drizzle"))
        case 61...67, 80...82: return ("cloud.rain.fill", L("Rain"))
        case 71...77, 85, 86: return ("cloud.snow.fill", L("Snow"))
        case 95...99: return ("cloud.bolt.rain.fill", L("Thunderstorm"))
        default: return ("thermometer.medium", "")
        }
    }

    public var text: String { "\(Int(temperature.rounded()))°" }
}

/// Headphone battery levels from `system_profiler SPBluetoothDataType -json`.
/// Field names vary across macOS versions, so any field containing batteryLevel is matched.
public struct BluetoothBattery: Equatable, Sendable {
    public var device: String
    public var levels: [String: Int]  // left / right / case / main → percent

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
                // Devices usually look like { "AirPods Pro": { "device_batteryLevelLeft": "80%", ... } }
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
            let part =
                lower.contains("left")
                ? "left"
                : lower.contains("right")
                    ? "right"
                    : lower.contains("case") ? "case" : "main"
            levels[part] = percent
        }
        return levels
    }
}
