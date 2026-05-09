@echo off
REM Whisperfile launcher: runs whatever whisper-*.llamafile the build wizard
REM staged into ai-kit\whisper\ (tiny.en / small.en / medium.en) as an HTTP
REM server on :8766. Lives at the USB root; references ai-kit\whisper\ alongside.
setlocal
set "ROOT=%~dp0"
set "PORT=8766"
set "WHISPER="
set "WHISPER_NAME="
for %%F in ("%ROOT%ai-kit\whisper\whisper-*.llamafile") do (
  if not defined WHISPER (
    set "WHISPER=%%~fF"
    set "WHISPER_NAME=%%~nxF"
  )
)
set "LOG=%ROOT%ai-kit\whisper.log"

if not defined WHISPER (
  echo.
  echo  ERROR: no whisper-*.llamafile found in %ROOT%ai-kit\whisper\.
  echo         Run build-usb.ps1 against this stick first.
  pause
  exit /b 1
)

cls
echo.
echo  ==============================================
echo            Whisperfile - Audio to Text
echo  ==============================================
echo.

REM Clean any orphan whisperfile from a previous run.
taskkill /F /IM "%WHISPER_NAME%.exe" >nul 2>&1
taskkill /F /IM whisperfile.exe >nul 2>&1

REM Whisperfile registers as a .llamafile so it runs as an APE polyglot.
REM Windows refuses to launch a .llamafile by name, so call the shipped
REM cosmocc loader by renaming a copy to .exe at first run.
if not exist "%WHISPER%.exe" copy /Y "%WHISPER%" "%WHISPER%.exe" >nul

start "Whisperfile" /MIN cmd /c ""%WHISPER%.exe" --host 127.0.0.1 --port %PORT% > "%LOG%" 2>&1"

echo  Loading Whisperfile (~5 seconds)...
echo  Log: %LOG%
echo.

set /a "TRIES=0"
:wait
set /a "TRIES+=1"
timeout /t 1 >nul
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/ -TimeoutSec 2) | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  if %TRIES% GEQ 30 (
    echo  ERROR: whisperfile did not come up. See %LOG%
    pause
    endlocal & exit /b 1
  )
  goto wait
)

echo  Server up. Opening browser at http://127.0.0.1:%PORT% ...
start "" http://127.0.0.1:%PORT%

echo.
echo  ==============================================
echo   Whisperfile is running. Press any key to STOP.
echo  ==============================================
echo.
pause >nul

taskkill /F /IM "%WHISPER_NAME%.exe" >nul 2>&1
taskkill /F /IM whisperfile.exe >nul 2>&1
endlocal
exit /b 0
