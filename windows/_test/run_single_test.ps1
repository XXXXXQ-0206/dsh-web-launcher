param([string]$LauncherPath, [string]$BinPath)
$ErrorActionPreference = 'SilentlyContinue'
$env:PATH = (Resolve-Path $BinPath).Path + ';' + $env:PATH
$p1 = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Start-Sleep -Seconds 3
$p2 = Start-Process -FilePath (Resolve-Path $LauncherPath).Path -PassThru
Start-Sleep -Seconds 4
$a1 = [bool](Get-Process -Id $p1.Id -ErrorAction SilentlyContinue)
$a2 = [bool](Get-Process -Id $p2.Id -ErrorAction SilentlyContinue)
$count = @(Get-Process DshWebLauncher -ErrorAction SilentlyContinue).Count
Write-Output ("instance1 alive=" + $a1 + " instance2 alive=" + $a2 + " total launcher procs=" + $count)
Get-Process DshWebLauncher -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Output "single-test-done"
