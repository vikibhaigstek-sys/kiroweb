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
REM Password is set WITHOUT DelayedExpansion to avoid ! being stripped
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

REM --- 1. Authenticate to SERVER ---------------------------------
echo.
echo [1/5] Connecting to \\%SERVER%\IPC$ ...
net use \\%SERVER%\IPC$ /user:%SERVER%\%RUSER% "%RPASS%" >nul 2>&1
if errorlevel 1 (
    echo       FAILED - retrying with IP-style connect...
    net use \\%SERVER%\IPC$ "%RPASS%" /user:%RUSER% >nul 2>&1
    if errorlevel 1 (
        echo       FAILED. Check server name, network, and credentials.
        pause
        exit /b 1
    )
)
echo       Connected.

REM --- 2. Find session ID using PowerShell (reliable parsing) ----
echo.
echo [2/5] Looking up session ID for %RUSER% on %SERVER% ...

REM Use PowerShell to parse quser output reliably
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command ^
  "$output = quser /server:%SERVER% 2>&1; foreach ($line in $output) { if ($line -match '^\s*>?%RUSER%\s+') { if ($line -match '^\s*>?\w+\s+\w+\s+(\d+)\s+Active') { $Matches[1] } elseif ($line -match '^\s*>?\w+\s+(\d+)\s+Disc') { $Matches[1] } } }"`) do (
    set "SID=%%S"
)

if not defined SID (
    echo       No active/disconnected session found for %RUSER%.
    echo       Trying alternative method...
    REM Alternative: query session command
    for /f "tokens=3" %%I in ('query session %RUSER% /server:%SERVER% 2^>nul ^| findstr /i "%RUSER%"') do (
        set "SID=%%I"
    )
)

if not defined SID (
    echo       Still no session found. Attempting reset session...
    REM Last resort: try to reset all sessions for user
    for /f "tokens=2,3,4" %%A in ('query user /server:%SERVER% 2^>nul ^| findstr /i "%RUSER%"') do (
        echo %%A| findstr /r "^[0-9][0-9]*$" >nul
        if not errorlevel 1 (
            set "SID=%%A"
        ) else (
            echo %%B| findstr /r "^[0-9][0-9]*$" >nul
            if not errorlevel 1 (
                set "SID=%%B"
            ) else (
                set "SID=%%C"
            )
        )
    )
)

if not defined SID (
    echo       [WARNING] Could not find session ID for %RUSER%.
    echo       Skipping logoff step.
    goto :disconnect
)
echo       Session ID = %SID%

REM --- 3. Force the logoff ---------------------------------------
echo.
echo [3/5] Forcing logoff of session %SID% on %SERVER% ...
logoff %SID% /server:%SERVER% /v
if errorlevel 1 (
    echo       logoff command returned error - trying reset session...
    reset session %SID% /server:%SERVER% >nul 2>&1
    if errorlevel 1 (
        echo       reset session also failed.
    ) else (
        echo       Session reset successfully.
    )
) else (
    echo       Logoff issued successfully.
)

:disconnect
REM --- 4. Drop the SMB session to SERVER -------------------------
echo.
echo [4/5] Disconnecting \\%SERVER%\IPC$ ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
net use * /delete /y >nul 2>&1

REM --- 5. Remove saved creds for SERVER from Credential Manager --
echo.
echo [5/5] Removing saved credentials matching "%SERVER%" ...

REM Delete common credential target formats for RDP/SMB
cmdkey /delete:TERMSRV/%SERVER% >nul 2>&1
cmdkey /delete:%SERVER% >nul 2>&1
cmdkey /delete:Domain:target=%SERVER% >nul 2>&1

REM Also scan and remove any other matching entries
setlocal EnableDelayedExpansion
for /f "tokens=1* delims=:" %%a in ('cmdkey /list ^| findstr /i "Target:"') do (
    set "TGT=%%b"
    if "!TGT:~0,1!"==" " set "TGT=!TGT:~1!"
    echo !TGT! | findstr /i "%SERVER%" >nul
    if !errorlevel! == 0 (
        cmdkey /delete:!TGT! >nul 2>&1
        echo       Removed: !TGT!
    )
)
endlocal
echo       Credential cleanup complete.

REM --- 6. Restart Workstation service (kills any cached sessions)-
echo.
echo Restarting Workstation service (LanmanWorkstation) ...
net stop lanmanworkstation /y
timeout /t 3 /nobreak >nul
net start lanmanworkstation

REM Re-start common dependents
net start "Computer Browser"                >nul 2>&1
net start "Netlogon"                        >nul 2>&1
net start "Distributed Link Tracking Client">nul 2>&1
net start "Background Intelligent Transfer Service" >nul 2>&1
net start "Offline Files"                   >nul 2>&1

echo.
echo ============================================================
echo  DONE.
echo   - %RUSER% logged off on %SERVER% (if a session existed)
echo   - Saved credentials for %SERVER% cleared on this PC
echo   - Workstation service restarted (LAN cache flushed)
echo ============================================================
echo.
pause
endlocal
exit /b 0
