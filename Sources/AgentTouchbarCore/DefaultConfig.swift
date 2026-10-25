// 首次启动时写到 ~/.config/agentTouchbar/config.yaml 的默认配置。
// config/config.example.yaml 与它保持一致（有单元测试检查）。
public enum DefaultConfig {
    public static let yaml = #"""
# agentTouchbar 配置文件
# 保存后立即生效，不用重启。改坏了也没关系：程序会继续用上一份能用的配置，并在菜单栏提示错误。
version: 1

theme:
  accent: "#7C5CFF"     # 主色，#RRGGBB 或 red / orange / green / blue / purple …
  font_size: 13
  density: comfortable  # compact（紧凑）/ comfortable（宽松）
  animations: true

touchbar:
  mode: full            # full：占满整条；app_region：只占左侧，右边保留系统的亮度、音量按钮
  wake_on_alert: true   # 有新提醒时，如果 Touch Bar 已熄灭，就把它点亮

# 三个区域默认显示的组件。可以写组件类型名，也可以写下面 widgets 里自定义的 id
layout:
  left: [esc]
  island: [next_event, now_playing, pomodoro]
  right: [weather, clock, battery, volume]

# 场景：从上到下匹配，第一个满足条件的生效。没写的区域沿用 layout。
# 条件：app（前台程序名或 bundle id）、mic_in_use、playing、time（"22:00-06:00"）、
#       weekdays（1=周一…7=周日）、on_battery、in_meeting；写了 match: any 表示满足任一即可
scenes:
  - name: 开会
    when:
      app: [腾讯会议, TencentMeeting, 飞书, Feishu, Lark, zoom.us, us.zoom.xos, Microsoft Teams]
      in_meeting: true
      match: any
    island: [meeting]
    right: [clock, volume]

  - name: 写代码
    when:
      app: [Terminal, 终端, iTerm2, Warp, Ghostty, Code, Visual Studio Code, Cursor, Xcode, Codex, Claude]
    island: [agents, git_branch, dev]

  - name: 浏览器
    when:
      app: [Google Chrome, Safari, Arc, Microsoft Edge]
    island: [video, browser, ai]

  - name: 夜间
    when:
      time: "23:00-06:00"
    hide: [weather]

# 提醒：priority 越大越靠前；ttl 秒后自动消失（不写表示一直显示）；sticky 表示必须手动处理
alerts:
  agent_permission:  { priority: 100, sticky: true }
  verification_code: { priority: 90, ttl: 120 }
  meeting_soon:      { priority: 80, ttl: 600 }
  agent_done:        { priority: 60, ttl: 30 }
  pomodoro:          { priority: 55, sticky: true }
  battery_low:       { priority: 50, ttl: 60 }
  reminder:          { priority: 40, ttl: 60 }
  download_done:     { priority: 30, ttl: 15 }

agents:
  permission_on_touchbar: true   # Claude Code / Codex 请求权限时，在 Touch Bar 上允许或拒绝
  permission_wait: 30            # 等你点击的秒数，超时后交回终端照常询问

verification_codes:
  enabled: true                  # 需要"完全磁盘访问权限"
  clear_clipboard_after: 120
  extra_keywords: []

clipboard:
  enabled: true
  max_items: 20
  show: 4

calendar:
  enabled: true                  # 需要日历权限
  lead_minutes: 5

downloads:
  enabled: true
  path: ~/Downloads

battery:
  low_threshold: 20

ai:
  base_url: https://api.openai.com/v1   # 任何兼容 OpenAI 接口的服务都可以，例如 DeepSeek、本地 Ollama
  model: gpt-4o-mini
  api_key_env: OPENAI_API_KEY           # 也可以运行 `atb set-key` 存进钥匙串
  prompts:
    - { title: 翻译, prompt: "把下面的文字翻译成中文；如果已经是中文，就翻译成英文。只输出译文。" }
    - { title: 润色, prompt: "润色下面的文字，保持原意和语言，只输出结果。" }
    - { title: 解释, prompt: "用简单的中文解释下面的内容，不超过 120 字。" }

server:
  port: 47800

# 自定义组件。id 用在 layout 和 scenes 里；type 是组件类型；其余是这个组件的选项
widgets:
  - id: clock
    type: clock
    zones: [Asia/Shanghai]       # 可以加 America/Los_Angeles 等，多个时区会轮流显示
    format: "HH:mm"

  - id: weather
    type: weather
    latitude: 31.23              # 默认上海，改成你所在城市
    longitude: 121.47

  - id: pomodoro
    type: pomodoro
    focus_minutes: 25
    rest_minutes: 5
    water_every: 60              # 每 60 分钟提醒喝水，0 表示关闭
    stand_every: 50              # 每 50 分钟提醒起身，0 表示关闭

  - id: dev
    type: buttons
    items:
      - { title: 测试, icon: "sf:checkmark.seal", run: "cd ~ && echo 改成你的测试命令" }
      - { title: 剪贴板, icon: "sf:doc.on.clipboard", widget: clipboard }
      - { title: 常用, icon: "sf:text.badge.star", widget: snippets }

  - id: snippets
    type: snippets
    items:
      - { title: 邮箱, text: "me@example.com" }
      - { title: 手机, text: "13800000000" }
      # 敏感内容存在钥匙串：运行 `atb set-secret 银行卡` 后这样写
      # - { title: 银行卡, keychain: 银行卡, masked: true }

  - id: system
    type: system
    items: [dark_mode, dnd, screenshot, lock, audio_output]
    dnd_shortcut: "专注模式开关"   # 在"快捷指令"里建一个切换勿扰模式的指令，填它的名字

  - id: meeting
    type: meeting
    # 各软件的快捷键，按你的设置修改。格式：cmd+shift+a
    keys:
      zoom.us:  { mute: "cmd+shift+a", camera: "cmd+shift+v", leave: "cmd+w" }
      腾讯会议: { mute: "cmd+shift+a", camera: "cmd+shift+v", leave: "cmd+w" }
      飞书:     { mute: "cmd+shift+d", camera: "cmd+shift+v", leave: "cmd+w" }

  - id: video
    type: video
    skip_seconds: 85             # "跳过片头"前进的秒数

  # 脚本组件示例：脚本输出一行 JSON 或普通文本
  # - id: btc
  #   type: script
  #   command: "~/bin/btc-price.sh"
  #   interval: 60
"""#
}
