@echo off
setlocal
cd /d "%~dp0"

:: Test if running with Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges recommended for hardware repair. Prompting for elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Starting Bluetooth Dongle Fix Graphical Interface...
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0BTFix-GUI.ps1"
exit /b
