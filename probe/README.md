# 探针

在你的 Mac 上自动测试两件事：

1. 全局显示 Touch Bar 用的私有 API 在当前 macOS 上还能不能用
2. Touch Bar 闲置熄灭后，程序能不能把它重新点亮，用哪种方法

## 运行

只需要 Xcode 命令行工具（没装的话先运行 `xcode-select --install`）：

```bash
cd agentTouchbar/probe
./run.sh
```

全程大约 3 到 5 分钟。终端里会提示你做两件事：

- **第 2 步**：Touch Bar 上出现一行字和紫色的"点我"按钮时，点一下。
- **第 4 步**：提示"不要碰键盘和触控板"后，完全松手，等 Touch Bar 自己熄灭。程序会自动尝试把它点亮，再测它能亮多久。

结束后，报告保存在桌面的 `agentTouchbar-probe.txt`，把内容复制给 Kiro 即可。

## 会不会影响系统

- 不需要任何系统权限，不修改系统设置。
- 测试中 Touch Bar 会被关掉再打开一次。程序退出时会撤下测试内容，并把 Touch Bar 重新点亮。
- 如果 Touch Bar 之后显示不正常，在终端运行 `sudo pkill TouchBarServer; killall ControlStrip` 即可恢复。
