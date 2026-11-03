@echo off
chcp 936 >nul
cd /d "%~dp0"
title Charles 汉化包 - 还原原版
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0还原原版.ps1" %*
if errorlevel 1 pause
