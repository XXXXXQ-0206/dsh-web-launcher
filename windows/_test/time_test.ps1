param([string]$LauncherPath, [string]$DshCmd)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port3080 {
    $cli = New-Object System.Net.Sockets.TcpClient
    try {
        $t = $cli.ConnectAsync('127.0.0.1', 3080)
        if ($t.Wait(800)) { return $cli.Connected } else { return $false }
    } catch { return $false }
    finally { $cli.Close() }
}

function Cleanup {
    $conn = Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }
    Get-Process DshWebLauncher -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
}

# Part A: launcher self-check overhead (WPF startup + FindDsh), no dsh needed
$checkFile = "$env:LOCALAPPDATA\DshWebLauncher\check.txt"
if (Test-Path $checkFile) { Remove-Item $checkFile -Force }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath (Resolve-Path $LauncherPath).Path -ArgumentList '--check' -Wait -WindowStyle Hidden
$sw.Stop()
Write-Output ("A) launcher --check took " + $sw.ElapsedMilliseconds + " ms (includes WPF startup + FindDsh)")

# Part B: direct dsh web boot time
Cleanup
$out = "$env:TEMP\dsh_boot.txt"
Remove-Item $out -Force
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = '/c ""' + $DshCmd + '" web --no-open >> "' + $out + '" 2>&1"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WindowStyle = 'Hidden'
$psi.WorkingDirectory = $env:USERPROFILE
$proc = [System.Diagnostics.Process]::Start($psi)
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 120; $i++) {
    if (Test-Port3080) { break }
    Start-Sleep -Milliseconds 250
}
$sw2.Stop()
$directUp = Test-Port3080
Write-Output ("B) direct dsh web boot to 3080 up = " + $sw2.ElapsedMilliseconds + " ms (up=" + $directUp + ")")

# cleanup direct dsh
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
Cleanup
Write-Output "time-test-done"
