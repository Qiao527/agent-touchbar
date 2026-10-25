// Simplified Chinese translations for AgentTouchbarCore (config errors, text helpers, default prompts).
// Keys are the exact English strings passed to L(...).
extension Localization {
    static let coreStrings: [String: String] = [
        // Agent hooks
        "Tool": "工具",
        "Waiting for approval": "等待确认",
        "Denied on the Touch Bar": "在 Touch Bar 上被拒绝",

        // Config
        "Widget is missing an id": "组件缺少 id",
        "Unrecognized config value": "无法识别的配置值",
        "Untitled scene": "未命名场景",

        // Text.countdown
        "now": "现在",
        "in {0} s": "{0} 秒后",
        "in {0} min": "{0} 分钟后",
        "in {0} h": "{0} 小时后",
        "in {0} h {1} min": "{0} 小时 {1} 分后",

        // Text.timeLeft
        "{0} s left": "剩 {0} 秒",
        "{0} min left": "剩 {0} 分钟",
        "{0} h left": "剩 {0} 小时",
        "{0} h {1} min left": "剩 {0} 小时 {1} 分",

        // Weather
        "Clear": "晴",
        "Partly cloudy": "多云",
        "Overcast": "阴",
        "Fog": "雾",
        "Drizzle": "毛毛雨",
        "Rain": "雨",
        "Snow": "雪",
        "Thunderstorm": "雷雨",
    ]
}
