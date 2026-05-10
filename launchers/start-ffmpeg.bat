@echo off
REM ffmpeg PATH-primer launcher: adds the bundled ffmpeg/ffprobe to PATH for
REM this cmd session, then opens an interactive cmd window with that PATH.
REM Lives at the USB root; references ai-kit\ffmpeg\ alongside.
setlocal
set "ROOT=%~dp0"
set "FFMPEG_DIR=%ROOT%ai-kit\ffmpeg\win"
set "FFMPEG_BIN=%FFMPEG_DIR%\ffmpeg.exe"

if not exist "%FFMPEG_BIN%" (
  echo.
  echo  ERROR: %FFMPEG_BIN% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

set "PATH=%FFMPEG_DIR%;%PATH%"

cls
echo.
echo  ==============================================
echo       FFMPEG SESSION - Doomstick - v0.11
echo  ==============================================
echo.
echo  ffmpeg and ffprobe are on PATH for this session.
echo.
echo  Examples:
echo    Audio extraction:            ffmpeg -i input.mp4 output.wav
echo    Whisperfile-format convert:  ffmpeg -i input.wav -ar 16000 -ac 1 out.wav
echo    Probe:                       ffprobe input.mp4
echo.
echo  Type 'exit' to close this session.
echo.

cmd /k
