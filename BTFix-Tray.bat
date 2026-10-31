@echo off
setlocal
cd /d "%~dp0"

echo Starting BTFix Bluetooth Sentry in System Tray...
start "" powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0BTFix-Tray.ps1"
exit /b
