$ErrorActionPreference = 'Continue'
$owners = Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
Write-Output ("owners: " + ($owners -join ', '))
foreach ($pid0 in $owners) {
    if (-not $pid0) { continue }
    $p = Get-Process -Id $pid0 -ErrorAction SilentlyContinue
    Write-Output ("killing PID " + $pid0 + " (" + $(if($p){$p.ProcessName}else{'gone'}) + ")")
    & taskkill /PID $pid0 /T /F
}
Start-Sleep -Seconds 1
Write-Output ("port3080 after: " + [bool](Get-NetTCPConnection -LocalPort 3080 -ErrorAction SilentlyContinue))
