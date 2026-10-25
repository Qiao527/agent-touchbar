# agentTouchbar

把 MacBook Pro 的 Touch Bar 变成"灵动岛"：平时显示常用信息，有事时自动弹出（验证码、Claude Code / Codex 请求权限、会议快开始了），并且随场景切换（开会、写代码、看视频）。组件、布局、场景规则都在一个配置文件里，保存后立即生效。

支持带 Touch Bar 的 Apple Silicon MacBook Pro（M1 / M2 13 寸），macOS 14 及以上。

## 安装

**方法一：下载编译好的版本**

1. 打开 [Actions](https://github.com/Qiao527/agentTouchbar/actions)，点最新一次成功的构建，下载 `agentTouchbar` 压缩包并解压。
2. 这个版本没有经过苹果公证，先解除隔离再移到"应用程序"：
   ```bash
   xattr -dr com.apple.quarantine ~/Downloads/agentTouchbar.app
   mv ~/Downloads/agentTouchbar.app /Applications/
   open /Applications/agentTouchbar.app
   ```

**方法二：自己编译**（需要 Xcode 命令行工具：`xcode-select --install`）

```bash
git clone https://github.com/Qiao527/agentTouchbar.git
cd agentTouchbar
./scripts/install.sh
```

> 每次重新编译后，ad-hoc 签名会变，系统可能要求重新授予权限。想避免这个问题，见 `scripts/build-app.sh` 开头关于 `SIGN_IDENTITY` 的说明。

## 第一次使用

启动后菜单栏会出现图标，Touch Bar 会换成 agentTouchbar 的界面。点菜单栏图标可以：

- **复制 Claude Code / Codex 的 hooks 配置**，分别粘贴到 `~/.claude/settings.json` 和 `~/.codex/config.toml`。Codex 还需要在里面运行一次 `/hooks` 信任这些 hook。
- 按提示授予权限：

| 权限 | 用途 |
|---|---|
| 完全磁盘访问权限 | 读取"信息"里的验证码短信（iPhone 需要打开"短信转发"） |
| 辅助功能 | 粘贴验证码和常用文本、会议快捷键、读取选中文字 |
| 日历 | 显示下一个日程、会议提醒 |
| 自动化（首次使用时系统弹窗） | 控制 Spotify、浏览器视频、深色模式 |

- **发送测试提醒**，确认 Touch Bar 能正常显示。

## 配置

配置文件在 `~/.config/agentTouchbar/config.yaml`，第一次启动时自动生成，里面每一项都有中文注释。完整示例见 [config/config.example.yaml](config/config.example.yaml)。

配置文件有错误时，程序会继续使用上一份能用的配置，并在 Touch Bar 和菜单栏提示错误位置。

### 组件

| 类型 | 作用 |
|---|---|
| `esc` | Esc 键 |
| `clock` | 时间，可以同时显示多个时区 |
| `battery` | 电量 |
| `cpu` | CPU 和内存占用，点一下打开活动监视器 |
| `volume` / `brightness` | 音量滑块、亮度按钮 |
| `weather` | 天气（Open-Meteo，不需要 key） |
| `next_event` | 下一个日程和倒计时，有会议链接时点一下直接加入 |
| `now_playing` | Spotify：封面、歌名、切歌 |
| `agents` | Claude Code / Codex 会话状态，点一下跳回终端 |
| `git_branch` | 最近活动的 agent 所在项目的 git 分支 |
| `pomodoro` | 番茄钟，以及喝水、起身提醒 |
| `buttons` | 自定义按钮：运行命令、打开网址、运行快捷指令、发送快捷键、粘贴文字 |
| `snippets` | 常用文本，敏感内容可以存在钥匙串 |
| `clipboard` | 最近的剪贴板内容 |
| `system` | 深色模式、勿扰、截图、锁屏、切换音频输出 |
| `audio_output` | 切换扬声器、AirPods 等输出设备 |
| `ai` | 把选中的文字交给 AI 翻译、润色、解释 |
| `meeting` | 会议静音、摄像头、离开、计时 |
| `video` | 网页视频进度、快进、倍速、跳过片头 |
| `browser` | 浏览器标签页、网页总结、网页翻译 |
| `airpods` | 蓝牙耳机电量 |
| `script` | 运行你的脚本，把输出显示出来 |
| `text` | 固定文字 |

### 自定义脚本组件

脚本输出一行 JSON 或者普通文本即可：

```json
{ "text": "BTC 68,210", "icon": "sf:bitcoinsign.circle", "color": "orange", "progress": 0.4 }
```

支持的字段：`text`、`icon`（`sf:符号名` 或图片路径）、`image`、`color`、`progress`（0–1）、`tap`（点击时运行的命令）、`alert`（发起一条提醒）。

### 从你自己的脚本发提醒

```bash
atb notify --title "构建完成" --detail "耗时 3 分 12 秒" --icon sf:hammer --color green --ttl 20
```

## 浏览器设置

视频控制和网页总结需要浏览器允许 AppleScript 执行 JavaScript：

- **Chrome / Edge / Arc / Brave**：菜单"显示" →"开发者" → 勾选"允许 Apple 事件中的 JavaScript"
- **Safari**：设置 →"高级"→ 勾选"显示网页开发者功能"，然后菜单"开发"→ 勾选"允许 Apple 事件中的 JavaScript"

## AI

在配置的 `ai` 部分填写接口地址和模型。任何兼容 OpenAI 接口的服务都能用（OpenAI、DeepSeek、本地 Ollama 等）。API key 用下面的命令存进钥匙串：

```bash
atb set-key
```

## 目录结构

```
Sources/
├── AgentTouchbarCore/   核心逻辑（配置、场景、提醒、验证码提取、hook 解析），可以在 Linux 上测试
├── atb/                 命令行工具
└── AgentTouchbar/       菜单栏程序
    ├── App/             入口、总控、菜单
    ├── TouchBar/        私有 API、Touch Bar 渲染
    ├── Sources/         各个数据源
    ├── Widgets/         组件
    └── Support/         工具函数
probe/                   检测私有 API 和唤醒能力的探针
docs/DESIGN.md           设计文档
```

## 开发

```bash
swift test                  # 核心逻辑测试（macOS 或 Linux）
./scripts/build-app.sh      # 打包到 build/agentTouchbar.app
```

日志在 `~/.config/agentTouchbar/agentTouchbar.log`。
