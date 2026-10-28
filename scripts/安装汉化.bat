@echo off
chcp 936 >nul
setlocal enabledelayedexpansion
echo ============================================
echo  Charles 5.2.2 简体中文语言包 - 安装器
echo ============================================
echo.
set /p DIR=请输入 Charles 安装目录（该目录下应有 lib\charles.jar，直接回车用脚本所在目录）: 
if "%DIR%"=="" set DIR=%~dp0..
if not exist "%DIR%\lib\charles.jar" (
  echo.
  echo [错误] 未找到 "%DIR%\lib\charles.jar"
  echo        请确认输入的目录就是 Charles 安装根目录。
  pause
  exit /b 1
)
echo.
echo 正在备份原版 jar ...
if not exist "%DIR%\lib\charles.jar.orig" (
  copy /y "%DIR%\lib\charles.jar" "%DIR%\lib\charles.jar.orig" >nul
  echo   已备份到 lib\charles.jar.orig
) else (
  echo   已存在备份 lib\charles.jar.orig，跳过备份
)
echo 正在写入汉化版 jar ...
copy /y "%~dp0..\dist\charles-zh.jar" "%DIR%\lib\charles.jar" >nul
if errorlevel 1 (
  echo [错误] 写入失败，请确认 Charles 已完全退出。
  pause
  exit /b 1
)
echo.
echo [完成] 汉化与授权补丁已安装，重新启动 Charles 即生效。
echo        界面应为中文，帮助菜单显示“注册给 Charles CN”。
pause
