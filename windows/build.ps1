#!/usr/bin/env pwsh
# Build the DeepSeek Harness Web Launcher (Windows, WPF + native Win32 tray like CquAutoLogin).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# Framework-dependent: requires the .NET 9 Windows Desktop Runtime (installed on this machine).
dotnet publish -c Release -f net9.0-windows -o $dist
if ($LASTEXITCODE -ne 0) { throw "publish failed: $LASTEXITCODE" }

# 把桌面图标 .ico 放到 dist，便于快捷方式直接引用大图
Copy-Item (Join-Path $PSScriptRoot 'assets\dsh_app.ico') (Join-Path $dist 'dsh_app.ico') -Force

$exe = Join-Path $dist 'DshWebLauncher.exe'
Write-Host "Built: $exe"

# Smoke check: --check does not start the UI.
$checkFile = Join-Path (Join-Path $env:LOCALAPPDATA 'DshWebLauncher') 'check.txt'
if (Test-Path $checkFile) { Remove-Item $checkFile -Force }
Start-Process -FilePath $exe -ArgumentList '--check' -Wait -WindowStyle Hidden
if (Test-Path $checkFile) {
    Write-Host "--- self check ---"
    Get-Content $checkFile
}
Write-Host "OK"
