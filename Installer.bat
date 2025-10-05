@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM -----------------------------
REM 0) Python check
REM -----------------------------
py --version >NUL 2>&1
if errorlevel 1 goto :errorNoPython

REM -----------------------------
REM 1) Pick Interface\AddOns (GUI) safely via temp file
REM -----------------------------
setlocal DisableDelayedExpansion
set "TMPFILE=%TEMP%\addons_%RANDOM%%RANDOM%.txt"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-Type -AssemblyName System.Windows.Forms; " ^
  "$d = New-Object Windows.Forms.FolderBrowserDialog; " ^
  "$d.Description = 'Select WoW Interface\AddOns'; " ^
  "$d.SelectedPath = Join-Path $env:ProgramFiles 'World of Warcraft\Interface\AddOns'; " ^
  "if($d.ShowDialog() -ne 'OK'){ exit 1 }; " ^
  "[IO.File]::WriteAllText('%TMPFILE%', $d.SelectedPath)"

if errorlevel 1 (
  echo Cancelled or failed to select a folder.
  exit /b 1
)

set /p ADDONS_DIR=<"%TMPFILE%"
del "%TMPFILE%" >nul 2>&1
endlocal & set "ADDONS_DIR=%ADDONS_DIR%"

REM Normalize (strip quotes / trailing backslash)
set "ADDONS_DIR=%ADDONS_DIR:"=%"
if "%ADDONS_DIR:~-1%"=="\" set "ADDONS_DIR=%ADDONS_DIR:~0,-1%"

REM Ensure it is ...\Interface\AddOns (accept Interface or root and auto-append)
if /I "%ADDONS_DIR:~-7%"=="\AddOns" (
  REM already correct
) else (
  if exist "%ADDONS_DIR%\AddOns\" (
    set "ADDONS_DIR=%ADDONS_DIR%\AddOns"
  ) else (
    echo The selected folder is not Interface\AddOns. Selected: "%ADDONS_DIR%"
    pause
    exit /b 1
  )
)

echo Using AddOns folder: "%ADDONS_DIR%"

set "IPC_DIR=%ADDONS_DIR%\IPC"
if not exist "%IPC_DIR%" mkdir "%IPC_DIR%"

REM ─────────────────────────────────────────────────────────────
REM 2) Fetch project into AddOns\IPC (git with smart fallback → ZIP)
REM ─────────────────────────────────────────────────────────────
set "REPO_GIT=https://github.com/MagGomesu/wow-discord-rpc-ascension"
set "REPO_ZIP=https://github.com/MagGomesu/wow-discord-rpc-ascension/archive/refs/heads/wotlk.zip"

REM Prefer git if available
git --version >NUL 2>&1
if errorlevel 1 goto :doZip

REM --- Try git clone into a temp working dir
echo Cloning repo via git...
set "TMP_REPO=%TEMP%\wowrpc-%RANDOM%-%RANDOM%"
if exist "%TMP_REPO%" rmdir /s /q "%TMP_REPO%"
git clone -b wotlk --single-branch "%REPO_GIT%" "%TMP_REPO%"
if errorlevel 1 (
  echo [git] clone failed; falling back to ZIP...
  goto :doZip
)

robocopy "%TMP_REPO%" "%IPC_DIR%" /E /NFL /NDL /NJH /NJS /NC /NS >NUL
rmdir /s /q "%TMP_REPO%"
goto :afterFetch

:doZip
echo Downloading ZIP (wotlk)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$u='%REPO_ZIP%';" ^
  "$zip=Join-Path $env:TEMP ('wowrpc-'+[guid]::NewGuid().ToString()+'.zip');" ^
  "Invoke-WebRequest -Uri $u -OutFile $zip;" ^
  "$unz=Join-Path $env:TEMP ('wowrpc-'+[guid]::NewGuid().ToString());" ^
  "Expand-Archive -Path $zip -DestinationPath $unz -Force;" ^
  "$top=(Get-ChildItem -Directory $unz | Select-Object -First 1);" ^
  "Copy-Item -Path (Join-Path $top.FullName '*') -Destination '%IPC_DIR%' -Recurse -Force;" ^
  "Remove-Item $zip -Force; Remove-Item $unz -Recurse -Force"
if errorlevel 1 goto :errorDownload

:afterFetch


REM -----------------------------
REM 3) Ensure Python deps (WoWPresence requirements)
REM -----------------------------
echo Installing Python deps (pillow, pywin32)...
py -m pip install --disable-pip-version-check --quiet pillow pywin32

REM -----------------------------
REM 4) Run upstream Installer.  bat (creates WoW.bat in IPC)
REM -----------------------------
pushd "%IPC_DIR%"
if not exist "Installer.bat" (
  echo ERROR: Installer.bat not found in "%IPC_DIR%".
  popd
  goto :end
)
echo Running upstream Installer.bat...
call "Installer.bat"
popd

REM -----------------------------
REM 5) Write "Ascension Launcher.bat" wrapper in IPC
REM -----------------------------
set "BAT_NAME=Ascension Launcher.bat"
set "BAT_PATH=%IPC_DIR%\%BAT_NAME%"
> "%BAT_PATH%" echo @echo off
>>"%BAT_PATH%" echo setlocal EnableExtensions
>>"%BAT_PATH%" echo pushd "%%~dp0"
>>"%BAT_PATH%" echo rem Detect Ascension Launcher path (x64/x86)
>>"%BAT_PATH%" echo set "LauncherExe="
>>"%BAT_PATH%" echo if exist "%%ProgramFiles%%\Ascension Launcher\Ascension Launcher.exe" set "LauncherExe=%%ProgramFiles%%\Ascension Launcher\Ascension Launcher.exe"
>>"%BAT_PATH%" echo if not defined LauncherExe if defined ProgramFiles(x86) if exist "%%ProgramFiles(x86)%%\Ascension Launcher\Ascension Launcher.exe" set "LauncherExe=%%ProgramFiles(x86)%%\Ascension Launcher\Ascension Launcher.exe"
>>"%BAT_PATH%" echo if not defined LauncherExe (
>>"%BAT_PATH%" echo   echo [ERROR] Ascension Launcher.exe not found in Program Files.
>>"%BAT_PATH%" echo   popd ^& exit /b 1
>>"%BAT_PATH%" echo )
>>"%BAT_PATH%" echo rem Launch Ascension quietly
>>"%BAT_PATH%" echo start "" "%%LauncherExe%%" ^>NUL 2^>^&1
>>"%BAT_PATH%" echo rem Keep WoWPresence console visible
>>"%BAT_PATH%" echo py "script\WoWPresence.py"
>>"%BAT_PATH%" echo popd
>>"%BAT_PATH%" echo endlocal

REM -----------------------------
REM 6) Desktop shortcut (icon from Ascension; fallback if missing)
REM -----------------------------
set "SHORTCUT_NAME=Ascension Launcher"
set "ICON_EXE=%ProgramFiles%\Ascension Launcher\Ascension Launcher.exe"
if not exist "%ICON_EXE%" if defined ProgramFiles(x86) set "ICON_EXE=%ProgramFiles(x86)%\Ascension Launcher\Ascension Launcher.exe"
set "DESKTOP=%USERPROFILE%\Desktop"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws=New-Object -ComObject WScript.Shell; $s=$ws.CreateShortcut('%DESKTOP%\%SHORTCUT_NAME%.lnk');" ^
  "$s.TargetPath='%BAT_PATH%'; $s.WorkingDirectory='%IPC_DIR%';" ^
  "if(Test-Path '%ICON_EXE%'){ $s.IconLocation='%ICON_EXE%,0' };" ^
  "$s.Description='Ascension + WoWPresence'; $s.Save()"

echo.
echo Installation complete.
echo  - AddOns: "%ADDONS_DIR%"
echo  - IPC:     "%IPC_DIR%"
echo  - Shortcut on Desktop: %SHORTCUT_NAME%.lnk

echo.
echo IMPORTANT: Always launch using the desktop shortcut or the .bat inside AddOns\IPC.
echo Do NOT move the .bat elsewhere.
echo.
pause >nul
goto :end

:errorNoPython
echo.
echo Error: Python 3 is not installed or 'py' launcher not found.
echo Please install Python 3 (with "Add to PATH") and re-run.
echo.
pause >nul
exit /b 1

:errorClone
echo.
echo Error while cloning the repository. Check your internet connection or git.
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
