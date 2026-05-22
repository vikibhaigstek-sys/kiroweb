@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===============================================================
REM  clear-lan-access-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Remove SERVER credentials from Credential Manager BUT keep
REM    TERMSRV (RDP) credentials intact. Then restart Workstation
REM    service to flush all cached LAN/SMB sessions.
REM
REM  Result:
REM    - RDP (Remote Desktop) still works (TERMSRV creds kept)
REM    - LAN access blocked (no file sharing, no net use, no IPC$)
REM
REM  Run as: Administrator on CLIENT PC
REM ===============================================================

set "SERVER=SERVER"

title Clear LAN Access to %SERVER% (keep RDP)

echo.
echo ============================================================
echo   Clear LAN access to "%SERVER%" (keep RDP credentials)
echo ============================================================
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

REM --- 1. Disconnect all network connections to SERVER ------------
echo.
echo [1/3] Disconnecting all network shares to %SERVER% ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
net use \\%SERVER%\C$ /delete /y >nul 2>&1
net use \\%SERVER%\D$ /delete /y >nul 2>&1
net use \\%SERVER%\E$ /delete /y >nul 2>&1
net use * /delete /y >nul 2>&1
echo       Done.

REM --- 2. Remove LAN credentials BUT keep TERMSRV ----------------
echo.
echo [2/3] Removing LAN/SMB credentials (keeping RDP) ...

set "REMOVED=0"
for /f "tokens=*" %%a in ('cmdkey /list ^| findstr /i /c:"Target:"') do (
    set "LINE=%%a"
    set "TGT=!LINE:*Target: =!"
    set "TGT=!TGT: =!"

    REM Check if this target contains SERVER
    echo !TGT! | findstr /i "%SERVER%" >nul
    if !errorlevel! == 0 (
        REM Check if it's a TERMSRV entry (RDP) - SKIP these
        echo !TGT! | findstr /i "TERMSRV" >nul
        if !errorlevel! == 0 (
            echo       KEEPING: !TGT! (RDP credential)
        ) else (
            REM Not TERMSRV - DELETE it (LAN/SMB credential)
            cmdkey /delete:"!TGT!" >nul 2>&1
            echo       REMOVED: !TGT! (LAN credential)
            set /a REMOVED+=1
        )
    )
)

if "!REMOVED!"=="0" (
    echo       No LAN credentials found for %SERVER%.
) else (
    echo       Removed !REMOVED! LAN credential(s).
)

REM --- 3. Restart Workstation service (flush cached sessions) ----
echo.
echo [3/3] Restarting Workstation service (LanmanWorkstation) ...
net stop lanmanworkstation /y
timeout /t 3 /nobreak >nul
net start lanmanworkstation

net start "Computer Browser"                >nul 2>&1
net start "Netlogon"                        >nul 2>&1
net start "Distributed Link Tracking Client">nul 2>&1
net start "Background Intelligent Transfer Service" >nul 2>&1
net start "Offline Files"                   >nul 2>&1

echo.
echo ============================================================
echo  DONE.
echo.
echo   REMOVED:  LAN/SMB credentials for %SERVER%
echo   KEPT:     TERMSRV/%SERVER% (RDP credentials)
echo   FLUSHED:  Workstation service restarted
echo.
echo   Result:
echo     - Remote Desktop (RDP) = WORKS
echo     - File sharing / LAN   = BLOCKED
echo     - Net use / IPC$       = BLOCKED
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('LAN access cleared. No one can access SERVER via network.\n\nRDP (Remote Desktop) still works.',0,'Message',64);close();"

endlocal
exit /b 0
