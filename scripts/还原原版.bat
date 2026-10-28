@echo off
chcp 936 >nul
setlocal
echo ============================================
echo  Charles 5.2.2 - 还原原版
echo ============================================
echo.
set /p DIR=请输入 Charles 安装目录（含 lib，直接回车用脚本所在目录）: 
if "%DIR%"=="" set DIR=%~dp0..
if not exist "%DIR%\lib\charles.jar.orig" (
  echo [错误] 找不到备份 "%DIR%\lib\charles.jar.orig"
  echo        如从未安装过补丁，可忽略本脚本。
  pause
  exit /b 1
)
copy /y "%DIR%\lib\charles.jar.orig" "%DIR%\lib\charles.jar" >nul
echo [完成] 已还原为原版 jar，重新启动 Charles 即可。
pause
