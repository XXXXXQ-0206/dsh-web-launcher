param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port3080 {
    $cli = New-Object System.Net.Sockets.TcpClient
    try {
        $t = $cli.ConnectAsync('127.0.0.1', 3080)
        if ($t.Wait(800)) { return $cli.Connected } else { return $false }
    } catch { return $false }
    finally { $cli.Close() }
}

$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
Start-Process -FilePath (Join-Path (Resolve-Path $BinPath).Path 'dsh.cmd') -WindowStyle Hidden
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Port3080) { break }
}
Write-Output ("listener up=" + (Test-Port3080))

$checkFile = "$env:LOCALAPPDATA\DshWebLauncher\check.txt"
if (Test-Path $checkFile) { Remove-Item $checkFile -Force }
$exe = (Resolve-Path $LauncherPath).Path
Start-Process -FilePath $exe -ArgumentList '--check' -Wait -WindowStyle Hidden
Write-Output "--- check.txt ---"
Get-Content $checkFile

$conn = Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }
Write-Output "up-probe-done"
