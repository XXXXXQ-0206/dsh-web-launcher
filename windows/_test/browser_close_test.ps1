param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Listen3080 {
    return [bool](Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue)
}

# 1) dummy window titled "DeepSeek Harness" (exits when closed)
$dummy = Start-Process pwsh -ArgumentList '-NoProfile','-File',(Join-Path $PSScriptRoot 'dummy_window.ps1') -PassThru
Start-Sleep -Seconds 2
$dHandle = (Get-Process -Id $dummy.Id).MainWindowHandle
$dTitle = (Get-Process -Id $dummy.Id).MainWindowTitle
Write-Output ("dummy window handle=" + $dHandle + " title='" + $dTitle + "'")

# 2) start launcher with fake dsh so it is running (service up -> tray)
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Listen3080) { break }
}
Write-Output ("launcher alive=" + [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue) + " service=" + (Test-Listen3080))

# 3) send quit -> launcher should close the dsh browser window, stop dsh, exit
Start-Process -FilePath (Resolve-Path $LauncherPath).Path -ArgumentList '--quit' -WindowStyle Hidden
Start-Sleep -Seconds 4

$dummyAlive = [bool](Get-Process -Id $dummy.Id -ErrorAction SilentlyContinue)
$launcherAlive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
Write-Output ("dummy window process alive after quit=" + $dummyAlive + "  (expect False => was closed)")
Write-Output ("launcher alive after quit=" + $launcherAlive + "  (expect False)")

if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
if (Get-Process -Id $dummy.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $dummy.Id -Force }
Write-Output "browser-close-test-done"
