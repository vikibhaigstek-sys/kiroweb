@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===============================================================
REM  unrestrict-drives-user1.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Remove drive restrictions for user1 — show ALL drives again.
REM
REM  Run as: Administrator ON THE SERVER
REM ===============================================================

title Unrestrict Drives for user1 - Show ALL drives

echo.
echo ============================================================
echo   Unrestrict Drives: Show ALL drives for user1
echo ============================================================
echo.
echo   This script must be run ON THE SERVER as Administrator.
echo   It will remove all drive restrictions for user1.
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

REM --- 1. Find user1's SID ---------------------------------------
echo.
echo [1/3] Finding SID for user1 ...

set "USERSID="
for /f "tokens=2 delims==" %%S in ('wmic useraccount where "Name='user1'" get SID /value 2^>nul ^| findstr /i "SID"') do (
    set "USERSID=%%S"
)

REM Remove any trailing carriage return
set "USERSID=!USERSID: =!"
for /f "delims=" %%a in ("!USERSID!") do set "USERSID=%%a"

if not defined USERSID (
    echo       [ERROR] Could not find SID for user1.
    echo       Make sure user1 exists on this server.
    pause
    exit /b 1
)
echo       Found SID: !USERSID!

REM --- 2. Load user1's registry hive if not loaded ---------------
echo.
echo [2/3] Checking user1 registry hive ...

reg query "HKU\!USERSID!\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" >nul 2>&1
if errorlevel 1 (
    echo       User1 hive not loaded. Loading from ntuser.dat ...
    
    set "PROFILEPATH="
    for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\!USERSID!" /v ProfileImagePath 2^>nul ^| findstr /i "ProfileImagePath"') do (
        set "PROFILEPATH=%%B"
    )
    
    if defined PROFILEPATH (
        reg load "HKU\!USERSID!" "!PROFILEPATH!\NTUSER.DAT" >nul 2>&1
        if errorlevel 1 (
            echo       Could not load hive. User may be logged in already.
            echo       Proceeding anyway...
        ) else (
            echo       Hive loaded successfully.
            set "HIVE_LOADED=1"
        )
    ) else (
        echo       Could not find profile path. Trying anyway...
    )
) else (
    echo       User1 registry hive already accessible.
)

REM --- 3. Remove drive restrictions --------------------------------
echo.
echo [3/3] Removing drive restrictions for user1 ...

REM Delete NoDrives (removes hidden drives)
reg delete "HKU\!USERSID!\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDrives /f >nul 2>&1
if errorlevel 1 (
    echo       NoDrives was not set (already unrestricted).
) else (
    echo       NoDrives removed (all drives visible now).
)

REM Delete NoViewOnDrive (removes access block)
reg delete "HKU\!USERSID!\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoViewOnDrive /f >nul 2>&1
if errorlevel 1 (
    echo       NoViewOnDrive was not set (already unrestricted).
) else (
    echo       NoViewOnDrive removed (all drives accessible now).
)

REM --- Unload hive if we loaded it --------------------------------
if defined HIVE_LOADED (
    reg unload "HKU\!USERSID!" >nul 2>&1
    echo       Registry hive unloaded.
)

echo.
echo ============================================================
echo  DONE. Drive restrictions REMOVED for user1:
echo.
echo   ALL drives are now visible and accessible for user1.
echo   (A: B: C: D: E: F: ... Z:)
echo.
echo   NOTE: user1 must log off and log back in to see changes.
echo ============================================================
echo.

REM --- Show popup message ----------------------------------------
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Drive restrictions removed for user1.\n\nAll drives are now visible and accessible.\nUser1 must log off and log back in.',0,'Drives Unrestricted',64);close();"

endlocal
exit /b 0
