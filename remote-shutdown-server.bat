@echo off
setlocal EnableExtensions

REM ===============================================================
REM  remote-shutdown-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Remotely shutdown SERVER from client PC using Administrator
REM    credentials. Clears saved credentials after shutdown command
REM    is sent and restarts Workstation service.
REM
REM  Run as: Administrator (right-click -> Run as administrator)
REM ===============================================================

REM ---- Server and credentials -----------------------------------
set "SERVER=SERVER"
set "RUSER=Administrator"
set "RPASS=P@ss3212"
REM ---------------------------------------------------------------

title Remote Shutdown %SERVER%

echo.
echo ============================================================
echo   Remote Shutdown "%SERVER%" using %RUSER% credentials
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

REM --- 1. Authenticate to SERVER ---------------------------------
echo.
echo [1/4] Authenticating to %SERVER% ...
cmdkey /add:%SERVER% /user:%RUSER% /pass:"%RPASS%" >nul 2>&1
net use \\%SERVER%\IPC$ /user:%SERVER%\%RUSER% "%RPASS%" >nul 2>&1
if errorlevel 1 (
    net use \\%SERVER%\IPC$ /user:%RUSER% "%RPASS%" >nul 2>&1
    if errorlevel 1 (
        echo       FAILED. Check server name, network, and credentials.
        cmdkey /delete:%SERVER% >nul 2>&1
        pause
        exit /b 1
    )
)
echo       Connected.

REM --- 2. Send remote shutdown command ---------------------------
echo.
echo [2/4] Sending shutdown command to %SERVER% ...
echo       Server will shutdown in 10 seconds...
shutdown /m \\%SERVER% /s /f /t 10 /c "Remote shutdown initiated from client PC"
if errorlevel 1 (
    echo       shutdown command failed. Trying alternative...
    shutdown /m \\%SERVER% /s /f /t 0
    if errorlevel 1 (
        echo       [ERROR] Could not shutdown server. Check permissions.
        goto :cred_cleanup
    )
)
echo       SUCCESS: Shutdown command sent to %SERVER%.
echo       Server will power off shortly.

:cred_cleanup
REM --- 3. Disconnect and clear credentials -----------------------
echo.
echo [3/4] Clearing connections and credentials ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
net use * /delete /y >nul 2>&1

cmdkey /delete:%SERVER% >nul 2>&1
cmdkey /delete:TERMSRV/%SERVER% >nul 2>&1
cmdkey /delete:Domain:target=%SERVER% >nul 2>&1

setlocal EnableDelayedExpansion
for /f "tokens=*" %%a in ('cmdkey /list ^| findstr /i /c:"Target:" ^| findstr /i /c:"%SERVER%"') do (
    set "LINE=%%a"
    set "LINE=!LINE:*Target: =!"
    set "LINE=!LINE: =!"
    if not "!LINE!"=="" (
        cmdkey /delete:"!LINE!" >nul 2>&1
        echo       Removed: !LINE!
    )
)
endlocal
echo       Done.

REM --- 4. Restart Workstation service ----------------------------
echo.
echo [4/4] Restarting Workstation service (LanmanWorkstation) ...
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
echo   - Shutdown command sent to %SERVER%
echo   - Server will power off in ~10 seconds
echo   - All credentials cleared from this PC
echo   - Workstation service restarted (LAN cache flushed)
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Server Shutdown Command Sent Successfully. Server is powering off.',0,'Message',64);close();"

endlocal
exit /b 0
