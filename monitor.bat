@echo off
REM Start Gnirehtet with auto-restart monitor (no log files)
start "Gnirehtet" powershell -NoLogo -NoExit -ExecutionPolicy Bypass -File "%~dp0\gnirehtet-monitor.ps1"
@echo Launched Gnirehtet auto-restart window.
exit