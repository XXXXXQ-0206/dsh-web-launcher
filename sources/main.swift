// DeepSeek Harness Web Launcher
// 单实例(flock 锁)常驻应用:服务未运行则拉起 dsh web,运行期间保持程序坞活跃
// 状态并显示菜单栏托盘图标;服务停止后自动退出。
import AppKit
import Foundation
import Darwin

let GUI_URL = "http://127.0.0.1:3080/"
let LOG_PATH = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/dsh-web-launcher.log")
let LOCK_PATH = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/DeepSeek Harness/dsh-launcher.lock")
let BOOT_TIMEOUT: TimeInterval = 90

// 退出时清理 Safari:dsh 标签全关;整窗仅有 dsh 标签则关窗;Safari 只剩 dsh 标签则退出 Safari
let SAFARI_SCRIPT = """
if application "Safari" is running then
	tell application "Safari"
		set dshPrefix to "http://127.0.0.1:3080"
		set dshOnlyWindows to {}
		repeat with w in windows
			set hasDsh to false
			set hasOther to false
			repeat with t in tabs of w
				if URL of t starts with dshPrefix then
					set hasDsh to true
				else
					set hasOther to true
				end if
			end repeat
			if hasDsh and not hasOther then
				set end of dshOnlyWindows to w
			else if hasDsh and hasOther then
				repeat
					set closedOne to false
					repeat with t in tabs of w
						if URL of t starts with dshPrefix then
							try
								close t
							end try
							set closedOne to true
							exit repeat
						end if
					end repeat
					if not closedOne then exit repeat
				end repeat
			end if
		end repeat
		if (count of dshOnlyWindows) > 0 then
			if (count of windows) = (count of dshOnlyWindows) then
				quit
			else
				repeat with w in dshOnlyWindows
					try
						close w
					end try
				end repeat
			end if
		end if
	end tell
end if
"""

func serviceUp() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    p.arguments = ["-sS", "-m", "2", "-o", "/dev/null", GUI_URL]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    } catch {
        return false
    }
}

func tokenURLFromLog() -> String? {
    guard let txt = try? String(contentsOfFile: LOG_PATH, encoding: .utf8) else { return nil }
    guard let r = txt.range(of: "http://127\\.0\\.0\\.1:3080/\\?token=[A-Za-z0-9_-]+", options: .regularExpression) else { return nil }
    return String(txt[r])
}

func findDsh() -> String? {
    let fm = FileManager.default
    // 1) npx 缓存目录:取最近使用的 checkout
    let npx = (NSHomeDirectory() as NSString).appendingPathComponent(".npm/_npx")
    if let dirs = try? fm.contentsOfDirectory(atPath: npx) {
        let candidates = dirs.compactMap { (d: String) -> (String, Date)? in
            let bin = URL(fileURLWithPath: npx).appendingPathComponent(d).appendingPathComponent("node_modules/.bin/dsh").path
            guard fm.isExecutableFile(atPath: bin) else { return nil }
            let mtime = (try? fm.attributesOfItem(atPath: bin)[.modificationDate] as? Date) ?? .distantPast
            return (bin, mtime)
        }
        if let best = candidates.sorted(by: { $0.1 > $1.1 }).first {
            return best.0
        }
    }
    // 2) PATH 常规位置
    for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
        let p = dir + "/dsh"
        if fm.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    var starting = false
    var startedAt = Date.distantPast
    var startedService = false
    var opened = false
    var downTicks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular) // 程序坞可见
        setupStatusItem()
        if serviceUp() {
            starting = false
            opened = true
            openGUI()
        } else {
            starting = true
            startedAt = Date()
            startedService = true
            startService()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            // 鲸鱼模板图(随菜单栏深浅色自动黑白反色);加载失败时退回系统符号
            var image: NSImage? = nil
            if let bundleURL = Bundle.main.url(forResource: "WhaleTemplate", withExtension: "png"),
               let whale = NSImage(contentsOf: bundleURL) {
                whale.isTemplate = true
                whale.size = NSSize(width: 20, height: 15)
                image = whale
            }
            if image == nil {
                for name in ["server.rack", "bolt.circle", "power"] {
                    image = NSImage(systemSymbolName: name, accessibilityDescription: "DeepSeek Harness")
                    if image != nil { break }
                }
            }
            btn.image = image
            btn.image?.isTemplate = true
            btn.toolTip = "DeepSeek Harness"
        }
        // 托盘仅两个动作:打开页面、退出。图标存在即表示 dsh 运行中。
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开 DeepSeek Harness", action: #selector(openAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc func openAction() { openGUI() }
    @objc func quitAction() { NSApp.terminate(nil) }

    func openGUI() {
        // 仅在本次启动服务后使用日志中新打印的 token 地址(浏览器无 cookie 也能登录)
        let target = (startedService && tokenURLFromLog() != nil) ? tokenURLFromLog()! : GUI_URL
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }

    func startService() {
        guard let dsh = findDsh() else {
            alert("无法启动 DeepSeek Harness", "未找到 dsh 命令,请在终端手动运行 dsh web。")
            NSApp.terminate(nil)
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (LOG_PATH as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: LOG_PATH, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "nohup \"\(dsh)\" web --no-open >>\"\(LOG_PATH)\" 2>&1 &"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        do {
            try p.run()
        } catch {
            alert("无法启动 DeepSeek Harness", error.localizedDescription)
            NSApp.terminate(nil)
        }
    }

    func tick() {
        let up = serviceUp()
        if up {
            downTicks = 0
            if starting && !opened {
                opened = true
                openGUI()
            }
            starting = false
        } else {
            if starting {
                if Date().timeIntervalSince(startedAt) > BOOT_TIMEOUT {
                    alert("DeepSeek Harness 启动超时", "看日志: \(LOG_PATH)")
                    NSApp.terminate(nil)
                }
            } else {
                downTicks += 1
                if downTicks >= 2 {
                    // 服务已结束:退出应用,程序坞/托盘图标随之消失
                    NSLog("dsh web service stopped; quitting launcher")
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func alert(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = .warning
        a.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openGUI() // 再次点击程序坞/启动台图标时打开页面
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeDshSafariTabs()
    }

    // 关闭 Safari 中所有 dsh 标签页;若 Safari 只有 dsh 标签则退出 Safari(最多等 10 秒)
    func closeDshSafariTabs() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", SAFARI_SCRIPT]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let deadline = Date().addingTimeInterval(10)
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning { p.terminate() }
            p.waitUntilExit()
        } catch {
            // 忽略:Safari 未运行或未授权时静默退出
        }
    }
}

// 命令行自检:查找 dsh、探测服务、解析授权地址(不启动 UI)
if CommandLine.arguments.contains("--check") {
    print("dsh: \(findDsh() ?? "NOT FOUND")")
    print("service: \(serviceUp() ? "up" : "down")")
    print("token in log: \(tokenURLFromLog() ?? "none")")
    exit(0)
}

// 单实例锁:已有实例运行则激活它,然后退出
let fm = FileManager.default
try? fm.createDirectory(atPath: (LOCK_PATH as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
let lockFD = open(LOCK_PATH, O_CREAT | O_RDWR, 0o644)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == Bundle.main.bundleIdentifier {
        app.activate()
    }
    exit(0)
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
