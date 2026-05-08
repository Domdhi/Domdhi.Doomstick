@echo off
REM Wiki launcher: serves any .zim file in zim\ via kiwix-serve on port 8767.
setlocal enabledelayedexpansion
set "ROOT=%~dp0"
set "PORT=8767"
set "KIWIX=%ROOT%ai-kit\kiwix\win\kiwix-serve.exe"
set "ZIM=%ROOT%zim"
set "LOG=%ROOT%ai-kit\kiwix.log"

if not exist "%KIWIX%" (
  echo  ERROR: %KIWIX% not found.
  echo         Run build-usb.ps1 against this stick first.
  pause
  exit /b 1
)

REM Build a list of .zim files. kiwix-serve takes them as positional args.
set "ZIMS="
for %%F in ("%ZIM%\*.zim") do set "ZIMS=!ZIMS! "%%F""

if "!ZIMS!"=="" (
  echo  No .zim files in %ZIM%. Add a Wikipedia ZIM and re-run.
  pause
  endlocal & exit /b 1
)

cls
echo.
echo  ==============================================
echo            Kiwix - Offline Wikipedia
echo  ==============================================
echo.

taskkill /F /IM kiwix-serve.exe >nul 2>&1

powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue; if ($c) { Write-Host '  Port %PORT% is in use. Close the offending app and re-run.' -ForegroundColor Red; exit 1 } else { exit 0 }"
if errorlevel 1 ( pause & endlocal & exit /b 1 )

start "Kiwix" /MIN cmd /c ""%KIWIX%" --port %PORT% !ZIMS! > "%LOG%" 2>&1"

echo  Starting kiwix-serve on port %PORT%...
echo  Log: %LOG%

set /a "TRIES=0"
:wait
set /a "TRIES+=1"
timeout /t 1 >nul
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/ -TimeoutSec 2) | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  if %TRIES% GEQ 15 (
    echo  ERROR: kiwix-serve did not come up. See %LOG%
    pause
    endlocal & exit /b 1
  )
  goto wait
)

echo  Server up. Opening browser at http://127.0.0.1:%PORT% ...
start "" http://127.0.0.1:%PORT%

echo.
echo  ==============================================
echo   Kiwix is running. Press any key to STOP.
echo  ==============================================
pause >nul

taskkill /F /IM kiwix-serve.exe >nul 2>&1
endlocal
exit /b 0
