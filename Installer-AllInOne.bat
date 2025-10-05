@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM 0) Python check (needed for WoWPresence + upstream installer)
REM ============================================================
py --version >NUL 2>&1
if errorlevel 1 goto :errorNoPython

REM ============================================================
REM 1) Accept AddOns folder via arg #1 OR show a single GUI picker
REM ============================================================
if not "%~1"=="" (
  set "ADDONS_DIR=%~1"
  goto :normalize_addons
)

REM ---- GUI picker once (safe handoff via temp file; no FOR /F)
setlocal DisableDelayedExpansion
set "TMPFILE=%TEMP%\addons_%RANDOM%%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-Type -AssemblyName System.Windows.Forms; " ^
  "$d = New-Object Windows.Forms.FolderBrowserDialog; " ^
  "$d.Description = 'Select WoW Interface\AddOns'; " ^
  "$d.SelectedPath = Join-Path $env:ProgramFiles 'World of Warcraft\Interface\AddOns'; " ^
  "if($d.ShowDialog() -ne 'OK'){ exit 1 }; " ^
  "[IO.File]::WriteAllText('%TMPFILE%', $d.SelectedPath)"
if errorlevel 1 ( echo Cancelled or failed to select a folder.& exit /b 1 )
set /p ADDONS_DIR=<"%TMPFILE%"
del "%TMPFILE%" >nul 2>&1
endlocal & set "ADDONS_DIR=%ADDONS_DIR%"

:normalize_addons
REM --- Normalize (strip quotes / trailing backslash), allow picking Interface and auto-append \AddOns
set "ADDONS_DIR=%ADDONS_DIR:"=%"
if "%ADDONS_DIR:~-1%"=="\" set "ADDONS_DIR=%ADDONS_DIR:~0,-1%"
if /I "%ADDONS_DIR:~-7%"=="\AddOns" (
  rem ok
) else (
  if exist "%ADDONS_DIR%\AddOns\" (
    set "ADDONS_DIR=%ADDONS_DIR%\AddOns"
  ) else (
    echo The selected folder is not Interface\AddOns. Selected: "%ADDONS_DIR%"
    pause & exit /b 1
  )
)
echo Using AddOns folder: "%ADDONS_DIR%"

REM ============================================================
REM 1.5) Prepare IPC dir + preflight write test (auto-elevate once)
REM ============================================================
set "IPC_DIR=%ADDONS_DIR%\IPC"
if not exist "%IPC_DIR%" mkdir "%IPC_DIR%" >nul 2>&1
>"%IPC_DIR%\.__wtest" echo ok 2>nul
if errorlevel 1 (
  echo Need write permission to "%IPC_DIR%". Trying elevation...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath '%~f0' -ArgumentList @('%ADDONS_DIR%') -Verb RunAs"
  exit /b
)
del "%IPC_DIR%\.__wtest" 2>nul

REM ============================================================
REM 2) Fetch project into AddOns\IPC (git with smart fallback → ZIP)
REM    Keep PS/curl calls outside IF (...) blocks to avoid () parsing issues
REM ============================================================
set "REPO_GIT=https://github.com/MagGomesu/wow-discord-rpc-ascension"
set "REPO_ZIP=https://github.com/MagGomesu/wow-discord-rpc-ascension/archive/refs/heads/wotlk.zip"

git --version >NUL 2>&1
if errorlevel 1 goto :doZip

echo Cloning repo via git...
set "TMP_REPO=%LOCALAPPDATA%\wowrpc_tmp_%RANDOM%_%RANDOM%"
if exist "%TMP_REPO%" rmdir /s /q "%TMP_REPO%"
git clone -b wotlk --single-branch "%REPO_GIT%" "%TMP_REPO%"
if errorlevel 1 (
  echo [git] clone failed; falling back to ZIP...
  goto :doZip
)
robocopy "%TMP_REPO%" "%IPC_DIR%" /E /NFL /NDL /NJH /NJS /NC /NS >NUL
if errorlevel 8 (
  echo robocopy reported a failure copying from git workdir.
  rmdir /s /q "%TMP_REPO%" 2>nul
  goto :errorDownload
)
rmdir /s /q "%TMP_REPO%" 2>nul
goto :afterFetch

:doZip
echo Downloading ZIP (wotlk)...
set "WORK=%LOCALAPPDATA%\wowrpc_installer"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
set "ZIPTMP=%WORK%\wowrpc_%RANDOM%.zip"
set "UNZIP_DIR=%WORK%\unz_%RANDOM%"

set "CURL=%SystemRoot%\System32\curl.exe"
if exist "%CURL%" (
  "%CURL%" -L -o "%ZIPTMP%" "%REPO_ZIP%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%REPO_ZIP%' -OutFile '%ZIPTMP%'"
)
if errorlevel 1 goto :errorDownload

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Expand-Archive -Path '%ZIPTMP%' -DestinationPath '%UNZIP_DIR%' -Force"
if errorlevel 1 goto :errorDownload

set "TOP="
for /d %%D in ("%UNZIP_DIR%\*") do (
  set "TOP=%%~fD"
  goto :gotTop
)
:gotTop
if not defined TOP (
  echo ZIP layout unexpected.
  goto :errorDownload
)

robocopy "%TOP%" "%IPC_DIR" /E /NFL /NDL /NJH /NJS /NC /NS >NUL
if errorlevel 8 goto :errorDownload

rd /s /q "%UNZIP_DIR%" 2>nul
del "%ZIPTMP%" 2>nul

:afterFetch

REM ============================================================
REM 3) Ensure Python deps (WoWPresence requirements) — robust
REM    - echo( … ) avoids () parsing
REM    - run pip in a fresh cmd so no prior block state leaks in
REM ============================================================
echo(Installing Python deps [pillow, pywin32]...
setlocal DisableDelayedExpansion
cmd /d /c "py -m pip install --disable-pip-version-check --quiet pillow pywin32"
set "PIP_RC=%ERRORLEVEL%"
endlocal

if not "%PIP_RC%"=="0" (
  echo(Pip quiet install failed, retrying verbose for diagnostics...
  py -m pip install pillow pywin32
  if errorlevel 1 (
    echo(FATAL: pip install still failing.
    goto :errorDownload
  )
)

REM ============================================================
REM 4) Locate Ascension Launcher (auto-detect; if missing, GUI picker)
REM ============================================================
set "ASC_EXE="
if exist "%ProgramFiles%\Ascension Launcher\Ascension Launcher.exe" set "ASC_EXE=%ProgramFiles%\Ascension Launcher\Ascension Launcher.exe"
if not defined ASC_EXE if defined ProgramFiles(x86) if exist "%ProgramFiles(x86)%\Ascension Launcher\Ascension Launcher.exe" set "ASC_EXE=%ProgramFiles(x86)%\Ascension Launcher\Ascension Launcher.exe"

if not defined ASC_EXE (
  echo Ascension not found in Program Files. Please select its install folder.
  setlocal DisableDelayedExpansion
  set "TMPASC=%TEMP%\asc_%RANDOM%%RANDOM%.txt"
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Add-Type -AssemblyName System.Windows.Forms; " ^
    "$d = New-Object Windows.Forms.FolderBrowserDialog; " ^
    "$d.Description = 'Select the Ascension Launcher folder (contains \"Ascension Launcher.exe\")'; " ^
    "$d.RootFolder = [System.Environment+SpecialFolder]::MyComputer; " ^
    "if($d.ShowDialog() -ne 'OK'){ exit 1 }; " ^
    "if(-not (Test-Path (Join-Path $d.SelectedPath 'Ascension Launcher.exe'))){ [System.Windows.Forms.MessageBox]::Show('Ascension Launcher.exe was not found in the selected folder.','Invalid folder',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error); exit 2 }; " ^
    "[IO.File]::WriteAllText('%TMPASC%', $d.SelectedPath)"
  if errorlevel 1 (
    echo Cancelled or invalid selection.
    exit /b 1
  )
  set /p ASC_DIR=<"%TMPASC%"
  del "%TMPASC%" >nul 2>&1
  endlocal & set "ASC_DIR=%ASC_DIR%"
  set "ASC_EXE=%ASC_DIR%\Ascension Launcher.exe"
)

if not exist "%ASC_EXE%" (
  echo [ERROR] Could not locate Ascension Launcher.exe.
  echo Re-run the installer and choose the correct folder.
  pause >nul
  exit /b 1
)

REM ============================================================
REM 5) Write "Ascension Launcher.bat" wrapper in IPC (uses chosen exe)
REM ============================================================
set "BAT_NAME=Ascension Launcher.bat"
set "BAT_PATH=%IPC_DIR%\%BAT_NAME%"
> "%BAT_PATH%" echo @echo off
>>"%BAT_PATH%" echo setlocal EnableExtensions
>>"%BAT_PATH%" echo pushd "%%~dp0"
>>"%BAT_PATH%" echo rem Preferred Ascension path captured at install time
>>"%BAT_PATH%" echo set "LauncherExe=%ASC_EXE%"
>>"%BAT_PATH%" echo if not exist "%%LauncherExe%%" (
>>"%BAT_PATH%" echo   echo [ERROR] Ascension Launcher.exe not found. Re-run installer to set path.
>>"%BAT_PATH%" echo   popd ^& exit /b 1
>>"%BAT_PATH%" echo )
>>"%BAT_PATH%" echo rem Launch Ascension quietly
>>"%BAT_PATH%" echo start "" "%%LauncherExe%%" ^>NUL 2^>^&1
>>"%BAT_PATH%" echo rem Keep WoWPresence console visible
>>"%BAT_PATH%" echo py "script\WoWPresence.py"
>>"%BAT_PATH%" echo popd
>>"%BAT_PATH%" echo endlocal

REM ============================================================
REM 6) Desktop shortcut (icon from chosen Ascension path; fallback if missing)
REM ============================================================
set "SHORTCUT_NAME=Ascension Launcher"
set "ICON_EXE=%ASC_EXE%"
if not exist "%ICON_EXE%" if exist "%ProgramFiles%\Ascension Launcher\Ascension Launcher.exe" set "ICON_EXE=%ProgramFiles%\Ascension Launcher\Ascension Launcher.exe"
if not exist "%ICON_EXE%" if defined ProgramFiles(x86) if exist "%ProgramFiles(x86)%\Ascension Launcher\Ascension Launcher.exe" set "ICON_EXE=%ProgramFiles(x86)%\Ascension Launcher\Ascension Launcher.exe"
set "DESKTOP=%USERPROFILE%\Desktop"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws=New-Object -ComObject WScript.Shell; $s=$ws.CreateShortcut('%DESKTOP%\%SHORTCUT_NAME%.lnk');" ^
  "$s.TargetPath='%BAT_PATH%'; $s.WorkingDirectory='%IPC_DIR%';" ^
  "if(Test-Path '%ICON_EXE%'){ $s.IconLocation='%ICON_EXE%,0' };" ^
  "$s.Description='Ascension + WoWPresence'; $s.Save()"

echo.
echo Installation complete.
echo - AddOns: "%ADDONS_DIR%"
echo - IPC:     "%IPC_DIR%"
echo - Ascension: "%ASC_EXE%"
echo - Shortcut on Desktop: "%SHORTCUT_NAME%.lnk"
echo.
echo IMPORTANT: Always launch using the shortcut or the .bat inside AddOns\IPC.
echo [Do NOT move the .bat elsewhere.]
echo You may now close this window. Press any key
echo.
pause >nul
goto :end

REM ============================================================
REM Errors
REM ============================================================
:errorNoPython
echo.
echo Error: Python 3 is not installed or 'py' launcher not found.
echo Please install Python 3 (with "Add to PATH") and re-run.
echo.
pause >nul
exit /b 1

:errorDownload
echo.
echo Error while downloading/extracting the ZIP from GitHub.
echo.
pause >nul
exit /b 1

:end
endlocal