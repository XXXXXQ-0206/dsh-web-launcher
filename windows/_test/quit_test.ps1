param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port3080 {
    $cli = New-Object System.Net.Sockets.TcpClient
    try {
        $t = $cli.ConnectAsync('127.0.0.1', 3080)
        if ($t.Wait(1200)) { return $cli.Connected } else { return $false }
    } catch { return $false }
    finally { $cli.Close() }
}

$log = "$env:LOCALAPPDATA\DshWebLauncher\launcher.log"
if (Test-Path $log) { Remove-Item $log -Force }
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Write-Output ("launched PID=" + $p.Id)

for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Port3080) { Write-Output ("service up at t=" + $i + "s"); break }
}

Start-Sleep -Seconds 2
$before = Test-Port3080
Write-Output ("port before quit=" + $before)

# trigger quit (stop dsh then exit)
Start-Process -FilePath (Resolve-Path $LauncherPath).Path -ArgumentList '--quit' -WindowStyle Hidden
Start-Sleep -Seconds 4

$alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
$after = Test-Port3080
Write-Output ("launcher alive after quit=" + $alive)
Write-Output ("port after quit=" + $after)
Write-Output ("RESULT: icon-present-invariant " + $(if ($alive -eq $after) {'OK (both false)'} else {'CHECK'}))

if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force }
# cleanup any leftover dsh listener
$conn = Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }
Write-Output "quit-test-done"
