@echo off
chcp 936 >nul
echo 正在关闭 Windows 系统代理 ...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
rundll32.exe user32.dll,UpdatePerUserSystemParameters
echo 完成：系统代理已关闭（Clash 等软件如需接管，请在其界面重新打开系统代理）。
timeout /t 3 >nul
