@echo off
setlocal EnableExtensions

REM ===============================================================
REM  force-logoff-server.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Force-log off remote RDP user "user1" on host "SERVER"
REM    from this client PC.
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
echo   Force logoff "%RUSER%" on "%SERVER%"
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

REM --- 1. Store credentials and establish connection -------------
echo.
echo [1/3] Authenticating to %SERVER% ...
cmdkey /add:%SERVER% /user:%RUSER% /pass:"%RPASS%" >nul 2>&1
net use \\%SERVER%\IPC$ /user:%SERVER%\%RUSER% "%RPASS%" >nul 2>&1
if errorlevel 1 (
    net use \\%SERVER%\IPC$ /user:%RUSER% "%RPASS%" >nul 2>&1
)
echo       Credentials stored and connection established.

REM --- 2. Force logoff using multiple approaches -----------------
echo.
echo [2/3] Force logging off %RUSER% on %SERVER% ...
echo.

REM --- Method A: Direct logoff via qwinsta -----------------------
echo       Method A: Querying sessions with qwinsta...
set "SID="
for /f "usebackq delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$lines = qwinsta /server:%SERVER% 2>&1; foreach ($line in $lines) { if ($line -match '%RUSER%') { if ($line -match '\s+(\d+)\s+') { Write-Output $Matches[1]; break } } }"`) do (
    set "SID=%%S"
)

if defined SID (
    echo       Found session ID: %SID%
    logoff %SID% /server:%SERVER% /v
    if not errorlevel 1 (
        echo       SUCCESS: Session %SID% logged off.
        goto :logoff_done
    )
    echo       logoff command failed, trying reset...
    reset session %SID% /server:%SERVER%
    if not errorlevel 1 (
        echo       SUCCESS: Session %SID% reset.
        goto :logoff_done
    )
)

echo       Method A did not work. Trying Method B...
echo.

REM --- Method B: Use PowerShell with explicit credentials --------
echo       Method B: PowerShell WMI remote logoff...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pass = ConvertTo-SecureString -String '%RPASS%' -AsPlainText -Force;" ^
  "$cred = New-Object System.Management.Automation.PSCredential('%SERVER%\%RUSER%', $pass);" ^
  "$sessions = Get-WmiObject -Class Win32_Process -ComputerName '%SERVER%' -Credential $cred -Filter \"Name='explorer.exe'\" -ErrorAction SilentlyContinue;" ^
  "if ($sessions) {" ^
  "  foreach ($proc in $sessions) {" ^
  "    $owner = $proc.GetOwner();" ^
  "    if ($owner.User -eq '%RUSER%') {" ^
  "      $proc.Terminate() | Out-Null;" ^
  "      Write-Host '      SUCCESS: Terminated explorer.exe for %RUSER%'" ^
  "    }" ^
  "  }" ^
  "} else {" ^
  "  Write-Host '      No explorer.exe found, trying Win32_OperatingSystem...';" ^
  "  $os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName '%SERVER%' -Credential $cred -ErrorAction SilentlyContinue;" ^
  "  if ($os) {" ^
  "    $os.Win32Shutdown(4) | Out-Null;" ^
  "    Write-Host '      Forced logoff signal sent via WMI'" ^
  "  } else {" ^
  "    Write-Host '      WMI connection failed';" ^
  "    exit 1" ^
  "  }" ^
  "}"

if not errorlevel 1 goto :logoff_done

echo       Method B did not work. Trying Method C...
echo.

REM --- Method C: taskkill to kill all user processes remotely -----
echo       Method C: Killing all processes for %RUSER% via taskkill...
taskkill /s %SERVER% /u %SERVER%\%RUSER% /p "%RPASS%" /fi "USERNAME eq %RUSER%" /f
if not errorlevel 1 (
    echo       SUCCESS: All processes terminated for %RUSER%.
    goto :logoff_done
)

REM --- Method D: shutdown command to force logoff ----------------
echo       Method C did not work. Trying Method D...
echo.
echo       Method D: Remote shutdown /l ...
shutdown /m \\%SERVER% /l /f
if not errorlevel 1 (
    echo       SUCCESS: Forced logoff via shutdown command.
    goto :logoff_done
)

echo.
echo       [WARNING] All methods attempted. Check server connectivity.

:logoff_done
echo.
echo       Logoff step complete.

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

REM First: explicitly delete all known LAN credential formats
cmdkey /delete:%SERVER% >nul 2>&1 && echo       REMOVED: %SERVER%
cmdkey /delete:Domain:target=%SERVER% >nul 2>&1 && echo       REMOVED: Domain:target=%SERVER%
cmdkey /delete:Domain:interactive=%SERVER%\%RUSER% >nul 2>&1 && echo       REMOVED: Domain:interactive=%SERVER%\%RUSER%
cmdkey /delete:Domain:interactive=%SERVER%\Administrator >nul 2>&1 && echo       REMOVED: Domain:interactive=%SERVER%\Administrator
cmdkey /delete:LegacyGeneric:target=%SERVER% >nul 2>&1 && echo       REMOVED: LegacyGeneric:target=%SERVER%
cmdkey /delete:%SERVER%.* >nul 2>&1 && echo       REMOVED: %SERVER%.*

REM Second: use PowerShell to find and delete any remaining non-TERMSRV creds
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
echo   - %RUSER% force logged off on %SERVER%
echo   - LAN/SMB credentials REMOVED (no LAN access possible)
echo   - TERMSRV/RDP credentials KEPT (Remote Desktop works)
echo   - Workstation service restarted (LAN cache flushed)
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Task Completed Successfully. Please connect Remote Again.\n\nLAN access cleared. RDP still works.',0,'Message',64);close();"

endlocal
exit /b 0
