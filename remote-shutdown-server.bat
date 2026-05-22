@echo off
setlocal EnableExtensions

REM ===============================================================
REM  remote-shutdown-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Remotely shutdown SERVER from client PC using Administrator
REM    credentials.
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
echo [1/3] Authenticating to %SERVER% ...
cmdkey /add:%SERVER% /user:%RUSER% /pass:"%RPASS%" >nul 2>&1
net use \\%SERVER%\IPC$ /user:%SERVER%\%RUSER% "%RPASS%" >nul 2>&1
if errorlevel 1 (
    net use \\%SERVER%\IPC$ /user:%RUSER% "%RPASS%" >nul 2>&1
    if errorlevel 1 (
        echo       FAILED. Check server name, network, and credentials.
        pause
        exit /b 1
    )
)
echo       Connected.

REM --- 2. Send remote shutdown command ---------------------------
echo.
echo [2/3] Sending shutdown command to %SERVER% ...
echo       Server will shutdown in 10 seconds...
shutdown /m \\%SERVER% /s /f /t 10 /c "Remote shutdown initiated from client PC"
if errorlevel 1 (
    echo       shutdown command failed. Trying alternative...
    shutdown /m \\%SERVER% /s /f /t 0
    if errorlevel 1 (
        echo       [ERROR] Could not shutdown server. Check permissions.
        goto :done
    )
)
echo       SUCCESS: Shutdown command sent to %SERVER%.

REM --- 3. Disconnect IPC$ session --------------------------------
:done
echo.
echo [3/3] Disconnecting IPC$ from %SERVER% ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
echo       Done.

echo.
echo ============================================================
echo  DONE.
echo   - Shutdown command sent to %SERVER%
echo   - Server will power off in ~10 seconds
echo   - Credentials kept for future use
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Server Shutdown Command Sent Successfully. Server is powering off.',0,'Message',64);close();"

endlocal
exit /b 0
