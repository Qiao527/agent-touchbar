# agentTouchbar

**把 MacBook Pro 的 Touch Bar 变成会看场合的"灵动岛"。** 平时安静地显示常用信息；有事时自动弹出（短信验证码、Claude Code 请求权限、会议 5 分钟后开始），点一下就能处理；还会随你正在做的事切换控件。

[English](README.md) | 简体中文

> 📹 演示动图待补充：项目还没有在真正的 Touch Bar 上运行过（见[当前状态](#当前状态)）。

## 功能

| | |
|---|---|
| **提醒**（有事才出现） | 验证码 · Claude Code / Codex 完成或等你回复 · 权限请求（允许 / 拒绝） · 会议即将开始 · 下载完成 · 电量低 · AirPods 电量低 · 番茄钟、喝水、起身提醒 |
| **场景**（自动切换） | 开会：静音、摄像头、离开、计时 · 写代码：agent 状态、git 分支、命令按钮 · 浏览器：视频进度、倍速、跳过片头、标签页、网页总结 · 听歌：Spotify 封面和控制 |
| **一按就完成** | 剪贴板历史 · 常用文本（敏感内容存钥匙串） · 切换音频输出 · 深色模式、勿扰、截图、锁屏 · AI 翻译、润色、解释选中文字 |
| **常驻信息** | 多时区时间 · 天气 · 电量 · CPU 和内存 · 下一个日程倒计时 |
| **可扩展** | 脚本组件（输出 JSON 的任意脚本） · `atb notify` · YAML 配置热更新 · 中英文界面 |

界面语言跟随系统，也可以用环境变量 `AGENT_TOUCHBAR_LANG=zh` 或 `en` 指定。

## 安装

需要带 Touch Bar 的 Apple 芯片 MacBook Pro（13 寸 M1 或 M2），macOS 14 及以上。

**从源码安装**（需要先运行 `xcode-select --install`）：

```bash
git clone https://github.com/Qiao527/agentTouchbar.git
cd agentTouchbar
./scripts/install.sh
```

**下载编译好的版本**：发布第一个版本后，可以在 [Releases](https://github.com/Qiao527/agentTouchbar/releases) 下载；在那之前，每次 CI 构建都会上传一个打包好的 app。这个版本没有经过苹果公证，打开前先解除隔离：

```bash
xattr -dr com.apple.quarantine agentTouchbar.app
mv agentTouchbar.app /Applications/ && open /Applications/agentTouchbar.app
```

### 第一次使用

1. 点菜单栏图标 →「发送测试提醒」，确认 Touch Bar 能正常显示。
2. 「复制 Claude Code 的 hooks 配置」，粘贴到 `~/.claude/settings.json`；Codex 同理，粘贴到 `~/.codex/config.toml`，然后在 Codex 里运行 `/hooks` 信任它们。
3. 按菜单提示授予权限：

| 权限 | 用途 |
|---|---|
| 完全磁盘访问权限 | 读取"信息"里的验证码（iPhone 需要打开"短信转发"） |
| 辅助功能 | 粘贴验证码和常用文本、会议快捷键、读取选中文字 |
| 日历 | 下一个日程、会议提醒 |
| 自动化 | Spotify、浏览器视频、深色模式（首次使用时系统弹窗） |

## 配置

所有配置都在 `~/.config/agentTouchbar/config.yaml`，第一次启动时自动生成，保存后立即生效。配置有错误时，程序继续使用上一份能用的配置，并提示出错位置。完整示例见 [config/config.example.yaml](config/config.example.yaml)。

默认配置里的场景名是英文（`Meeting`、`Coding` 等），可以改成任何你喜欢的名字。

### 浏览器设置

视频控制和网页总结需要浏览器允许 AppleScript 执行 JavaScript：

- **Chrome / Edge / Arc / Brave**：菜单"显示"→"开发者"→ 勾选"允许 Apple 事件中的 JavaScript"
- **Safari**：设置 →"高级"→ 勾选"显示网页开发者功能"，然后菜单"开发"→ 勾选"允许 Apple 事件中的 JavaScript"

### AI

在配置的 `ai` 部分填写接口地址和模型，任何兼容 OpenAI 接口的服务都能用（OpenAI、DeepSeek、本地 Ollama 等）。API key 用 `atb set-key` 存进钥匙串。

## 当前状态

| 部分 | 状态 |
|---|---|
| 核心逻辑、命令行 | 已实现，在 Linux 和 macOS 上有单元测试 |
| 菜单栏程序、全部组件 | 已实现，在 CI 的 macOS 26 上编译通过 |
| 在真实 Touch Bar 上的表现 | **尚未验证**，请先运行 `probe/run.sh` |
| 设置窗口 | 未开始，目前用配置文件 |

更多内容见英文 [README](README.md)、[设计文档](docs/DESIGN.md)、[安全说明](SECURITY.md)和[贡献指南](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE) © 2026 Qiao Long
