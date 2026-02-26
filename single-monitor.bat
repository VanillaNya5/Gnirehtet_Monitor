@echo off
chcp 65001 >nul
echo 启动 Gnirehtet 单窗口监视器...
echo 按 Ctrl+C 停止
echo.
powershell -ExecutionPolicy Bypass -File .\gnirehtet-single-window.ps1
pause