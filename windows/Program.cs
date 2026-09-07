using System.Drawing;
using System.Runtime.InteropServices;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace DshWebLauncher;

internal static class Program
{
    private const string GuidUrl = "http://127.0.0.1:3080/";
    private const string Host = "127.0.0.1";
    private const int Port = 3080;
    private const int ProbeTimeoutMs = 2000;
    private const int BootTimeoutSec = 90;
    private const int MaxStartAttempts = 4;
    private const string MutexName = @"Local\DshWebLauncher.Singleton";
    private const string ActivateSignalName = @"Local\DshWebLauncher.Activate";
    private const string QuitSignalName = @"Local\DshWebLauncher.Quit";
    private static readonly Regex TokenRegex =
        new(@"http://" + Host + @":3080/\?token=[A-Za-z0-9_-]+", RegexOptions.Compiled);

    [STAThread]
    private static int Main(string[] args)
    {
        // 让原生菜单在高 DPI 缩放下清晰渲染（PerMonitorV2），避免位图拉伸发糊
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
        try { Application.SetHighDpiMode(HighDpiMode.PerMonitorV2); } catch { }

        bool check = args.Length > 0 && string.Equals(args[0], "--check", StringComparison.OrdinalIgnoreCase);
        bool quit = args.Any(a => string.Equals(a, "--quit", StringComparison.OrdinalIgnoreCase));

        if (check)
        {
            WriteCheck();
            return 0;
        }

        bool owned;
        using (var mutex = new Mutex(true, MutexName, out owned))
        {
            if (!owned)
            {
                try
                {
                    if (quit)
                        EventWaitHandle.OpenExisting(QuitSignalName).Set();
                    else
                        EventWaitHandle.OpenExisting(ActivateSignalName).Set();
                }
                catch
                {
                }
                return 0;
            }

            if (quit)
                return 0; // 没有在跑的主实例，无需退出

            Application.Run(new TrayApp());
        }
        return 0;
    }

    private static string LogPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                     "DshWebLauncher", "launcher.log");

    private static Icon LoadTrayIcon()
    {
        var asm = Assembly.GetExecutingAssembly();
        var name = asm.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("whale_running.ico", StringComparison.OrdinalIgnoreCase));
        if (name is not null)
        {
            using var s = asm.GetManifestResourceStream(name);
            if (s is not null)
                return new Icon(s, 32, 32);
        }
        return (Icon)SystemIcons.Application.Clone();
    }

    private static void OpenPage(bool startedByUs)
    {
        var url = GuidUrl;
        if (startedByUs)
        {
            var tok = TokenFromLog();
            if (tok is not null)
                url = tok;
        }
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
        }
    }

    private static bool IsServiceUp()
    {
        // 直接查 TCP 监听表：瞬时、不发起连接，因此 dsh 未运行也不会挂 2s。
        var listening = IsPortListening(Port);
        if (listening is not null)
            return listening.Value;

        // 仅当读取 TCP 表失败（API 不可用）时才回退到短超时连接
        var tcp = new TcpClient();
        try
        {
            var task = tcp.ConnectAsync(Host, Port);
            if (!task.Wait(300))
                return false;
            return tcp.Connected;
        }
        catch
        {
            return false;
        }
        finally
        {
            tcp.Close();
        }
    }

    private static bool? IsPortListening(int port)
    {
        const int AfInet = 2;
        const int TcpTableOwnerPidListener = 3;
        int size = 0;
        // 第一次调用用于取得所需缓冲区大小（会返回 ERROR_INSUFFICIENT_BUFFER）
        if (GetExtendedTcpTable(IntPtr.Zero, ref size, false, AfInet, TcpTableOwnerPidListener, 0) != 0 && size == 0)
            return null;

        var buffer = Marshal.AllocHGlobal(size);
        try
        {
            if (GetExtendedTcpTable(buffer, ref size, false, AfInet, TcpTableOwnerPidListener, 0) != 0)
                return null;

            var count = Marshal.ReadInt32(buffer);
            var baseAddr = buffer.ToInt64() + sizeof(uint);
            var rowSize = Marshal.SizeOf<MIB_TCPROW_OWNER_PID>();
            for (var i = 0; i < count; i++)
            {
                var row = Marshal.PtrToStructure<MIB_TCPROW_OWNER_PID>(new IntPtr(baseAddr + (long)i * rowSize));
                var low = row.dwLocalPort & 0xFFFF;
                var p = (int)(((low >> 8) & 0xFF) | ((low & 0xFF) << 8));
                if (p == port && row.dwState == 2) // MIB_TCP_STATE_LISTEN
                    return true;
            }
            return false;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MIB_TCPROW_OWNER_PID
    {
        public uint dwState;
        public uint dwLocalAddr;
        public uint dwLocalPort;
        public uint dwRemoteAddr;
        public uint dwRemotePort;
        public uint dwOwningPid;
    }

    [DllImport("iphlpapi.dll", SetLastError = true)]
    private static extern int GetExtendedTcpTable(IntPtr pTcpTable, ref int pdwSize, bool bOrder, int ulAf, int TableClass, int Reserved);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    private delegate bool EnumWindowsProc(nint hWnd, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(nint hWnd, uint msg, nint wParam, nint lParam);

    private const int WmClose = 0x0010;

    private static string? TokenFromLog()
    {
        if (!File.Exists(LogPath))
            return null;
        string txt;
        try
        {
            txt = File.ReadAllText(LogPath);
        }
        catch
        {
            return null;
        }
        var matches = TokenRegex.Matches(txt);
        return matches.Count > 0 ? matches[^1].Value : null;
    }

    private static string? FindDsh()
    {
        var found = new List<KeyValuePair<string, DateTime>>();
        var names = new[] { "dsh.cmd", "dsh.exe", "dsh.ps1", "dsh.bat", "dsh" };

        foreach (var npxRoot in new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "npm-cache", "_npx"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".npm", "_npx")
        })
        {
            if (!Directory.Exists(npxRoot))
                continue;
            foreach (var npx in Directory.GetDirectories(npxRoot))
                ScanBin(found, Path.Combine(npx, "node_modules", ".bin"), names);
        }

        var npmGlobal = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm");
        ScanBin(found, npmGlobal, names);
        ScanBin(found, Path.Combine(npmGlobal, "node_modules", ".bin"), names);

        foreach (var nodeHome in new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "nodejs")
        })
            ScanBin(found, nodeHome, names);

        var pathVar = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var dir in pathVar.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                ScanBin(found, dir.Trim(), names);
            }
            catch
            {
            }
        }

        return found.OrderByDescending(kv => kv.Value).Select(kv => kv.Key).FirstOrDefault();
    }

    private static void ScanBin(List<KeyValuePair<string, DateTime>> found, string dir, string[] names)
    {
        if (!Directory.Exists(dir))
            return;
        foreach (var n in names)
        {
            var p = Path.Combine(dir, n);
            if (File.Exists(p))
            {
                try
                {
                    found.Add(new KeyValuePair<string, DateTime>(p, File.GetLastWriteTimeUtc(p)));
                }
                catch
                {
                }
            }
        }
    }

    private static void WriteCheck()
    {
        try
        {
            var swForDsh = System.Diagnostics.Stopwatch.StartNew();
            var dsh = FindDsh();
            swForDsh.Stop();
            var swUp = System.Diagnostics.Stopwatch.StartNew();
            var up = IsServiceUp();
            swUp.Stop();
            var swTok = System.Diagnostics.Stopwatch.StartNew();
            var tok = TokenFromLog();
            swTok.Stop();
            var dir = Path.GetDirectoryName(LogPath) ?? string.Empty;
            Directory.CreateDirectory(dir);
            var text = "dsh: " + (dsh ?? "NOT FOUND") +
                       "\nservice: " + (up ? "up" : "down") +
                       "\ntoken in log: " + (tok ?? "none") +
                       "\nfindDsh: " + swForDsh.ElapsedMilliseconds + " ms" +
                       "\nisUp: " + swUp.ElapsedMilliseconds + " ms" +
                       "\ntoken: " + swTok.ElapsedMilliseconds + " ms";
            File.WriteAllText(Path.Combine(dir, "check.txt"), text, Encoding.UTF8);
        }
        catch
        {
        }
    }

    /// <summary>
    /// 关闭标题为 DeepSeek Harness 的浏览器窗口（对应 dsh 页面），与 macOS 版“退出清理”一致。
    /// 仅按窗口标题匹配，避免误关其他窗口。
    /// </summary>
    private static void CloseDshBrowserWindows()
    {
        try
        {
            EnumWindows((hWnd, _) =>
            {
                if (IsWindow(hWnd))
                {
                    var sb = new System.Text.StringBuilder(512);
                    GetWindowText(hWnd, sb, sb.Capacity);
                    if (sb.ToString().IndexOf("DeepSeek Harness", StringComparison.OrdinalIgnoreCase) >= 0)
                        PostMessage(hWnd, WmClose, nint.Zero, nint.Zero);
                }
                return true;
            }, nint.Zero);
        }
        catch
        {
        }
    }

    private sealed class TrayApp : ApplicationContext
    {
        private readonly DshTrayIconService? _tray;
        private readonly System.Windows.Forms.Timer _timer;
        private readonly CancellationTokenSource _cts = new();
        private EventWaitHandle? _activate;
        private EventWaitHandle? _quit;
    private bool _starting;
    private int _startAttempts;
    private bool _startedByUs;
        private bool _openedAfterStart;
        private bool _everUp;
        private DateTime _startedAt = DateTime.MinValue;
        private int _downTicks;
        private bool _forceShutdown;
        private System.Diagnostics.Process? _dshProcess;

        public TrayApp()
        {
            // 0) 单实例信号尽早建立，第二实例可立即唤醒/退出
            _activate = new EventWaitHandle(false, EventResetMode.AutoReset, ActivateSignalName);
            _quit = new EventWaitHandle(false, EventResetMode.AutoReset, QuitSignalName);

            // 1) 尽早拉起 dsh（若未运行）——启动耗时主要在这里，别让托盘初始化挡在前面
            bool needStart = !IsServiceUp();
            if (needStart)
                StartService();

            // 2) 构建托盘（消息窗口）
            _tray = new DshTrayIconService(LoadTrayIcon());
            _tray.OpenRequested += () => OpenPage(_startedByUs);
            _tray.ExitRequested += () => ExitLauncher(stopService: true);
            _tray.RestartRequested += RestartDsh;

            // 3) 监听来自第二实例的信号
            var th = new Thread(() => ListenForSignals()) { IsBackground = true, Name = "DshWebLauncher.SignalListener" };
            th.Start();

            // 4) 若启动前 dsh 就在运行，点亮图标并直接打开页面；否则等就绪后由 OnTick 处理
            if (!needStart)
            {
                _everUp = true;
                _tray.ShowIcon();
                OpenPage(_startedByUs);
            }

            // 5) 启动阶段用较快轮询，服务就绪即开页面；就绪后再用 2s 监测。
            _timer = new System.Windows.Forms.Timer { Interval = _starting ? 400 : 2000 };
            _timer.Tick += OnTick;
            _timer.Start();
        }

        private void ListenForSignals()
        {
            while (!_cts.IsCancellationRequested)
            {
                int idx;
                try
                {
                    idx = WaitHandle.WaitAny(new[] { _activate!, _quit! });
                }
                catch
                {
                    return;
                }
                if (idx == 0)
                    _tray?.PostActivate();
                else if (idx == 1)
                {
                    _tray?.PostQuit();
                    return;
                }
            }
        }

        private void OnTick(object? sender, EventArgs e)
        {
            var up = IsServiceUp();
            if (up)
            {
                _downTicks = 0;
                _everUp = true;
                _tray?.ShowIcon();
                if (_starting && !_openedAfterStart)
                {
                    _openedAfterStart = true;
                    OpenPage(_startedByUs);
                }
                _starting = false;
                _startedByUs = false;
                _timer.Interval = 2000;
            }
            else
            {
                if (_starting)
                {
                    _timer.Interval = 400;
                    // dsh 启动存在间歇性的 Node ESM/CJS 加载竞态（ERR_INTERNAL_ASSERTION，
                    // “Cannot require() ES Module ... not yet fully loaded”），进程会提前退出。
                    // 检测到启动中的 dsh 进程退出且端口未就绪时自动重启重试。
                    if (_dshProcess is { HasExited: true })
                    {
                        if (_startAttempts < MaxStartAttempts)
                        {
                            _startAttempts++;
                            _startedAt = DateTime.Now;
                            _openedAfterStart = false;
                            if (!StartDsh())
                            {
                                ShowFatal("未找到 dsh 命令。\n\n请先安装 DeepSeek Harness，或把 dsh 加入 PATH 后重试。");
                                ExitLauncher(stopService: false);
                            }
                            return;
                        }
                        ShowFatal($"DeepSeek Harness 启动失败（已重试 {_startAttempts} 次）。\n\n请查看日志：\n{LogPath}");
                        ExitLauncher(stopService: true);
                        return;
                    }
                    if ((DateTime.Now - _startedAt).TotalSeconds > BootTimeoutSec)
                    {
                        ShowFatal($"DeepSeek Harness 启动超时。\n\n请查看日志：\n{LogPath}");
                        ExitLauncher(stopService: true);
                    }
                }
                else if (_everUp)
                {
                    _downTicks++;
                    if (_downTicks >= 2)
                    {
                        _tray?.HideIcon();
                        ExitLauncher(stopService: false);
                    }
                }
            }
        }

        private void StartService()
        {
            if (_starting)
                return;
            _starting = true;
            _startAttempts = 0;
            _startedByUs = true;
            _startedAt = DateTime.Now;
            _openedAfterStart = false;

            if (!StartDsh())
            {
                _starting = false;
                _startedByUs = false;
                ShowFatal("未找到 dsh 命令。\n\n请先安装 DeepSeek Harness，或把 dsh 加入 PATH 后重试。");
                ExitLauncher(stopService: false);
            }
        }

        private bool StartDsh()
        {
            var dsh = FindDsh();
            if (dsh is null)
                return false;

            var dir = Path.GetDirectoryName(LogPath) ?? string.Empty;
            Directory.CreateDirectory(dir);
            try
            {
                File.AppendAllText(LogPath, "");
            }
            catch
            {
            }

            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c \"\"" + dsh + "\" web --no-open >> \"" + LogPath + "\" 2>&1\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
                WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            };
            try
            {
                _dshProcess = System.Diagnostics.Process.Start(psi);
                return true;
            }
            catch (Exception ex)
            {
                ShowFatal($"无法启动 DeepSeek Harness：{ex.Message}");
                return false;
            }
        }

        /// <summary>重启 dsh：关闭旧页面、停止服务、重新拉起，启动器保持运行。</summary>
        private void RestartDsh()
        {
            if (_forceShutdown)
                return;
            CloseDshBrowserWindows();   // 关闭旧的 dsh 浏览器窗口（重启后重新打开）
            StopDsh();                  // 杀掉当前 dsh 进程树
            _starting = false;
            _startedByUs = false;
            _openedAfterStart = false;
            _everUp = false;
            _startAttempts = 0;
            _downTicks = 0;
            _tray?.HideIcon();
            StartService();             // 重新拉起 dsh，就绪后由 OnTick 亮图标并打开页面
        }

        private void ExitLauncher(bool stopService)
        {
            if (_forceShutdown)
                return;
            _forceShutdown = true;
            // 退出清理：关闭 dsh 对应浏览器窗口（macOS 版“退出时关闭 dsh 标签”）
            CloseDshBrowserWindows();
            if (stopService)
                StopDsh();
            _tray?.HideIcon();
            _timer.Stop();
            ExitThread();
            Environment.Exit(0);
        }

        private void StopDsh()
        {
            if (_dshProcess is { HasExited: false })
                KillTree(_dshProcess.Id);
            var owner = FindTcpOwner(Port);
            if (owner > 0 && owner != Environment.ProcessId)
                KillTree(owner);
        }

        private static int FindTcpOwner(int port)
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo("netstat", "-ano")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
                    RedirectStandardOutput = true
                };
                using var p = System.Diagnostics.Process.Start(psi);
                if (p is null)
                    return 0;
                var output = p.StandardOutput.ReadToEnd();
                if (!p.WaitForExit(3000))
                {
                    try { p.Kill(); } catch { }
                }
                foreach (var line in output.Split('\n'))
                {
                    if (line.Contains(":" + port) && line.Contains("LISTENING"))
                    {
                        var parts = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length > 0 && int.TryParse(parts[^1], out var pid))
                            return pid;
                    }
                }
            }
            catch
            {
            }
            return 0;
        }

        private static void KillTree(int pid)
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo("taskkill", "/PID " + pid + " /T /F")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden
                };
                using var tk = System.Diagnostics.Process.Start(psi);
                tk?.WaitForExit(2000);
            }
            catch
            {
            }
        }

        private static void ShowFatal(string message)
        {
            try
            {
                MessageBox.Show(message, "DeepSeek Harness", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch
            {
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _cts.Cancel();
                _activate?.Set();
                _quit?.Set();
                _activate?.Dispose();
                _quit?.Dispose();
                _timer.Dispose();
                _tray?.Dispose();
                _cts.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
