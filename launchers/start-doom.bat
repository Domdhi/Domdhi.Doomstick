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
  echo  WARNING: doom1.wad not present - game will fail to load.
  echo           Re-run build-usb.ps1 to fetch the shareware WAD.
  echo.
)

cls
echo.
echo  ==============================================
echo          DOOM - Doomstick - v0.5
echo  ==============================================
echo.

REM Reuse an existing redbean if it's already serving /health.
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/health -TimeoutSec 1) | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
  echo  redbean already running on %PORT% - reusing.
  set "STARTED_REDBEAN=0"
  goto open
)
set "STARTED_REDBEAN=1"

REM Clean any orphan redbean from a previous run.
taskkill /F /IM redbean.com >nul 2>&1
taskkill /F /IM redbean.exe >nul 2>&1

REM Windows refuses to launch a .com directly in some shells; copy to .exe at first run.
if not exist "%REDBEAN%.exe" copy /Y "%REDBEAN%" "%REDBEAN%.exe" >nul

REM .init.lua + doom/* are baked into redbean.com's appended zip by build-usb --
REM no per-launch staging needed. cd /d %ROOT% so saves.db lands at
REM ai-kit\redbean\saves.db (relative to redbean's CWD).
REM
REM Why -D points at an empty webroot, not the USB root: even without -D,
REM redbean uses the CWD as an implicit docroot. On exFAT, native Cosmopolitan
REM stat() reports files/dirs with mode 0700/0600 (no group/other bits), which
REM fails redbean's static-serve "other readable" check -> 403 on any on-disk
REM asset (/doom/index.html, etc.). Pointing -D at an empty subdirectory
REM makes redbean find no on-disk match and fall through to the appended-zip
REM lookup (which has no permission check). The launcher opens
REM /doom/index.html directly because zip-only mode does not auto-resolve
REM trailing-slash to index.html.
if not exist "%ROOT%ai-kit\redbean\webroot" mkdir "%ROOT%ai-kit\redbean\webroot" >nul 2>&1
start "redbean" /MIN cmd /c "cd /d "%ROOT%" && "%REDBEAN%.exe" -p %PORT% -D "%ROOT%ai-kit\redbean\webroot" -L "%LOG%" > "%LOG%" 2>&1"

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
echo  Server up. Opening browser at http://127.0.0.1:%PORT%/doom/index.html ...
start "" http://127.0.0.1:%PORT%/doom/index.html

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
