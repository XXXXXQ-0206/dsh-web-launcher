# DeepSeek Harness Web Launcher (macOS / Windows)

一个极简的 macOS 启动器:点击图标打开 DeepSeek Harness Web 界面;服务未运行时自动拉起 `dsh web`;服务运行期间程序坞常驻、菜单栏显示鲸鱼图标;服务停止后自动退出;单实例防重复。

> 本仓库同时提供 **Windows 系统托盘版**,见 [`windows/`](./windows/)。两版核心逻辑一致:托盘图标存在 ⇔ dsh 在后台运行;右键菜单仅「打开 / 退出」。Windows 版采用 WPF + 原生 Win32 托盘(与 CquAutoLogin 同款深色菜单),详见 [`windows/README.md`](./windows/README.md)。

## 功能

- **自动启动**:未运行 dsh 时自动执行 `dsh web --no-open`,就绪后打开页面(解析启动时打印的 token 授权地址,浏览器无 cookie 也能登录)
- **常驻指示**:服务期间菜单栏显示鲸鱼托盘图标、程序坞显示运行状态;服务停止约 4 秒后应用自动退出,图标消失(图标存在 = dsh 运行中)
- **托盘菜单**:打开页面 / 退出(退出不影响 dsh 服务运行)
- **退出清理**:退出应用时自动关闭 Safari 中所有 dsh 标签页;若 Safari 只剩 dsh 标签,连 Safari 一起退出(首次需在系统弹窗中授权控制 Safari)
- **单实例**:flock 文件锁,重复启动只激活已有实例,不重复拉起 dsh
- **自检**:`DeepSeekHarnessApp --check` 打印 dsh 路径、服务状态、token(不启动 UI)

## 要求

- macOS 13+ (arm64)
- Xcode 命令行工具(swiftc)、sips、iconutil(系统自带)
- DeepSeek Harness 已安装(dsh 位于 PATH,或 npm/npx 缓存目录 `~/.npm/_npx/*/node_modules/.bin/dsh`)

## 构建与安装

```bash
./build.sh          # 构建到 dist/DeepSeek Harness.app
./build.sh install  # 构建并安装到 ~/Applications
```

## 使用

- 点击图标(启动台 / Dock)→ 打开页面;服务未运行则先自动启动
- 菜单栏鲸鱼 →「打开 DeepSeek Harness」「退出」
- 日志:`~/Library/Logs/dsh-web-launcher.log`
- 实例锁:`~/Library/Application Support/DeepSeek Harness/dsh-launcher.lock`

## 工作原理

启动(冷启动)链路:单实例检查 → 探测 `http://127.0.0.1:3080/`(HTTP 401 视为已运行)→ 未运行则后台拉起 `dsh web --no-open` → 每 2 秒轮询至就绪(上限 90 秒)→ 从日志解析 token 授权地址并打开浏览器。此后常驻监视:服务连续 2 次探测失败即自动退出;托盘/程序坞的再次点击只打开页面,不会重启服务。

## 图标

`assets/AppIcon.svg`、`assets/WhaleTemplate.svg` 基于 DeepSeek 官方 favicon(取自 `@deepseek-ai/dsh-web-frontend`)重绘,仅作为本启动器视觉标识,版权归 DeepSeek 所有。
