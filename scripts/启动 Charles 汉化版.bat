@echo off
chcp 936 >nul
cd /d "%~dp0"
setlocal

rem ===== 启动前：把 Windows 系统代理指向 Charles =====
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d 127.0.0.1:8888 /f >nul
rundll32.exe user32.dll,UpdatePerUserSystemParameters

rem ===== 启动 Charles（阻塞等待，直到窗口关闭）=====
start /wait "" "Charles.exe"

rem ===== Charles 退出后：自动关闭系统代理，恢复原来的上网方式 =====
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
rundll32.exe user32.dll,UpdatePerUserSystemParameters
endlocal
