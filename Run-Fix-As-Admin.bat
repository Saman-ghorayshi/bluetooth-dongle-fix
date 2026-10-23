@echo off
setlocal
cd /d "%~dp0"

:: Test if running with Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges required. Prompting for elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   BTFix: Switching Bluetooth to USB Dongle
echo ========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BTFix.ps1" -Mode Fix
echo.
echo ========================================================
pause