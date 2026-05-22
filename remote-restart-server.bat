@echo off
setlocal EnableExtensions

REM ===============================================================
REM  remote-restart-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Remotely restart SERVER from client PC using Administrator
REM    credentials.
REM
REM  Run as: Administrator (right-click -> Run as administrator)
REM ===============================================================

REM ---- Server and credentials -----------------------------------
set "SERVER=SERVER"
set "RUSER=Administrator"
set "RPASS=P@ss3212"
REM ---------------------------------------------------------------

title Remote Restart %SERVER%

echo.
echo ============================================================
echo   Remote Restart "%SERVER%" using %RUSER% credentials
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
echo [1/5] Authenticating to %SERVER% ...
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

REM --- 2. Send remote restart command ----------------------------
echo.
echo [2/5] Sending restart command to %SERVER% ...
echo       Server will restart in 10 seconds...
shutdown /m \\%SERVER% /r /f /t 10 /c "Remote restart initiated from client PC"
if errorlevel 1 (
    echo       shutdown command failed. Trying alternative...
    shutdown /m \\%SERVER% /r /f /t 0
    if errorlevel 1 (
        echo       [ERROR] Could not restart server. Check permissions.
    )
)
echo       SUCCESS: Restart command sent to %SERVER%.

REM --- 3. Disconnect all network shares to SERVER -----------------
echo.
echo [3/5] Disconnecting all network shares to %SERVER% ...
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
net use \\%SERVER%\C$ /delete /y >nul 2>&1
net use \\%SERVER%\D$ /delete /y >nul 2>&1
net use \\%SERVER%\E$ /delete /y >nul 2>&1
net use * /delete /y >nul 2>&1
echo       Done.

REM --- 4. Remove LAN credentials BUT keep TERMSRV (RDP) ----------
echo.
echo [4/5] Removing LAN credentials (keeping RDP) ...

cmdkey /delete:%SERVER% >nul 2>&1 && echo       REMOVED: %SERVER%
cmdkey /delete:Domain:target=%SERVER% >nul 2>&1 && echo       REMOVED: Domain:target=%SERVER%
cmdkey /delete:Domain:interactive=%SERVER%\%RUSER% >nul 2>&1 && echo       REMOVED: Domain:interactive=%SERVER%\%RUSER%
cmdkey /delete:Domain:interactive=%SERVER%\user1 >nul 2>&1 && echo       REMOVED: Domain:interactive=%SERVER%\user1
cmdkey /delete:LegacyGeneric:target=%SERVER% >nul 2>&1 && echo       REMOVED: LegacyGeneric:target=%SERVER%

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$output = cmdkey /list 2>&1 | Out-String;" ^
  "$targets = [regex]::Matches($output, 'Target:\s*(.+)');" ^
  "foreach ($t in $targets) {" ^
  "  $target = $t.Groups[1].Value.Trim();" ^
  "  if ($target -match '%SERVER%' -and $target -notmatch 'TERMSRV') {" ^
  "    $null = cmdkey /delete:$target 2>&1;" ^
  "    Write-Host ('      REMOVED: ' + $target + ' (LAN credential)')" ^
  "  } elseif ($target -match 'TERMSRV' -and $target -match '%SERVER%') {" ^
  "    Write-Host ('      KEEPING: ' + $target + ' (RDP credential)')" ^
  "  }" ^
  "}"

echo       Credential cleanup complete.

REM --- 5. Restart Workstation service (flush cached LAN sessions) -
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
echo   - Restart command sent to %SERVER%
echo   - Server will reboot in ~10 seconds
echo   - LAN/SMB credentials REMOVED
echo   - TERMSRV/RDP credentials KEPT
echo   - Workstation service restarted
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Server Restart Command Sent Successfully. Please wait 2-3 minutes and then connect Remote Again.',0,'Message',64);close();"

endlocal
exit /b 0
