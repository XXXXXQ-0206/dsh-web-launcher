$ErrorActionPreference = 'SilentlyContinue'
# 结束所有监听 3080 的进程树（可能有多个，如真实 dsh node 及子进程）
Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { taskkill /PID $_ /T /F 2>$null }
Get-Process DshWebLauncher -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
Start-Sleep -Milliseconds 500
Write-Output "cleanup done"
