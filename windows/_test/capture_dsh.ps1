param([string]$DshCmd)
$ErrorActionPreference = 'SilentlyContinue'
$out = "$env:TEMP\dsh_capture.txt"
Remove-Item $out -Force
# 用与启动器一致的 cmd /c 重定向方式启动
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = '/c ""' + $DshCmd + '" web --no-open >> "' + $out + '" 2>&1"'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WindowStyle = 'Hidden'
$psi.WorkingDirectory = $env:USERPROFILE
$proc = [System.Diagnostics.Process]::Start($psi)
Write-Output ("started pid=" + $proc.Id + " waiting for service...")
$up = $false
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 1
    if (Test-NetConnection -ComputerName 127.0.0.1 -Port 3080 -InformationLevel Quiet -WarningAction SilentlyContinue) { $up = $true; break }
}
Write-Output ("port3080 up=" + $up)
Write-Output "--- captured stdout/stderr ---"
if (Test-Path $out) { Get-Content $out } else { Write-Output "(no file)" }
# 清理：杀掉占用 3080 的 dsh 进程
$conn = Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }
Write-Output "capture-done"
