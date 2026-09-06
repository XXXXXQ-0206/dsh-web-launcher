param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'
$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Write-Output ("launched PID=" + $p.Id + " at " + (Get-Date -Format HH:mm:ss.fff))
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    $alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
    $port = (Test-NetConnection -ComputerName 127.0.0.1 -Port 3080 -InformationLevel Quiet -WarningAction SilentlyContinue)
    Write-Output ("t=" + $i + "s alive=" + $alive + " port3080=" + $port)
}
if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
Write-Output "monitor-done"
