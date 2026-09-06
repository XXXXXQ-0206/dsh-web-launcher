@echo off
rem Fake dsh for local verification only. Prints a token line then holds port 3080.
echo http://127.0.0.1:3080/?token=TESTTOKENAZ09REMOTEID--
powershell -NoProfile -Command "$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,3080); $l.Start(); Start-Sleep -Seconds 45; $l.Stop()"
