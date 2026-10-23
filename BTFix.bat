@echo off
setlocal
cd /d "%~dp0"

:: Test if running with Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges required for repairs. Prompting for elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title BTFix - Bluetooth Dongle Fix & Repair
echo ========================================================
echo   BTFix: Windows Bluetooth Dongle Conflict & Repair Tool
echo ========================================================
echo.
echo 1. Check status (Read-Only Diagnostics)
echo 2. Fix conflict: Switch to USB Dongle (Recommended)
echo 3. Rollback: Restore previously disabled radios
echo 4. Forget a device (e.g. Haylou / QCY / AirPods)
echo 5. Exit
echo.
set /p choice="Choose an option (1-5): "
if "%choice%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BTFix.ps1" -Mode Check
    goto done
)
if "%choice%"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BTFix.ps1" -Mode Fix
    goto done
)
if "%choice%"=="3" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BTFix.ps1" -Mode Rollback
    goto done
)
if "%choice%"=="4" (
    set /p devname="Enter device name to forget (e.g. Haylou): "
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BTFix.ps1" -Mode Forget -Device "%devname%"
    goto done
)
if "%choice%"=="5" exit /b 0

:done
echo.
pause