param([string]$ExePath)
Add-Type -AssemblyName System.Drawing
$exe = (Resolve-Path $ExePath).Path
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
Write-Output ("exe associated icon: " + $icon.Width + "x" + $icon.Height)
$icon.Dispose()
$icon2 = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
$bmp = $icon2.ToBitmap()
Write-Output ("icon bitmap: " + $bmp.Width + "x" + $bmp.Height)
$bmp.Dispose(); $icon2.Dispose()
