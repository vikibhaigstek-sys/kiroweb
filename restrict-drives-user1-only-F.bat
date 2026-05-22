@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===============================================================
REM  restrict-drives-user1-only-F.bat
REM  -------------------------------------------------------------
REM  Purpose:
REM    Hide and block access to ALL drives EXCEPT F: for user1.
REM    Administrator keeps full access to all drives.
REM
REM  Value: 67108863 - 32 (F:) = 67108831
REM
REM  Run as: Administrator ON THE SERVER
REM ===============================================================

title Restrict Drives for user1 - Show only F:

echo.
echo ============================================================
echo   Restrict Drives: Show ONLY F: drive for user1
echo ============================================================
echo.
echo   This script must be run ON THE SERVER as Administrator.
echo   It will hide all drives except F: for user1 only.
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

REM --- 3. Apply drive restrictions --------------------------------
echo.
echo [3/3] Applying drive restrictions for user1 ...

reg add "HKU\!USERSID!\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /f >nul 2>&1

REM NoDrives = 67108831 (all hidden except F:)
reg add "HKU\!USERSID!\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDrives /t REG_DWORD /d 67108831 /f >nul 2>&1
if errorlevel 1 (
    echo       [ERROR] Failed to set NoDrives.
) else (
    echo       NoDrives = 67108831 (all hidden except F:)
)

REM NoViewOnDrive = 67108831 (access blocked except F:)
reg add "HKU\!USERSID!\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoViewOnDrive /t REG_DWORD /d 67108831 /f >nul 2>&1
if errorlevel 1 (
    echo       [ERROR] Failed to set NoViewOnDrive.
) else (
    echo       NoViewOnDrive = 67108831 (access blocked except F:)
)

if defined HIVE_LOADED (
    reg unload "HKU\!USERSID!" >nul 2>&1
    echo       Registry hive unloaded.
)

echo.
echo ============================================================
echo  DONE. Drive restrictions applied for user1:
echo.
echo   VISIBLE drives for user1:  F: only
echo   HIDDEN drives for user1:   A: B: C: D: E: G: H: ... Z:
echo   ACCESS blocked:            All drives except F:
echo.
echo   Administrator:             Full access (no change)
echo.
echo  NOTE: user1 must log off and log back in to see changes.
echo ============================================================
echo.

mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Drive restriction applied for user1.\n\nOnly F: drive will be visible.\nUser1 must log off and log back in.',0,'Drives Restricted',64);close();"

endlocal
exit /b 0
