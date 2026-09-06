param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'
$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Write-Output ("launched PID=" + $p.Id)
Start-Sleep -Seconds 17
$proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
if ($proc) { Write-Output "STILL ALIVE (unexpected)" } else { Write-Output "EXITED on its own (expected)" }
Write-Output "--- log ---"
if (Test-Path $log) { Get-Content $log } else { Write-Output "(no log)" }
if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
Write-Output "cleanup-done"
