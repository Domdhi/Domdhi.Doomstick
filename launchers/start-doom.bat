@echo off
REM DOOM launcher: starts redbean serving the USB root on :8768, opens browser to /doom/.
REM Lives at the USB root; references ai-kit\redbean\ alongside.
setlocal
set "ROOT=%~dp0"
set "PORT=8768"
set "REDBEAN=%ROOT%ai-kit\redbean\redbean.com"
set "DOOM_DIR=%ROOT%doom"
set "LOG=%ROOT%ai-kit\redbean.log"

if not exist "%REDBEAN%" (
  echo.
  echo  ERROR: %REDBEAN% not found.
  echo         Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)
if not exist "%DOOM_DIR%\index.html" (
  echo.
  echo  ERROR: %DOOM_DIR%\index.html not found.
  echo         Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)
if not exist "%DOOM_DIR%\doom1.wad" (
  echo.
  echo  WARNING: doom1.wad not present — game will fail to load.
  echo           Re-run build-usb.ps1 to fetch the shareware WAD.
  echo.
)

cls
echo.
echo  ==============================================
echo          DOOM — Doomstick · v0.5
echo  ==============================================
echo.

REM Reuse an existing redbean if it's already serving /health.
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/health -TimeoutSec 1) | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
  echo  redbean already running on %PORT% — reusing.
  set "STARTED_REDBEAN=0"
  goto open
)
set "STARTED_REDBEAN=1"

REM Clean any orphan redbean from a previous run.
taskkill /F /IM redbean.com >nul 2>&1
taskkill /F /IM redbean.exe >nul 2>&1

REM Windows refuses to launch a .com directly in some shells; copy to .exe at first run.
if not exist "%REDBEAN%.exe" copy /Y "%REDBEAN%" "%REDBEAN%.exe" >nul

REM .init.lua is baked into redbean.com's appended zip by build-usb.ps1 —
REM no per-launch staging needed. cd /d %ROOT% so saves.db lands at
REM ai-kit\redbean\saves.db (relative to redbean's CWD).
start "redbean" /MIN cmd /c "cd /d "%ROOT%" && "%REDBEAN%.exe" -p %PORT% -D "%ROOT%" -L "%LOG%" > "%LOG%" 2>&1"

echo  Loading redbean...
echo  Log: %LOG%
echo.

set /a "TRIES=0"
:wait
set /a "TRIES+=1"
timeout /t 1 >nul
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/health -TimeoutSec 2) | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  if %TRIES% GEQ 15 (
    echo  ERROR: redbean did not come up. See %LOG%
    pause
    endlocal & exit /b 1
  )
  goto wait
)

:open
echo  Server up. Opening browser at http://127.0.0.1:%PORT%/doom/ ...
start "" http://127.0.0.1:%PORT%/doom/

echo.
echo  ==============================================
echo   DOOM is running. Press any key to STOP.
echo  ==============================================
echo.
pause >nul

if "%STARTED_REDBEAN%"=="1" (
  taskkill /F /IM redbean.com >nul 2>&1
  taskkill /F /IM redbean.exe >nul 2>&1
  echo  Stopped redbean.
) else (
  echo  (Left existing redbean running.)
)
endlocal
exit /b 0
