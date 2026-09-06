param([string]$LauncherPath)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Listen3080 {
    return [bool](Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue)
}

# Ensure clean port
Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { taskkill /PID $_ /T /F 2>$null }
Get-Process DshWebLauncher -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800

$exe = (Resolve-Path $LauncherPath).Path
$p = Start-Process -FilePath $exe -PassThru
Write-Output ("launched PID=" + $p.Id)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$up = $false
for ($i = 0; $i -lt 400; $i++) {
    if (Test-Listen3080) { $up = $true; break }
    Start-Sleep -Milliseconds 100
}
$sw.Stop()
Write-Output ("dsh ready (port listen) = " + $sw.Elapsed.TotalSeconds.ToString('0.00') + " s, up=" + $up)

# Cleanup: stop launcher and the real dsh node (taskkill tree)
if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { taskkill /PID $_ /T /F 2>$null }
Start-Sleep -Milliseconds 500
Write-Output "real-startup-time-done"
