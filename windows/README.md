# DeepSeek Harness Web Launcher (Windows, 系统托盘版)

把 macOS 版 `dsh-web-launcher` 的核心逻辑移植到 Windows，并采用与 [CquAutoLogin](https://github.com/XXXXXQ-0206/CquAutoLogin) 相同技术栈：**WPF (net9.0-windows) + 原生 Win32 托盘菜单**。

> 用户给的 `XXXXXQ-0206/dsh-web-launcher` 是 macOS 版启动器的 fork；本目录为 Windows 等价实现。

## 核心行为（与 macOS 一致）

- **托盘图标存在 ⇔ dsh 在后台运行**：启动器只在 dsh 服务就绪后才创建托盘图标；服务停止后启动器自动退出，图标随之消失。
- **托盘鲸鱼为白色**（白色主体 + 细深色描边，深浅色任务栏都能看清）。
- **右键菜单只有两个按钮**：**打开 DeepSeek Harness** / **退出**（无状态项）。
- **打开页面**：服务未运行会自动拉起 `dsh web --no-open`，就绪后用浏览器打开（优先用日志里的 `?token=` 地址）。
- **退出**：**连同 dsh 一起停掉**（结束 dsh 进程树 + 停止 3080 监听），随后退出启动器。
- **单实例**：重复启动只会唤醒已有实例打开页面，不会重复拉起 dsh。
- **快速启动**：用 `GetExtendedTcpTable` 瞬时读 TCP 监听表探测端口，不发起连接、不挂起，启动器自身启动约 0.3s（`dsh web` 启动约需 6s）。

由此保证：**任何时刻，托盘图标存在 ⇔ dsh 在后台运行；图标消失 ⇔ dsh 已停止**。

## 技术栈 / 样式

- `net9.0-windows`，`UseWPF=true`，`WinExe`，无可见窗口（纯托盘）。
- 托盘用原生 Win32：`Shell_NotifyIcon` + 隐藏消息窗口 + `CreatePopupMenu`/`InsertMenuItem`/`TrackPopupMenuEx`。
- 右键菜单启用 **DWM 沉浸式深色模式**（`DWMWA_USE_IMMERSIVE_DARK_MODE` + `uxtheme` 的 `SetPreferredAppMode(AllowDark)` / `FlushMenuThemes`），与 CquAutoLogin 同款观感。
- 进程为 **PerMonitorV2 DPI 感知**（启动即设置），确保高 DPI 缩放下原生菜单文字清晰不发糊。
- 单实例：`Mutex` + `EventWaitHandle` 激活信号（与 CquAutoLogin 相同）。

## 构建

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
```

产物：`dist\DshWebLauncher.exe`。要求本机装有 **.NET 9 Windows Desktop Runtime**（本机已满足）。自检：`DshWebLauncher.exe --check` 会写 `%LOCALAPPDATA%\DshWebLauncher\check.txt`。

## 桌面快捷方式

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File create_shortcut.ps1
```

会在桌面创建 **「DeepSeek Harness」** 快捷方式，图标为**深灰圆角底 + 居中的大号白色鲸鱼**（鲸鱼约占图标 80% 宽），使用 `dist\dsh_app.ico` 的多尺寸大图，双击即打开启动器。

## 重新生成图标

```powershell
python assets\make_icons.py
```

产出 `whale_running.ico`（运行态白色鲸鱼）、`whale_stopped.ico`、`dsh_app.ico`（深灰圆角底 + 居中大号白色鲸鱼，供应用/快捷方式使用）。

## 要求 / 检测路径

DeepSeek Harness 的 `dsh` 命令位于以下任一位置即可（`FindDsh` 自动取最新）：

- Windows npx 缓存：`%LOCALAPPDATA%\npm-cache\_npx\*\node_modules\.bin\dsh.cmd`
- macOS/Linux npx 缓存：`%USERPROFILE%\.npm\_npx\*\node_modules\.bin\dsh.cmd`
- 全局 npm：`%APPDATA%\npm\dsh.cmd`、`%APPDATA%\npm\node_modules\.bin\dsh.cmd`
- Node 目录：`%ProgramFiles%\nodejs\dsh.cmd`
- PATH 中的 `dsh.cmd` / `dsh.exe` / `dsh.ps1`

日志：`%LOCALAPPDATA%\DshWebLauncher\launcher.log`。

> 部分 Windows 环境的 `dsh web` 不把 token 地址打印到重定向的 stdout，此时启动器回退到普通地址 `http://127.0.0.1:3080/`。

> 与 macOS 版差异：macOS 的「退出」保留 dsh 服务运行；本版为满足“图标一定 ⇔ dsh 在后台”，退出会一并停止 dsh。

## 文件

- `DshWebLauncher.csproj` / `App.xaml` / `App.xaml.cs` — 主程序
- `DshTrayIconService.cs` — 原生 Win32 托盘（含深色菜单）
- `build.ps1` / `create_shortcut.ps1` — 构建与桌面快捷方式
- `assets/` — 图标与生成脚本
- `_test/` — 本地验证用例（可删除）
