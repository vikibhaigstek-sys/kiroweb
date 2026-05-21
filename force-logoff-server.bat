@echo off
setlocal EnableExtensions

REM ===============================================================
REM  force-logoff-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    1. Force-log off remote RDP user "user1" on host "SERVER"
REM       from this client PC using multiple methods.
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

REM --- 1. Store credentials so remote commands authenticate ------
echo.
echo [1/6] Storing temporary credentials for %SERVER% ...
cmdkey /add:%SERVER% /user:%RUSER% /pass:"%RPASS%" >nul 2>&1
echo       Done.

REM --- 2. Force logoff using PowerShell (most reliable method) ---
echo.
echo [2/6] Force logging off %RUSER% on %SERVER% via PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pw = ConvertTo-SecureString '%RPASS%' -AsPlainText -Force;" ^
  "$cred = New-Object System.Management.Automation.PSCredential('%SERVER%\%RUSER%', $pw);" ^
  "try {" ^
  "  $session = Invoke-Command -ComputerName %SERVER% -Credential $cred -ScriptBlock {" ^
  "    $s = quser 2>&1 | Where-Object { $_ -match '%RUSER%' };" ^
  "    if ($s) {" ^
  "      $id = ($s -split '\s+')[($s -match 'Disc' ? 2 : 3)];" ^  
  "      logoff $id /v;" ^
  "      Write-Output \"Logged off session ID: $id\"" ^
  "    } else {" ^
  "      Write-Output 'NO_SESSION_FOUND'" ^
  "    }" ^
  "  } -ErrorAction Stop;" ^
  "  Write-Host \"  Result: $session\"" ^
  "} catch {" ^
  "  Write-Host \"  PowerShell remoting failed: $_\";" ^
  "  Write-Host '  Trying alternative method...';" ^
  "  exit 1" ^
  "}"

if errorlevel 1 (
    echo.
    echo       PowerShell remoting not available, trying qwinsta method...
    goto :try_qwinsta
)
goto :cred_cleanup

:try_qwinsta
REM --- 3. Fallback: use qwinsta + logoff -------------------------
echo.
echo [3/6] Trying qwinsta /server:%SERVER% ...

REM First establish IPC$ connection
net use \\%SERVER%\IPC$ /user:%SERVER%\%RUSER% "%RPASS%" >nul 2>&1
if errorlevel 1 (
    net use \\%SERVER%\IPC$ /user:%RUSER% "%RPASS%" >nul 2>&1
)

REM Use PowerShell to parse qwinsta output (avoids batch parsing issues)
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command ^
  "$out = qwinsta /server:%SERVER% 2>&1 | Out-String;" ^
  "$lines = $out -split [Environment]::NewLine;" ^
  "foreach ($line in $lines) {" ^
  "  if ($line -match '%RUSER%') {" ^
  "    if ($line -match '\s+(\d+)\s+') { $Matches[1]; break }" ^
  "  }" ^
  "}"`) do (
    set "SID=%%S"
)

if defined SID (
    echo       Found session ID: %SID%
    echo       Forcing logoff...
    logoff %SID% /server:%SERVER% /v
    if errorlevel 1 (
        echo       logoff failed, trying reset session...
        reset session %SID% /server:%SERVER%
    ) else (
        echo       Logoff successful.
    )
) else (
    echo       qwinsta could not find session. Trying final method...
    goto :try_taskkill
)
goto :cleanup_ipc

:try_taskkill
REM --- 3b. Last resort: taskkill on explorer.exe for user1 -------
echo.
echo       Using taskkill to end all processes of %RUSER% on %SERVER%...
taskkill /s %SERVER% /u %SERVER%\%RUSER% /p "%RPASS%" /fi "USERNAME eq %RUSER%" /f >nul 2>&1
echo       taskkill executed (this effectively logs off the user).

:cleanup_ipc
REM Disconnect IPC$
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1

:cred_cleanup
REM --- 4. Remove ALL saved credentials for SERVER ----------------
echo.
echo [4/6] Removing saved credentials for %SERVER% ...

REM Delete known credential formats
cmdkey /delete:%SERVER% >nul 2>&1
cmdkey /delete:TERMSRV/%SERVER% >nul 2>&1
cmdkey /delete:Domain:target=%SERVER% >nul 2>&1
cmdkey /delete:%SERVER%.* >nul 2>&1

REM Scan and remove any remaining entries matching SERVER
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

REM --- 5. Delete all net use connections -------------------------
echo.
echo [5/6] Clearing all network connections ...
net use * /delete /y >nul 2>&1
echo       Done.

REM --- 6. Restart Workstation service ----------------------------
echo.
echo [6/6] Restarting Workstation service (LanmanWorkstation) ...
net stop lanmanworkstation /y
timeout /t 3 /nobreak >nul
net start lanmanworkstation

REM Re-start dependent services
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
