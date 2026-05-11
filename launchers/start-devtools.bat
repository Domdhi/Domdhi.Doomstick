@echo off
setlocal

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DEVTOOLS_DIR=%ROOT%\ai-kit\devtools\win"

if not exist "%DEVTOOLS_DIR%\rg.exe" (
    echo   ERROR: %DEVTOOLS_DIR%\rg.exe not found.
    echo   Run build-usb.ps1 against this stick first.
    pause
    endlocal & exit /b 1
)

set "PATH=%DEVTOOLS_DIR%;%DEVTOOLS_DIR%\vscode;%PATH%"

cls
echo.
echo   ================================================
echo        DEV TOOLS SESSION — Doomstick · v0.12
echo   ================================================
echo.
echo   ripgrep, fzf, jq, 7-Zip, and VSCodium (codium)
echo   are on PATH for this session.
echo.
echo   Examples:
echo     Recursive search:   rg "pattern" .
echo     Fuzzy file picker:  fzf
echo     JSON field:         jq ".field" data.json
echo     Extract archive:    7za x archive.7z
echo     Open editor:        codium .
echo.
echo   Type 'exit' to close this session.
echo.

cmd /k
endlocal
