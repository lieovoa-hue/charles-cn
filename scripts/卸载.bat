@echo off
chcp 936 >nul
cd /d "%~dp0"
title Charles ∫∫ªØ∞Ê - –∂‘ÿ / «Â¿Ì
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0–∂‘ÿ-Charles.ps1" %*
if errorlevel 1 pause
