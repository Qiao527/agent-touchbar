// Simplified Chinese translations for Touch Bar widgets.
// Keys are the exact English strings passed to L(...).
extension Localization {
    static let widgetStrings: [String: String] = [
        // Widget.swift
        "{0} failed": "{0}失败",
        "Unknown widget {0}": "未知组件 {0}",

        // ActionWidgets.swift
        "Sure?": "确认？",
        "Command failed": "命令失败",
        "Command": "命令",
        "{0} done": "{0}完成",
        "\"{0}\" is not in the Keychain": "钥匙串里没有「{0}」",
        "Run atb set-secret {0} to save it": "运行 atb set-secret {0} 保存",
        "Clipboard is empty": "剪贴板还是空的",
        "Shortcut \"{0}\" not found": "找不到快捷指令「{0}」",
        "Create a shortcut in Shortcuts that toggles Do Not Disturb": "在快捷指令里新建一个切换勿扰模式的指令",
        "Output device": "输出设备",
        "Script error": "脚本出错",
        "Select some text first": "先选中一段文字",

        // SceneWidgets.swift: agents
        "No agents running": "没有运行中的 agent",
        "Waiting": "等你",
        "Done": "完成",
        "Idle": "空闲",

        // SceneWidgets.swift: pomodoro and reminders
        "🍅 Focus done, take a break": "🍅 专注结束，休息一下",
        "Break over": "休息结束",
        "Rounds today: {0}": "今天完成 {0} 轮",
        "Break": "休息",
        "One more": "再来一轮",
        "In 5 min": "5 分钟后",
        "Focus": "开始专注",
        "Stop": "结束",
        "💧 Time for some water": "💧 喝口水吧",
        "🧍 Time to stand up and move": "🧍 起来活动一下",

        // SceneWidgets.swift: meeting
        "Mute": "静音",
        "Camera": "摄像头",
        "Leave": "离开",
        "Join meeting": "加入会议",

        // SceneWidgets.swift: video
        "Skip intro": "跳过片头",
        "Speed": "倍速",
        "Speed {0}×": "倍速 {0}×",

        // SceneWidgets.swift: browser
        "Tabs": "标签页",
        "Summarize": "总结",
        "Translate": "翻译",
        "Can't read the page": "读不到网页内容",
        "Turn on \"Allow JavaScript from Apple Events\" in the browser menu": "在浏览器菜单里打开「允许 Apple 事件中的 JavaScript」",
        "Page summary": "网页总结",
        "Summarize the main points of this web page as a bulleted list of at most 8 items.":
            "用中文分点总结这个网页的主要内容，不超过 8 点。",

        // StatusWidgets.swift: clock cities
        "Beijing": "北京",
        "Hong Kong": "香港",
        "Tokyo": "东京",
        "Singapore": "新加坡",
        "San Francisco": "旧金山",
        "New York": "纽约",
        "London": "伦敦",
        "Paris": "巴黎",
        "Berlin": "柏林",
        "Sydney": "悉尼",

        // StatusWidgets.swift: stats, calendar, headphones
        "Mem {0}%": "内存 {0}%",
        "L{0}": "左{0}",
        "R{0}": "右{0}",
        "Case {0}": "盒{0}",
    ]
}
