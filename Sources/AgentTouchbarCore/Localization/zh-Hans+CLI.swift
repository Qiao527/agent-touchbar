// Simplified Chinese translations for the atb command-line tool.
// Keys are the exact English strings passed to L(...).
extension Localization {
    static let cliStrings: [String: String] = [
        "Invalid value for {0}": "{0} 的值无效",
        // Usage
        "Usage:": "用法：",
        "Run as a Claude Code hook (reads JSON from stdin)": "作为 Claude Code 的 hook（从标准输入读取 JSON）",
        "Run as a Codex hook (reads JSON from stdin)": "作为 Codex 的 hook（从标准输入读取 JSON）",
        "Run as the legacy Codex notify command": "作为 Codex 旧版 notify 命令",
        "--title <title> [--detail <text>] [--icon sf:bell] [--color orange]":
            "--title 标题 [--detail 说明] [--icon sf:bell] [--color orange]",
        "[--ttl <seconds>] [--priority <number>] [--id <id>]": "[--ttl 秒] [--priority 数字] [--id 标识]",
        "Check whether the menu bar app is running": "检查菜单栏程序是否在运行",
        "Create the default config file ~/.config/agentTouchbar/config.yaml":
            "生成默认配置文件 ~/.config/agentTouchbar/config.yaml",
        "Print the hook config to paste into the agent's config file": "打印 hook 配置，复制到对应的配置文件里",
        "Store the AI API key in the Keychain": "把 AI 接口的 API key 存进钥匙串",
        "Store sensitive text (e.g. a card number) in the Keychain for the Snippets widget":
            "把一段敏感文本（如银行卡号）存进钥匙串，供“常用文本”组件使用",
        "Usage: atb hooks claude or atb hooks codex": "用法：atb hooks claude 或 atb hooks codex",
        "Usage: atb set-secret <name>": "用法：atb set-secret 名字",

        // notify / status
        "Unrecognized argument: {0}": "无法识别的参数：{0}",
        "Missing --title": "缺少 --title",
        "Send failed: agentTouchbar is not running, or the token is wrong": "发送失败：agentTouchbar 没有运行，或者 token 不对",
        "No token yet: start agentTouchbar first": "还没有 token：请先启动 agentTouchbar",
        "agentTouchbar is not responding (port {0})": "agentTouchbar 没有响应（端口 {0}）",
        "agentTouchbar is running (port {0})": "agentTouchbar 正在运行（端口 {0}）",
        "Unknown command: {0}": "未知命令：{0}",

        // init
        "Config file already exists: {0}": "配置文件已存在：{0}",
        "Wrote {0}": "已生成：{0}",
        "Write failed: {0}": "写入失败：{0}",

        // hooks
        "Merge the following into the \"hooks\" field of ~/.claude/settings.json:":
            "把下面的内容合并到 ~/.claude/settings.json 的 \"hooks\" 字段里：",
        "Add the following to ~/.codex/config.toml, then run /hooks in Codex to trust these hooks:":
            "把下面的内容加到 ~/.codex/config.toml，然后在 Codex 里运行 /hooks 信任这些 hook：",

        // Keychain
        "Saved to the Keychain (service {0}, account {1})": "已保存到钥匙串（服务名 {0}，账户 {1}）",
        "Could not run security: {0}": "无法运行 security：{0}",
        "The Keychain is only available on macOS": "钥匙串只在 macOS 上可用",
    ]
}
