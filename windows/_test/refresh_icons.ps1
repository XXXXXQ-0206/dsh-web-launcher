$ErrorActionPreference = 'SilentlyContinue'
# 清掉图标缓存并刷新 Shell，让更新的 dsh_app.ico 立即可见
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force
# 先杀掉 Explorer 再启动，刷新桌面/任务栏图标缓存（几秒内恢复）
Stop-Process -Name explorer -Force
Start-Sleep -Milliseconds 800
Start-Process explorer
Write-Output "icon cache refreshed (explorer restarted)"
