@echo off
setlocal EnableExtensions EnableDelayedExpansion

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

REM ---- Edit these two lines if you ever change the names --------
set "SERVER=SERVER"
set "RUSER=user1"
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

REM --- 1. Ask for password (hidden input via PowerShell) ---------
echo Enter the password for %SERVER%\%RUSER% (input is hidden):
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command ^
   "$p=Read-Host -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"`) do set "RPASS=%%P"

if not defined RPASS (
    echo [ERROR] No password entered. Aborting.
    pause
    exit /b 1
)

REM --- 2. Authenticate to SERVER ---------------------------------
echo.
echo [1/5] Connecting to \\%SERVER%\IPC$ ...
net use \\%SERVER%\IPC$ /user:%SERVER%\%RUSER% "!RPASS!" >nul 2>&1
if errorlevel 1 (
    echo       FAILED. Check server name, network, and credentials.
    set "RPASS="
    pause
    exit /b 1
)
echo       Connected.

REM --- 3. Find session ID of %RUSER% on %SERVER% -----------------
echo.
echo [2/5] Looking up session ID for %RUSER% on %SERVER% ...
set "SID="

REM quser output columns differ between Active and Disconnected sessions:
REM   Active        : USERNAME  SESSIONNAME  ID  STATE  IDLE TIME  LOGON TIME
REM   Disconnected  : USERNAME               ID  STATE  IDLE TIME  LOGON TIME
for /f "skip=1 tokens=1,2,3,4" %%A in ('quser /server:%SERVER% 2^>nul') do (
    set "U=%%A"
    REM Strip a possible leading ">" marker
    if "!U:~0,1!"==">" set "U=!U:~1!"
    if /i "!U!"=="%RUSER%" (
        REM If token2 is numeric, the session is Disconnected -> ID is %%B
        REM Otherwise the session is Active and ID is %%C
        echo %%B| findstr /r "^[0-9][0-9]*$" >nul
        if !errorlevel! == 0 (
            set "SID=%%B"
        ) else (
            set "SID=%%C"
        )
    )
)

if not defined SID (
    echo       No active session found for %RUSER%. Skipping logoff.
    goto :disconnect
)
echo       Session ID = !SID!

REM --- 4. Force the logoff ---------------------------------------
echo.
echo [3/5] Forcing logoff of session !SID! on %SERVER% ...
logoff !SID! /server:%SERVER% /v
if errorlevel 1 (
    echo       WARNING: logoff returned a non-zero exit code.
) else (
    echo       Logoff issued successfully.
)

:disconnect
REM --- 5. Drop the SMB session to SERVER -------------------------
echo.
echo [4/5] Disconnecting \\%SERVER%\IPC$ ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1

REM Wipe password from memory as soon as we no longer need it
set "RPASS="

REM --- 6. Remove saved creds for SERVER from Credential Manager --
echo.
echo [5/5] Removing saved credentials matching "%SERVER%" ...
set "REMOVED=0"
for /f "tokens=1* delims=:" %%a in ('cmdkey /list ^| findstr /i "Target:"') do (
    set "TGT=%%b"
    REM Trim a single leading space, if present
    if "!TGT:~0,1!"==" " set "TGT=!TGT:~1!"
    echo !TGT! | findstr /i "%SERVER%" >nul
    if !errorlevel! == 0 (
        cmdkey /delete:!TGT! >nul 2>&1
        if !errorlevel! == 0 (
            echo       Removed: !TGT!
            set /a REMOVED+=1
        )
    )
)
if "!REMOVED!"=="0" echo       No saved credentials referenced %SERVER%.

REM --- 7. Restart Workstation service (kills any cached sessions)-
echo.
echo Restarting Workstation service ^(LanmanWorkstation^) ...
net stop  lanmanworkstation /y
timeout /t 2 /nobreak >nul
net start lanmanworkstation

REM Re-start common dependents that 'net stop' takes down with it.
REM Errors are suppressed because not every service exists on every
REM Windows edition / build.
net start "Computer Browser"                >nul 2>&1
net start "Netlogon"                        >nul 2>&1
net start "Distributed Link Tracking Client">nul 2>&1
net start "Background Intelligent Transfer Service" >nul 2>&1
net start "Offline Files"                   >nul 2>&1

echo.
echo ------------------------------------------------------------
echo  DONE.
echo   - %RUSER% logged off on %SERVER% (if a session existed)
echo   - Saved credentials for %SERVER% cleared on this PC
echo   - Workstation service restarted (LAN cache flushed)
echo ------------------------------------------------------------
echo.
pause
endlocal
exit /b 0
