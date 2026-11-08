# agentTouchbar

[![CI](https://github.com/Qiao527/agent-touchbar/actions/workflows/build.yml/badge.svg)](https://github.com/Qiao527/agent-touchbar/actions/workflows/build.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/swift-6.3%2B-orange)
![Engine](https://img.shields.io/badge/renderer-Metal%2060%20FPS-purple)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**将 MacBook Pro 的 Touch Bar 打造为专为 AI Coding、全栈开发者与设计师量身定制的 60 FPS GPU 硬件平视显示器（HUD）。**

[English Documentation](README.md) | 简体中文文档

---

## ⚡️ 技术突破：为什么 agentTouchbar 如此不同？

过去十年来，开源 Touch Bar 工具（如 MTMR、Pock）普遍受困于低效的 CPU `drawRect:` 绘制，刷新率仅 20–30 FPS，发热严重、耗电大。

通过对 macOS 核心闭源服务 `TouchBarServer` 的深度逆向工程，**agentTouchbar 确立了下一代底层架构**：
- **60 FPS GPU 零拷贝渲染引擎**：基于 `CAMetalLayer` 与硬件像素格式 `.bgra8Unorm`，单帧 CPU 提交预算 **<3ms**，整机 CPU 占用 **<1%**，完全杜绝发热降频。
- **1004 pt 边缘至边缘全景接管**：逆向证实 `DFRPresentationMode: 3` 与 `DFRSystemModal` 放置层 1，零 Root、零 SIP 限制，一键铺满 1004 × 30 pt（2170 像素全宽）长画布，告别 Control Strip 割裂。
- **10 指硬件级原生多点触控**：直通 Mac 底层 SPI 数字化仪中断（`NSTouchTypeDirect`），支持亚像素级连续坐标追踪与无级推子。

---

## 🛠 专为开发者与设计师打造的生产力场景

### 🤖 AI Coding 智能体用户（Claude Code、Codex、Cursor、Aider）
- **免切屏物理一键审批**：当 Claude Code 或 Codex 在终端发起高危操作（如 `rm`、`git push`）时，Touch Bar 立即浮现紫色的一键放行按钮，手指轻碰键盘即可审批，无需切出当前网页或文档。
- **AI 思考脉冲仪 (`agent_pulse`)**：60 FPS 流体波形随推理状态跳动。待机呈深邃蓝呼吸光，活跃时涌动霓虹紫粉能量波。

### 💻 后端与全栈工程师
- **端口卫士与一键杀僵尸 (`port_guard`)**：实时监控开发常用端口（`:3000`、`:5173`、`:8080`、`:5432`）。不仅能一键在浏览器打开本地服务，更支持**一按强杀占用进程**，告别 `EADDRINUSE` 噩梦。
- **GPU 实时遥测折线 (`cpu_sparkline`)**：过去 30 秒 CPU 与内存连续流动波形图，60 FPS 平滑滚动，根据负载智能变色（青 ➔ 紫 ➔ 琥珀红）。
- **Git 分支与 CI 状态**：实时展示当前分支名、未提交变更数与流水线红绿灯。

### 🎨 设计师与前端工程师
- **屏幕像素吸色取色器 (`color_picker`)**：一键调出 macOS 原生高倍放大取色镜，在屏幕任意位置采样像素，自动转换并复制 Hex `#RRGGBB` 颜色码至剪贴板，Touch Bar 实时回显色块。
- **硬件级无级平滑推子 (`metal_volume` / `metal_slider`)**：零延迟连续滑动调节音量与亮度，指尖正下方绽放跟随光晕（Touch Halo）。

### 🚀 1004 pt 沉浸式全景控制台（Mission Control HUD）
轻触微件按钮、点击菜单栏、或在终端输入 `atb dashboard`，Touch Bar 瞬间展开为跨越 1004 pt 的平视显示器：
```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ [✕ 收起]  🤖 2 AGENTS  [ ~~~~ AI Pulse ~~~~ ]  CPU [~~] RAM [~~]  [ ─── Vol ──●─ ] [📊] │
└────────────────────────────────────────────────────────────────────────────────────────┘
```
内置 25 秒防呆静默自动收起机制，日常使用的 Control Strip 原样保留、零干扰。

---

## 功能矩阵

| 模块分类 | 核心亮点 |
|---|---|
| **GPU Metal 微件** | `agent_pulse`（AI 思考波形） · `cpu_sparkline`（动态折线图） · `metal_volume`（硬件级推子） · `hud`（全景控制台开关） |
| **开发者神器** | `port_guard`（端口监听与一键 Kill） · `color_picker`（屏幕放大取色与 Hex 自动复制） · `git_branch` · `snippets`（钥匙串常用文本） |
| **智能提醒** | 终端 AI 权限审批（允许 / 拒绝） · 短信 2FA 验证码一键填充 · 会议倒计时 · 下载完成 · 番茄钟与喝水提醒 |
| **情境场景** | 随前台应用自动切换：**Coding**（代码与端口） · **Design**（设计与取色） · **Meeting**（静音与摄像头） · **Browser** · **Night** |
| **自由扩展** | 脚本微件（输出 JSON 的任意脚本） · `atb notify` 命令行工具 · YAML 配置热更新 · 中英文全量双语支持 |

---

## 安装方法

系统要求：带物理 Touch Bar 的 Apple 芯片 MacBook Pro（13 寸 M1 / M2），macOS 14 及以上。

### 源码编译安装（推荐）
```bash
git clone https://github.com/Qiao527/agent-touchbar.git
cd agent-touchbar
./scripts/install.sh
```

### 预编译安装
从 [Releases](https://github.com/Qiao527/agent-touchbar/releases) 下载最新打包文件：
```bash
xattr -dr com.apple.quarantine agentTouchbar.app
mv agentTouchbar.app /Applications/ && open /Applications/agentTouchbar.app
```

---

## 配置示例

配置文件位于 `~/.config/agentTouchbar/config.yaml`（初次启动自动生成，修改保存即时生效）。完整参考见 [config/config.example.yaml](config/config.example.yaml)。

```yaml
touchbar:
  mode: full            # full 全宽模式 或 app_region

scenes:
  - name: Coding
    when:
      app: [Terminal, iTerm2, Code, Cursor, Xcode]
    island: [agent_pulse, port_guard, git_branch]
    right: [cpu_curve, hud_btn]

  - name: Design
    when:
      app: [Figma, Sketch, Adobe Photoshop 2024]
    island: [color_picker, hud_btn]
    right: [vol_slider]

widgets:
  - id: agent_pulse
    type: agent_pulse
    width: 120

  - id: cpu_curve
    type: cpu_sparkline
    width: 100

  - id: vol_slider
    type: metal_volume
    width: 120

  - id: port_guard
    type: port_guard
    ports: [3000, 5173, 8080, 5432]
```

---

## 开源协议

[MIT](LICENSE) © 2026 Qiao Long. 第三方依赖声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
