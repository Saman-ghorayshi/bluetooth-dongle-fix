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
echo 2. Fix conflict: Switch to Superior Radio (Recommended)
echo 3. Rollback: Restore previously disabled radios
echo 4. Forget a device (e.g. Haylou / QCY / AirPods)
echo 5. Compare Radios (Superiority Benchmark & LMP Specs)
echo 6. Open Graphical Interface (GUI)
echo 7. Exit
echo.
set /p choice="Choose an option (1-7): "
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
if "%choice%"=="5" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BTFix.ps1" -Mode Compare
    goto done
)
if "%choice%"=="6" (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0BTFix-GUI.ps1"
    exit /b 0
)
if "%choice%"=="7" exit /b 0

:done
echo.
pause
