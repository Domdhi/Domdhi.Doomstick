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

rem --- PortableGit first-run extraction ---
if not exist "%DEVTOOLS_DIR%\git\cmd\git.exe" (
    if exist "%DEVTOOLS_DIR%\PortableGit.7z.exe" (
        echo   First run: extracting PortableGit -- this takes about 30 seconds...
        "%DEVTOOLS_DIR%\PortableGit.7z.exe" -y -o"%DEVTOOLS_DIR%\git\"
        echo   Git ready.
    )
)

set "PATH=%DEVTOOLS_DIR%;%DEVTOOLS_DIR%\vscode;%DEVTOOLS_DIR%\git\cmd;%PATH%"

cls
echo.
echo   ================================================
echo        DEV TOOLS SESSION -- Doomstick v0.12
echo   ================================================
echo.
echo   ripgrep, fzf, jq, 7-Zip, VSCodium (codium),
echo   and git are on PATH for this session.
echo.
echo   Examples:
echo     Recursive search:   rg "pattern" .
echo     Fuzzy file picker:  fzf
echo     JSON field:         jq ".field" data.json
echo     Extract archive:    7za x archive.7z
echo     Open editor:        codium .
echo     Git clone:          git clone https://...
echo.
echo   Type 'exit' to close this session.
echo.

cmd /k
endlocal
