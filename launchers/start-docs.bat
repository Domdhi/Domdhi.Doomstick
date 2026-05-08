@echo off
REM DevDocs launcher: opens the static offline DevDocs page.
setlocal
set "ROOT=%~dp0"
set "PAGE=%ROOT%docs-offline\index.html"

if not exist "%PAGE%" (
  echo  ERROR: %PAGE% not found.
  echo         DevDocs is not auto-fetched by build-usb. See:
  echo         %ROOT%docs-offline\README.txt
  echo         (or repo: docs/setup-devdocs.md)
  pause
  exit /b 1
)

start "" "%PAGE%"
endlocal
exit /b 0
