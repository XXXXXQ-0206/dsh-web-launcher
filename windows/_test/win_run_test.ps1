param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port3080 {
    return [bool](Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue)
}

$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Write-Output ("launched PID=" + $p.Id)
$shown = $false
for ($i = 0; $i -lt 16; $i++) {
    Start-Sleep -Seconds 1
    $alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
    $port = Test-Port3080
    if (-not $shown -and $alive) {
        $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        Write-Output ("t=" + $i + "s alive=" + $alive + " port3080=" + $port +
            " MainWindowHandle=" + $proc.MainWindowHandle + " title='" + $proc.MainWindowTitle + "'")
        $shown = $true
    } else {
        Write-Output ("t=" + $i + "s alive=" + $alive + " port3080=" + $port)
    }
    if (-not $alive -and $i -gt 5) { break }
}
if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
Write-Output "win-test-done"
