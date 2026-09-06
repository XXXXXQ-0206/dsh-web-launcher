#!/usr/bin/env pwsh
# Create a desktop shortcut "Dsh Web Launcher" pointing at the launcher exe,
# using the exe's embedded dark-gray dsh icon (double-click opens the launcher).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$exe = Join-Path $PSScriptRoot 'dist\DshWebLauncher.exe'
if (-not (Test-Path $exe)) { throw "Not found: $exe. Run build.ps1 first." }

$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'DeepSeek Harness.lnk'
$oldLnk = Join-Path $desktop 'Dsh Web Launcher.lnk'
if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force }

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = Split-Path $exe
$lnk.Description = 'DeepSeek Harness Web Launcher (system tray)'
# 图标优先用 dist 里的 dsh_app.ico（多尺寸大图，48px 确定变大）；缺失时退回 exe 内嵌图标
$ico = Join-Path (Split-Path $exe) 'dsh_app.ico'
if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" } else { $lnk.IconLocation = "$exe,0" }
$lnk.Save()

Write-Host "Created desktop shortcut: $lnkPath"
