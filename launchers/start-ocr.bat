@echo off
REM OCR launcher: opens the static OCR page. No server needed.
setlocal
set "ROOT=%~dp0"
set "PAGE=%ROOT%ocr\index.html"

if not exist "%PAGE%" (
  echo  ERROR: %PAGE% not found.
  echo         Run build-usb.ps1 against this stick first.
  pause
  exit /b 1
)

start "" "%PAGE%"
endlocal
exit /b 0
