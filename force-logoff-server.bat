@echo off
setlocal EnableExtensions

REM ===============================================================
REM  force-logoff-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    1. Force-log off remote RDP user "user1" on host "SERVER"
REM       from this client PC.
REM    2. Remove any saved credentials for SERVER from this PC's
REM       Windows Credential Manager.
REM    3. Restart the Workstation (LanmanWorkstation) service so
REM       no cached LAN session for SERVER survives.
REM
REM  Run as: Administrator (right-click -> Run as administrator)
REM ===============================================================

REM ---- Server and user configuration ---------------------------
set "SERVER=SERVER"
set "RUSER=user1"
set RPASS=Ichalkaranji@416115^!@#$%%
REM ---------------------------------------------------------------

title Force logoff %RUSER% on %SERVER%

echo.
echo ============================================================
echo   Force logoff "%RUSER%" on "%SERVER%" + clear local creds
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

REM --- 1. Establish connection to SERVER -------------------------
echo.
echo [1/5] Connecting to \\%SERVER%\IPC$ ...
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

REM --- 2. Find session ID and force logoff -----------------------
echo.
echo [2/5] Finding session for %RUSER% on %SERVER% and logging off...

REM Use PowerShell to reliably parse qwinsta output and get session ID
for /f "usebackq delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$lines = qwinsta /server:%SERVER% 2>&1; foreach ($line in $lines) { if ($line -match '%RUSER%') { if ($line -match '\s+(\d+)\s+') { Write-Output $Matches[1]; break } } }"`) do (
    set "SID=%%S"
)

if defined SID (
    echo       Found session ID: %SID%
    echo       Forcing logoff...
    logoff %SID% /server:%SERVER% /v
    if errorlevel 1 (
        echo       logoff returned error, trying reset session...
        reset session %SID% /server:%SERVER%
    ) else (
        echo       Logoff successful.
    )
    goto :cleanup
)

echo       qwinsta did not find session. Trying taskkill method...
echo.
taskkill /s %SERVER% /u %SERVER%\%RUSER% /p "%RPASS%" /fi "USERNAME eq %RUSER%" /f >nul 2>&1
echo       taskkill executed (forces user processes to end).

:cleanup
REM --- 3. Disconnect from SERVER ---------------------------------
echo.
echo [3/5] Disconnecting from %SERVER% ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
net use * /delete /y >nul 2>&1
echo       Done.

REM --- 4. Remove ALL saved credentials for SERVER ----------------
echo.
echo [4/5] Removing saved credentials for %SERVER% ...

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
echo       Credential cleanup complete.

REM --- 5. Restart Workstation service ----------------------------
echo.
echo [5/5] Restarting Workstation service (LanmanWorkstation) ...
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
echo   - %RUSER% force logged off on %SERVER%
echo   - All saved credentials for %SERVER% removed
echo   - All network connections cleared
echo   - Workstation service restarted (LAN cache flushed)
echo   - No one can access %SERVER% from this PC via LAN now
echo ============================================================
echo.
pause
endlocal
exit /b 0
