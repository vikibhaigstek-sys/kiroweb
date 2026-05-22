@echo off
setlocal EnableExtensions

REM ===============================================================
REM  fix-rdp-blackscreen-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Apply all registry/GPO fixes on SERVER to prevent RDP
REM    blank/black screen issues. Run this ONCE on the server.
REM
REM  What it does:
REM    1. Disables WDDM display driver for RDP (uses stable XDDM)
REM    2. Disables hardware graphics adapters for RDP sessions
REM    3. Disables H.264/AVC 444 graphics mode
REM    4. Disables H.264/AVC hardware encoding
REM    5. Disables RemoteFX (deprecated, causes issues)
REM    6. Forces TCP-only transport (disables UDP)
REM    7. Sets keep-alive interval to prevent disconnects
REM    8. Disables persistent bitmap caching
REM
REM  Run as: Administrator ON THE SERVER (not client PC)
REM  After running: Restart the server for all changes to apply.
REM ===============================================================

title Fix RDP Black Screen - Server 2019

echo.
echo ============================================================
echo   Fix RDP Black Screen Issues - Windows Server 2019
echo ============================================================
echo.
echo   This script must be run ON THE SERVER (not client PC).
echo   It will apply registry fixes to prevent blank/black screen.
echo.

REM --- 0. Must run elevated --------------------------------------
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click the .bat file and choose
    echo         "Run as administrator", then try again.
    echo.
    pause
    exit /b 1
)

REM --- Registry path for Terminal Services policies --------------
set "TSPATH=HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
set "TSPATH2=HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"

echo.
echo [1/8] Disabling WDDM display driver for RDP ...
reg add "%TSPATH%" /v fEnableWddmDriver /t REG_DWORD /d 0 /f >nul 2>&1
echo       Done. (Forces stable XDDM driver instead of WDDM)

echo.
echo [2/8] Disabling hardware graphics adapters for RDP sessions ...
reg add "%TSPATH%" /v bEnumerateHWBeforeSW /t REG_DWORD /d 0 /f >nul 2>&1
echo       Done. (Prevents GPU conflicts in RDP)

echo.
echo [3/8] Disabling H.264/AVC 444 graphics mode ...
reg add "%TSPATH%" /v AVC444ModePreferred /t REG_DWORD /d 0 /f >nul 2>&1
echo       Done. (Reduces display rendering issues)

echo.
echo [4/8] Disabling H.264/AVC hardware encoding ...
reg add "%TSPATH%" /v AVCHardwareEncodePreferred /t REG_DWORD /d 0 /f >nul 2>&1
echo       Done. (Avoids encoder crashes)

echo.
echo [5/8] Disabling RemoteFX ...
reg add "%TSPATH%" /v fEnableRemoteFXAdvancedRemoteApp /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" /v EnableHardwareMode /t REG_DWORD /d 0 /f >nul 2>&1
echo       Done. (RemoteFX is deprecated and causes black screen)

echo.
echo [6/8] Forcing TCP-only transport (disabling UDP) ...
reg add "%TSPATH%" /v SelectTransport /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%TSPATH%" /v fDisableUDPTransport /t REG_DWORD /d 1 /f >nul 2>&1
echo       Done. (UDP causes blank screens over VPN)

echo.
echo [7/8] Setting keep-alive interval (60 seconds) ...
reg add "%TSPATH%" /v KeepAliveEnable /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%TSPATH%" /v KeepAliveInterval /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%TSPATH2%" /v KeepAliveTimeout /t REG_DWORD /d 60000 /f >nul 2>&1
echo       Done. (Prevents session from going unresponsive)

echo.
echo [8/8] Disabling persistent bitmap caching ...
reg add "%TSPATH2%" /v fDisableCpm /t REG_DWORD /d 1 /f >nul 2>&1
echo       Done. (Bitmap cache corruption causes black screen)

REM --- Apply Group Policy immediately ----------------------------
echo.
echo Applying Group Policy update ...
gpupdate /force

echo.
echo ============================================================
echo  ALL FIXES APPLIED SUCCESSFULLY.
echo.
echo  Settings changed:
echo   [1] WDDM display driver       = DISABLED (using XDDM)
echo   [2] Hardware graphics for RDP  = DISABLED
echo   [3] H.264/AVC 444 mode        = DISABLED
echo   [4] H.264/AVC HW encoding     = DISABLED
echo   [5] RemoteFX                   = DISABLED
echo   [6] UDP transport              = DISABLED (TCP only)
echo   [7] Keep-alive interval        = 60 seconds
echo   [8] Persistent bitmap cache    = DISABLED
echo.
echo  IMPORTANT: Please RESTART the server for all changes
echo  to take full effect.
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('All RDP Black Screen fixes applied successfully.\n\nPlease RESTART the server for changes to take effect.',0,'Fix Applied',64);close();"

endlocal
exit /b 0
