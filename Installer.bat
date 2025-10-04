@echo off
setlocal EnableExtensions

:: ─────────────────────────────────────────────────────────────
:: 1) Check for Python and install deps
:: ─────────────────────────────────────────────────────────────
py --version >NUL 2>&1
if errorlevel 1 goto errorNoPython

py -m pip install pillow pywin32

:: ─────────────────────────────────────────────────────────────
:: 2) Paths & names
:: ─────────────────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
set "BAT_NAME=Ascension Launcher.bat"
set "BAT_PATH=%SCRIPT_DIR%%BAT_NAME%"
set "DESKTOP=%USERPROFILE%\Desktop"

:: Prefer 64-bit Program Files; fall back to x86 for the icon source
set "ICON_EXE=%ProgramFiles%\Ascension Launcher\Ascension Launcher.exe"
if not exist "%ICON_EXE%" if defined ProgramFiles(x86) set "ICON_EXE=%ProgramFiles(x86)%\Ascension Launcher\Ascension Launcher.exe"

:: ─────────────────────────────────────────────────────────────
:: 3) Write Ascension Launcher.bat
::    - Launches Ascension Launcher silently
::    - Runs WoWPresence script and keeps its console output
:: ─────────────────────────────────────────────────────────────
> "%BAT_PATH%" echo @echo off
>>"%BAT_PATH%" echo setlocal EnableExtensions
>>"%BAT_PATH%" echo pushd "%%~dp0"
>>"%BAT_PATH%" echo rem Detect Ascension Launcher path (x64/x86)
>>"%BAT_PATH%" echo set "LauncherExe="
>>"%BAT_PATH%" echo if exist "%%ProgramFiles%%\Ascension Launcher\Ascension Launcher.exe" set "LauncherExe=%%ProgramFiles%%\Ascension Launcher\Ascension Launcher.exe"
>>"%BAT_PATH%" echo if not defined LauncherExe if defined ProgramFiles(x86) if exist "%%ProgramFiles(x86)%%\Ascension Launcher\Ascension Launcher.exe" set "LauncherExe=%%ProgramFiles(x86)%%\Ascension Launcher\Ascension Launcher.exe"
>>"%BAT_PATH%" echo if not defined LauncherExe (
>>"%BAT_PATH%" echo   echo [ERROR] Ascension Launcher.exe not found in Program Files.
>>"%BAT_PATH%" echo   popd
>>"%BAT_PATH%" echo   exit /b 1
>>"%BAT_PATH%" echo )
>>"%BAT_PATH%" echo rem Launch the game launcher without cluttering this console
>>"%BAT_PATH%" echo start "" "%%LauncherExe%%" ^>NUL 2^>^&1
>>"%BAT_PATH%" echo rem Now run presence script (keep its console output visible)
>>"%BAT_PATH%" echo py "script\WoWPresence.py"
>>"%BAT_PATH%" echo popd
>>"%BAT_PATH%" echo endlocal

:: ─────────────────────────────────────────────────────────────
:: 4) Create desktop shortcut with icon from Ascension Launcher.exe
:: ─────────────────────────────────────────────────────────────
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell; " ^
  "$s  = $ws.CreateShortcut('%DESKTOP%\Ascension Launcher.lnk'); " ^
  "$s.TargetPath      = '%BAT_PATH%'; " ^
  "$s.WorkingDirectory= '%SCRIPT_DIR%'; " ^
  "$s.IconLocation    = '%ICON_EXE%,0'; " ^
  "$s.Description     = 'Ascension + WoWPresence'; " ^
  "$s.Save()"

:: ─────────────────────────────────────────────────────────────
:: 5) Self-delete and exit
:: ─────────────────────────────────────────────────────────────
echo Installation Complete. Press any key
pause >nul
del /f "%~f0"
goto :eof

:errorNoPython
echo.
echo Error^: Python 3 is not installed
pause
