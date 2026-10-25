# agentTouchbar 设计文档

> 状态：草案 v0.1（2026-10-25）
> 目标设备：MacBook Pro 13 寸 M1（带 Touch Bar），macOS 27

## 1. 目标

把 Touch Bar 改造成一个"灵动岛"：

- **平时**只显示少量安静的常驻信息。
- **有事时**自动弹出相关内容（验证码、AI agent 等你确认、会议快开始了），点一下就能处理。
- **处理完**自动收起。
- **随场景切换**：开会、看视频、听歌、写代码、浏览网页时显示不同的控件。
- **高度个性化**：组件、布局、场景规则、外观、自定义脚本全部可以配置。

### 不做的事

- 不上 Mac App Store（需要用私有 API 才能全局显示）。
- 不读取、不上传任何聊天内容。验证码只在本机解析，用完即丢。
- 不支持 Intel Mac 和没有 Touch Bar 的 Mac。

## 2. 屏幕布局

Touch Bar 分成三个区域：

```
┌──────┬─────────────────────────────────────────┬────────────────────────┐
│ esc  │                 中间：灵动岛               │      右侧：常驻信息        │
│      │  平时显示场景组件，有提醒时被提醒顶替       │  时间 / 电量 / CPU / 音量  │
└──────┴─────────────────────────────────────────┴────────────────────────┘
```

- **左侧**：固定 `esc`，可以再加一两个常用按钮。
- **中间（灵动岛）**：显示当前场景的组件。有提醒时，提醒从右往左滑入，覆盖场景组件；同时有多个提醒时按优先级排队，可以左右滑动查看。
- **右侧**：常驻信息，内容和顺序可配置。点一下可以展开成系统控制（音量、亮度滑块）。

## 3. 功能清单

难度：🟢 容易 · 🟡 中等 · 🔴 较难

### 3.1 有事才出现（提醒）

| 功能 | 数据来源 | Touch Bar 上的样子 | 交互 | 难度 |
|---|---|---|---|---|
| 验证码 | 监听"信息"的数据库 `~/Library/Messages/chat.db`，正则提取 4–8 位码 | `🔑 482913 · 招商银行` | 点一下粘贴到当前输入框，长按只复制 | 🟡 |
| Claude Code / Codex 状态 | 两者的 hooks 调用本地 `atb` 命令 | `🤖 Claude · 等待确认：rm -rf build` | 允许 / 拒绝 / 跳回终端 | 🟡 |
| 会议前提醒 | EventKit 读取日历，解析会议链接 | `📅 5 分钟后 · 周会` | 点一下打开会议链接 | 🟡 |
| 下载完成 | FSEvents 监听 `~/Downloads` | `⬇️ report.pdf 已下载` | 打开 / 在访达中显示 | 🟢 |
| 电量低 | IOKit 电源信息 | `🔋 18%` 闪烁 | 点一下开启低电量模式 | 🟢 |
| AirPods 电量低 | 读取蓝牙设备电量（方案待验证，见 §10） | `🎧 左 10%` | — | 🟡 |
| 番茄钟 / 喝水 / 起身 | 内部定时器 | `🍅 时间到` | 休息 / 再来一轮 / 推迟 | 🟢 |

### 3.2 随场景自动切换

| 场景 | 触发条件 | 显示内容 | 难度 |
|---|---|---|---|
| 开会 | 前台是腾讯会议、飞书、Zoom，或麦克风正在被占用 | 静音、摄像头、会议计时、离开会议 | 🔴 |
| 看视频 | 浏览器中有正在播放的 `<video>` | 进度条滑块、倍速、跳过片头 | 🔴 |
| 听歌 | Spotify 正在播放 | 专辑封面、滚动歌名、上一首、播放/暂停、下一首、音量 | 🟢 |
| 写代码 | 前台是终端或编辑器 | agent 状态、当前 git 分支、常用命令按钮 | 🟡 |
| 浏览网页 | 前台是 Chrome 或 Safari | 翻译页面、总结文章、标签页列表 | 🔴 |

### 3.3 一按就完成

| 功能 | 实现方式 | 难度 |
|---|---|---|
| 剪贴板历史（最近 3–5 条） | 轮询 `NSPasteboard.changeCount` | 🟢 |
| 常用文本（邮箱、手机号、地址、银行卡号） | 配置文件 + 钥匙串存敏感内容 | 🟢 |
| 切换音频输出 | CoreAudio 设置默认输出设备 | 🟢 |
| 勿扰模式 | 调用"快捷指令"（`shortcuts run`） | 🟢 |
| 深色模式 / 锁屏 / 截图 | AppleScript、`pmset`、`screencapture` | 🟢 |
| AI 翻译 / 润色 / 解释选中文字 | 辅助功能 API 取选中文字，调用 AI 接口，结果显示在悬浮面板 | 🟡 |

### 3.4 扫一眼的常驻信息

| 功能 | 数据来源 | 难度 |
|---|---|---|
| 下一个日程和倒计时 | EventKit | 🟢 |
| 天气 | [Open-Meteo](https://open-meteo.com/)（免费，不需要 API key） | 🟢 |
| 多个时区 | 系统时区数据 | 🟢 |
| CPU 和内存 | `host_statistics` | 🟢 |

## 4. 个性化

### 4.1 配置文件

位置：`~/.config/agentTouchbar/config.yaml`。保存后自动生效，不用重启。

```yaml
version: 1

theme:
  accent: "#7C5CFF"        # 主色
  font: system             # system / rounded / mono
  density: comfortable     # compact / comfortable
  animations: true

layout:
  left: [esc]
  island: [next_event, now_playing]   # 没有场景匹配时显示
  right: [clock, battery, cpu]

# 场景：从上到下匹配，第一个满足条件的生效
scenes:
  - name: meeting
    when:
      app: [com.tencent.meeting, us.zoom.xos]   # bundle id，见 §10 如何查询
      or_mic_in_use: true
    island: [meeting_controls]

  - name: coding
    when:
      app: [com.googlecode.iterm2, com.apple.Terminal, com.microsoft.VSCode]
    island: [agents, git_branch, dev_commands]

  - name: night
    when:
      time: "22:00-06:00"
    hide: [cpu]
    island: [bedtime]

# 提醒：优先级越高越靠前；ttl 秒后自动消失；sticky 表示必须手动处理
alerts:
  agent_permission: { priority: 100, sticky: true, sound: false }
  verification_code: { priority: 90, ttl: 120, tap: paste, long_press: copy }
  meeting_soon:      { priority: 80, lead_minutes: 5 }
  agent_done:        { priority: 60, ttl: 30 }
  battery_low:       { priority: 50, threshold: 20 }
  download_done:     { priority: 30, ttl: 15 }

widgets:
  - id: clock
    type: clock
    zones: [Asia/Shanghai, America/Los_Angeles]

  - id: dev_commands
    type: buttons
    items:
      - { title: "测试", icon: "sf:checkmark.seal", run: "cd ~/code/app && npm test" }
      - { title: "部署", icon: "sf:paperplane", run: "~/bin/deploy.sh", confirm: true }

  - id: snippets
    type: snippets
    items:
      - { title: "邮箱", text: "me@example.com" }
      - { title: "银行卡", keychain: "atb.card.cmb", mask: "**** 1234" }

  - id: btc
    type: script
    command: "~/bin/btc-price.sh"
    interval: 60
```

### 4.2 自定义脚本组件

任何脚本都能变成一个组件。agentTouchbar 按 `interval` 定时运行脚本，读取它输出的一行 JSON：

```json
{ "text": "BTC 68,210", "icon": "sf:bitcoinsign.circle", "color": "#F7931A" }
```

支持的字段：

| 字段 | 说明 |
|---|---|
| `text` | 显示的文字 |
| `icon` | `sf:名字`（SF Symbols）或图片文件路径 |
| `image` | 图片路径，显示为缩略图 |
| `color` | 文字或背景色 |
| `progress` | 0–1，显示为进度条 |
| `alert` | 一个对象，脚本可以借此主动发起提醒 |
| `tap` | 点击时运行的命令 |

输出普通文本（不是 JSON）时，直接当作 `text` 显示。

### 4.3 设置窗口

菜单栏图标 → 设置。窗口里有 Touch Bar 的等比预览，可以拖拽组件调整顺序，修改结果会写回 `config.yaml`。这部分放在最后一个阶段做，在此之前先用配置文件。

## 5. 架构

```
┌────────────────────────────── agentTouchbar.app（菜单栏程序） ──────────────────────────────┐
│                                                                                              │
│   数据源（Sources）            核心（Core）                     显示（TouchBar）                │
│   ┌────────────────┐        ┌──────────────────┐            ┌────────────────────┐          │
│   │ MessagesSource │──┐     │  EventBus        │            │ TouchBarHost       │          │
│   │ AgentServer    │──┤     │  AlertQueue      │──────────▶ │ （私有 API 全局显示） │          │
│   │ CalendarSource │──┼───▶ │  ContextEngine   │            │ ZoneRenderer       │          │
│   │ SpotifySource  │──┤     │  SceneMatcher    │            │ Widget 视图         │          │
│   │ SystemSource   │──┤     │  WidgetRegistry  │            └────────────────────┘          │
│   │ ScriptRunner   │──┘     │  ConfigStore     │                                            │
│   └────────────────┘        └──────────────────┘                                            │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
          ▲
          │  atb 命令行（Claude Code / Codex hooks、你自己的脚本都通过它发事件）
```

### 5.1 模块说明

- **ConfigStore**：读取 `config.yaml`，监听文件变化，热更新。
- **ContextEngine**：收集"当前状态"：前台程序、时间、是否在播放音乐、麦克风是否占用、电源状态。
- **SceneMatcher**：用当前状态匹配配置里的场景规则，决定中间区域显示哪些组件。
- **AlertQueue**：管理提醒的优先级、排队、自动过期。
- **WidgetRegistry**：所有组件的注册表。内置组件和脚本组件实现同一个协议。
- **TouchBarHost**：负责把组件画到 Touch Bar 上，处理动画和触摸。
- **AgentServer**：只监听 `127.0.0.1` 的本地 HTTP 服务，接收 `atb` 发来的事件。

### 5.2 组件协议（草案）

```swift
protocol Widget: AnyObject {
    var id: String { get }
    /// 组件希望占用的宽度（点）。nil 表示自适应。
    var preferredWidth: CGFloat? { get }
    /// 创建 Touch Bar 上的视图
    func makeView() -> NSView
    /// 配置变化或数据更新时调用
    func update(config: WidgetConfig, context: Context)
}
```

### 5.3 提醒模型

```swift
struct Alert: Identifiable {
    let id: String
    let kind: String          // "verification_code"、"agent_permission" ...
    let source: String        // "messages"、"claude"、"codex" ...
    var title: String
    var detail: String?
    var icon: Icon?
    var priority: Int
    var expiresAt: Date?      // nil 表示 sticky
    var actions: [AlertAction]
}
```

### 5.4 核心逻辑与 UI 分离

规则匹配、验证码提取、配置解析、提醒排队这些逻辑放在单独的 Swift Package `AgentTouchbarCore` 里，不依赖 AppKit。这样它们能在 Linux 上编译和测试，开发时不必每次都在 Mac 上验证。

## 6. 全局 Touch Bar 的实现

公开 API 只允许程序在自己处于前台时修改 Touch Bar。要在所有程序里都显示，需要调用私有框架 `DFRFoundation`：

- `NSTouchBar.presentSystemModalTouchBar(_:systemTrayItemIdentifier:)`：让我们的 Touch Bar 覆盖在系统 Touch Bar 之上。
- `DFRElementSetControlStripPresenceForIdentifier`：在系统 Control Strip 上放一个入口按钮。
- `DFRSystemModalShowsCloseBoxWhenFrontMost`：隐藏左侧的关闭按钮。

[MTMR](https://github.com/Toxblh/MTMR) 和 [Pock](https://github.com/pock/pock) 都是这样实现的，可以参考。

**已知情况（2026-10-25 调研）**：

- [StripGauge](https://github.com/CodeCampusCo/stripgauge) 在 **macOS 26.5.2 + M1 13 寸**上实测过 `DFRElementSetControlStripPresenceForIdentifier`、`addSystemTrayItem:` 和 `presentSystemModalTouchBar:systemTrayItemIdentifier:`，都可用。它的设计文档还提到，只占左侧区域的方式会保留系统的亮度和音量按钮，占满整条则需要自己重新实现这些按钮。
- BetterTouchTool 依赖同样的机制。它的作者在 macOS 27 第一个测试版上就说整体能正常工作，论坛上目前也没有 Touch Bar 失效的报告（[论坛帖](https://community.folivora.ai/t/macos-27-golden-gate/47224)）。
- 还没有找到在 macOS 27 正式版上直接验证这些调用的公开记录，所以用 `probe/` 里的探针在你的 Mac 上实测。

**布局决定**：先用占满整条的方式（`placement: 1`），右侧自己实现亮度、音量。如果探针显示整条方式不可用，就退回到只占左侧区域，右侧保留系统 Control Strip。

## 7. 各功能实现要点

### 7.1 验证码

- 新版 macOS 的短信正文经常不在 `text` 字段里，而是存在 `attributedBody`（序列化的 `NSAttributedString`）里，两个字段都要解析。
- 监听 `chat.db-wal` 文件变化，有变化时只查询比上次更新的消息（按 `ROWID`）。
- 提取规则：先找"验证码 / 校验码 / code / OTP"等关键词附近的 4–8 位数字或字母数字组合，再用发送方或短信中的【公司名】作为来源标签。规则可以在配置里扩展。
- 点击时：写入剪贴板 → 模拟 `⌘V` 粘贴 → 2 分钟后从剪贴板清除（如果剪贴板还是这个码）。
- 验证码不写日志，不进剪贴板历史。

### 7.2 Claude Code / Codex

提供一个命令行工具 `atb`，两边的 hooks 都调用它：

```bash
atb hook claude   # 从 stdin 读取 Claude Code 的 hook JSON
atb hook codex    # 从 stdin 读取 Codex 的 hook JSON
atb notify --title "构建完成" --icon sf:hammer --ttl 20   # 你自己的脚本也能用
```

使用的事件：

| 状态 | Claude Code | Codex |
|---|---|---|
| 正在运行 | `UserPromptSubmit`、`PreToolUse` | `UserPromptSubmit`、`PreToolUse` |
| 等你确认 | `PermissionRequest`、`Notification` | `PermissionRequest` |
| 本轮完成 | `Stop` | `Stop`（旧版本用 `notify`） |
| 会话结束 | `SessionEnd` | — |

**在 Touch Bar 上允许/拒绝**：两边的 `PermissionRequest` hook 都可以返回 allow/deny 决定。`atb hook` 收到请求后阻塞等待，Touch Bar 上显示"允许 / 拒绝 / 去终端处理"：

- 你点了允许或拒绝 → `atb` 输出对应的决定 JSON。
- 你点"去终端处理"或超时（默认 60 秒）→ `atb` 不做决定，交回终端正常询问。

**跳回终端**：hook 数据里有 `cwd` 和会话 ID。根据 `TERM_PROGRAM` 用 AppleScript 激活 iTerm2 或 Terminal 的对应窗口；Codex App、Claude Desktop 则直接激活应用。这一项尽力而为。

**git 分支**：从 hook 数据的 `cwd` 运行 `git branch --show-current`。

**本地服务安全**：
- 只监听 `127.0.0.1`。
- 首次启动生成随机 token，存在 `~/.config/agentTouchbar/token`（权限 600），每个请求必须携带。

### 7.3 Spotify

- 用 AppleScript 读取当前歌曲、歌手、播放状态和封面 URL（`artwork url of current track`），控制播放和音量。
- 需要"自动化"权限（首次使用时系统会弹窗）。
- 系统的 MediaRemote 私有框架从 macOS 15.4 开始限制第三方调用，所以不依赖它，按程序单独对接。
- 收藏歌曲需要 Spotify Web API 和 OAuth 登录，放到后面。

### 7.4 日历和会议

- EventKit 读取所有日历（需要日历权限）。
- 从地点、备注、URL 字段中识别会议链接：`meeting.tencent.com`、`vc.feishu.cn`、`zoom.us`、`meet.google.com`、`teams.microsoft.com`。
- **会议控制**：腾讯会议和飞书没有公开接口，只能模拟它们的快捷键（需要辅助功能权限）。每个软件的快捷键写在配置里，你可以自己改。
- **会议计时**：从进入会议场景开始计时。

### 7.5 浏览器和视频

Chrome 和 Safari 都能通过 AppleScript 执行网页里的 JavaScript（需要在浏览器里打开"允许 Apple 事件中的 JavaScript"）。这样不用写浏览器扩展也能：

- 读取标签页列表，切换标签页。
- 控制页面上的 `<video>`：进度、倍速、前进指定秒数（"跳过片头"默认前进 85 秒，可配置）。
- 读取正文交给 AI 总结。翻译可以调用浏览器自带翻译，或者交给 AI。

如果 AppleScript 方案在某些网站不可用，再考虑写浏览器扩展。

### 7.6 AI 文字处理

- 通过辅助功能 API 读取选中文字（`AXSelectedText`），读不到时模拟 `⌘C`。
- 支持 OpenAI、Anthropic 和兼容 OpenAI 接口的本地模型，在配置里选择。API key 存在钥匙串。
- Touch Bar 太小，结果显示在光标附近的悬浮面板里，面板上有"替换原文 / 复制 / 关闭"。
- 提示词可配置，你可以加自己的按钮，比如"改成英文邮件"。

### 7.7 系统功能

| 功能 | 方式 |
|---|---|
| 勿扰模式 | 运行你在"快捷指令"里建好的指令（`shortcuts run "专注模式开关"`）。"快捷指令"组件可以运行任意指令，这也是个性化的一个入口 |
| 深色模式 | `osascript` 调用 System Events |
| 锁屏 | `pmset displaysleepnow` |
| 截图 | `screencapture -i -c` |
| 音频输出 | CoreAudio `kAudioHardwarePropertyDefaultOutputDevice` |
| 电量 | IOKit `IOPSCopyPowerSourcesInfo` |
| CPU/内存 | `host_statistics64` |
| 下载完成 | FSEvents 监听 `~/Downloads`，忽略 `.crdownload`、`.download` 等临时文件 |

### 7.8 剪贴板

- 每 0.5 秒检查 `NSPasteboard.changeCount`。
- 跳过带有 `org.nspasteboard.ConcealedType` 或 `TransientType` 标记的内容（1Password 等密码管理器会打这个标记），也跳过验证码。
- 只保存在内存里，最多 20 条，退出即清空。可以在配置里改成持久化。

## 8. 需要的系统权限

| 权限 | 用途 | 何时申请 |
|---|---|---|
| 完全磁盘访问权限 | 读取"信息"数据库（验证码） | 开启验证码组件时 |
| 辅助功能 | 模拟粘贴、会议快捷键、读取选中文字 | 第一次用到时 |
| 自动化 | 控制 Spotify、浏览器、System Events | 系统自动弹窗 |
| 日历 | 读取日程 | 开启日程组件时 |

**注意**：这些权限和程序的签名绑定。ad-hoc 签名每次编译都会变，权限需要重新授权。用固定的签名证书（例如 Xcode 里 Apple ID 免费个人团队生成的 Apple Development 证书）可以避免这个问题。

## 9. 项目结构

改用 Swift Package Manager，不再使用 XcodeGen：不需要完整的 Xcode，只要命令行工具就能编译；GitHub Actions 也能直接在 macOS 上编译和打包。

```
agentTouchbar/
├── Package.swift
├── Sources/
│   ├── AgentTouchbarCore/      # 不依赖 AppKit 的核心逻辑（可在 Linux 上测试）
│   ├── atb/                    # atb 命令行工具
│   └── AgentTouchbar/          # 菜单栏程序（App、TouchBar、Sources、Widgets、Support）
├── Tests/AgentTouchbarCoreTests/
├── Resources/Info.plist
├── scripts/                    # build-app.sh 打包，install.sh 安装
├── probe/                      # 探针
├── config/config.example.yaml  # 和内置默认配置保持一致（有测试检查）
└── .github/workflows/build.yml # Linux 跑核心测试；macOS 26 编译、打包、上传 app
```

## 10. 待验证的问题

| 问题 | 为什么重要 | 怎么验证 |
|---|---|---|
| Touch Bar 闲置熄灭后，程序能否把它点亮 | 决定"有事才出现"是否有效 | 运行 `probe/run.sh`。已知线索见下方 |
| `DFRFoundation` 私有 API 在 macOS 27 上是否可用 | 决定能否全局显示 | 运行 `probe/run.sh`。已知情况见 §6 |
| AirPods 电量的读取方式 | 没有公开 API | 在你的 Mac 上试 `system_profiler SPBluetoothDataType` 和 `ioreg` |
| 腾讯会议、飞书的 bundle id 和快捷键 | 会议场景要用 | 运行 `osascript -e 'id of app "腾讯会议"'`，查看各软件的快捷键设置 |
| macOS 27 上 `chat.db` 的结构 | 验证码功能依赖它 | 第 2 阶段用真实数据测试 |

**唤醒的已知线索**：

- 系统负责闲置变暗的 `TouchBarServer` 用的是 `DFRBrightness.framework` 里的 `DFRBrightnessClient` 类，它有 `turnOn` 和 `turnOff` 方法。[TouchBarOff](https://github.com/gbili/touchbar-off) 在 **M1 13 寸 + macOS 15.5** 上用它关闭和点亮 Touch Bar，并用 `DFRGetStatus()` 判断亮暗（`0x4` 位为 1 表示熄灭）。
- 公开 API `IOPMAssertionDeclareUserActivity` 可以声明"用户有操作"，可能也会让 Touch Bar 重新亮起，但没有找到实测记录。
- 探针按"只更新内容 → 重新显示 → 声明用户操作 → 私有 API 点亮"的顺序逐个尝试，记录哪种有效，以及点亮后能亮多久。

**如果所有方法都不能唤醒**：提醒同时发到菜单栏图标（变色或显示数字）和系统通知，保证不会漏掉。

## 11. 开发进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **0. 技术验证** | `probe/` 探针 | 代码完成，CI 编译通过，**等待在真机上运行** |
| **1. 基础框架** | 菜单栏程序、三区布局、配置热更新、场景匹配、提醒队列、`atb` 和本地服务 | 完成 |
| **2. 第一批组件** | 验证码、Claude Code/Codex（含允许/拒绝）、Spotify、时间、电量、CPU | 完成 |
| **3. 第二批组件** | 日程和会议提醒、番茄钟和提醒、剪贴板、常用文本、音频切换、快捷指令、系统开关、脚本组件 | 完成 |
| **4. 第三批组件** | AI 文字处理、天气、AirPods、下载完成 | 完成 |
| **5. 难度较高的部分** | 会议控制、浏览器标签页、网页视频控制、网页总结 | 完成 |
| **6. 设置窗口** | 拖拽布局、主题编辑 | 未开始，目前用配置文件 |

"完成"指代码写完、在 macOS 26 上编译通过、核心逻辑有单元测试。所有涉及 Touch Bar 显示、系统权限和第三方程序的部分都还没有在真机上验证过。

## 12. 你需要准备

1. 安装 Xcode 命令行工具：`xcode-select --install`（自己编译时需要；用 CI 打包好的版本则不需要）。
2. 如果要用验证码功能：在 iPhone 上打开"设置 → 信息 → 短信转发"，勾选这台 Mac。
3. 想让系统权限在重新编译后不失效：在钥匙串里准备一个代码签名证书，编译时设置 `SIGN_IDENTITY`（见 `scripts/build-app.sh`）。
