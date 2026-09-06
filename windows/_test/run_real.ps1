param([string]$LauncherPath)
$ErrorActionPreference = 'SilentlyContinue'
$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Write-Output ("launched PID=" + $p.Id)
# 真实 dsh 启动可能较慢，轮询最多 40 秒
$up = $false
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 1
    if (Test-NetConnection -ComputerName 127.0.0.1 -Port 3080 -InformationLevel Quiet -WarningAction SilentlyContinue) { $up = $true; break }
}
$proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
Write-Output ("port3080 up=" + $up)
if ($proc) {
    Write-Output ("launcher alive=True MainWindowHandle=" + $proc.MainWindowHandle + " title='" + $proc.MainWindowTitle + "'")
} else { Write-Output "launcher alive=False" }
Write-Output "--- log (last 30 lines) ---"
if (Test-Path $log) { Get-Content $log -Tail 30 } else { Write-Output "(no log)" }
# 清理：杀掉启动器 + 占用 3080 的真实 dsh 进程
if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
Start-Sleep -Seconds 1
$conn = Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }
Write-Output "real-test-done"
