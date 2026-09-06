@echo off
rem Fake dsh that holds port 3080 briefly, to exercise the auto-quit path.
echo http://127.0.0.1:3080/?token=SHORTTOKEN-- 
powershell -NoProfile -Command "$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,3080); $l.Start(); Start-Sleep -Seconds 10; $l.Stop()"
