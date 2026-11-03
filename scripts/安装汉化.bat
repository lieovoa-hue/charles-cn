@echo off
chcp 936 >nul
cd /d "%~dp0"
title Charles 5.2.2 中文语言包 - 安装
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0安装汉化-GUI.ps1" %*
if errorlevel 1 pause
