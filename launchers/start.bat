@echo off
REM Unified launcher: shows a menu, picks a model, runs it.
REM Lives at the USB root; references ai-kit\runtime\ and ai-kit\models\ alongside.
REM llamafile runs minimized; full output goes to ai-kit\llamafile-<model>.log.
setlocal
set "ROOT=%~dp0"
set "PORT=8765"

:menu
cls
echo.
echo  ==============================================
echo           Portable Offline AI Kit
echo  ==============================================
echo.
echo    Pick a model to load:
echo.
echo    [1]  Gemma 4 E4B   --   5 GB    needs 8+ GB RAM
echo    [2]  Gemma 4 26B   --  17 GB   needs 18+ GB RAM  (MoE, surprisingly fast)
echo.
set "CHOICE="
set /p "CHOICE=    Choose 1 or 2 (or close this window to cancel): "

if "%CHOICE%"=="1" (
  set "MODEL=gemma-4-E4B-it-Q4_K_M.gguf"
  set "LABEL=Gemma 4 E4B"
  set "WAIT_TRIES=45"
  set "POLL_SEC=2"
  set "LOAD_HINT=about 15-30 seconds"
  set "LOG=%ROOT%ai-kit\llamafile-e4b.log"
  goto run
)
if "%CHOICE%"=="2" (
  set "MODEL=gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
  set "LABEL=Gemma 4 26B-A4B"
  set "WAIT_TRIES=60"
  set "POLL_SEC=3"
  set "LOAD_HINT=about 45-90 seconds"
  set "LOG=%ROOT%ai-kit\llamafile-26b.log"
  goto run
)
echo.
echo    Invalid choice. Try again.
timeout /t 2 >nul
goto menu

:run
cls
echo.
echo  ==============================================
echo          %LABEL% - Starting
echo  ==============================================
echo.

REM Clean up any orphan llamafile.exe from a previous run.
taskkill /F /IM llamafile.exe >nul 2>&1

REM Preflight: only block if something is actively LISTENING on the port.
REM TIME_WAIT and other transient states are ignored -- they don't block bind().
powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue; if ($c) { $p = Get-Process -Id $c[0].OwningProcess -ErrorAction SilentlyContinue; Write-Host ('  Port %PORT% is being held by PID ' + $c[0].OwningProcess + ' (' + $p.ProcessName + '.exe).') -ForegroundColor Red; Write-Host '  Close that app or edit this .bat to set PORT to a free port.' -ForegroundColor Red; exit 1 } else { exit 0 }"
if errorlevel 1 ( pause & endlocal & exit /b 1 )

REM Run llamafile minimized, redirecting stdout+stderr to the log file.
start "%LABEL%" /MIN cmd /c ""%ROOT%ai-kit\runtime\llamafile.exe" -m "%ROOT%ai-kit\models\%MODEL%" --server --host 127.0.0.1 --port %PORT% -c 8192 > "%LOG%" 2>&1"

echo  Loading %LABEL% from USB (%LOAD_HINT%)...
echo  Log file: %LOG%
echo.

set /a "TRIES=0"
:wait
set /a "TRIES+=1"
timeout /t %POLL_SEC% >nul
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/ -TimeoutSec 2) | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  if %TRIES% GEQ %WAIT_TRIES% (
    echo.
    echo  ERROR: model did not come up in time.
    echo         Open the log to see what went wrong:
    echo         %LOG%
    echo.
    pause
    endlocal & exit /b 1
  )
  goto wait
)

if exist "%ROOT%chat\index.html" (
  echo  Server up. Opening chat tab from %ROOT%chat\index.html ...
  start "" "%ROOT%chat\index.html"
) else (
  echo  Server up. Chat tab missing -- opening bare llamafile UI at http://127.0.0.1:%PORT% ...
  start "" http://127.0.0.1:%PORT%
)

echo.
echo  ==============================================
echo   %LABEL% is running.
echo   Press any key here to STOP the model.
echo  ==============================================
echo.
pause >nul

echo  Stopping...
taskkill /F /IM llamafile.exe >nul 2>&1
endlocal
exit /b 0
