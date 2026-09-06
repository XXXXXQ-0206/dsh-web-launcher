param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'
$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Start-Sleep -Seconds 4
$proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
if ($proc) {
    Write-Output ("alive=" + $true)
    Write-Output ("MainWindowHandle=" + $proc.MainWindowHandle + "  (0 => no taskbar window)")
    Write-Output ("MainWindowTitle='" + $proc.MainWindowTitle + "'")
} else { Write-Output "alive=False" }
$port = Test-NetConnection -ComputerName 127.0.0.1 -Port 3080 -InformationLevel Quiet -WarningAction SilentlyContinue
Write-Output ("port3080=" + $port)
Write-Output "--- log ---"
if (Test-Path $log) { Get-Content $log }
if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
Write-Output "final-done"
