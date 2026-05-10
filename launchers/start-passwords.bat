@echo off
REM KeePassXC launcher: opens the bundled KeePassXC GUI with the kit's password
REM database (passwords\vault.kdbx) if it exists. Lives at the USB root;
REM references ai-kit\keepassxc\ alongside.
setlocal
set "ROOT=%~dp0"
set "BINARY=%ROOT%ai-kit\keepassxc\win\KeePassXC.exe"

if not exist "%BINARY%" (
  echo.
  echo  ERROR: %BINARY% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

REM Pass the kit database as argv if it exists; otherwise KeePassXC shows its
REM built-in open-file dialog so the user can navigate to their own database.
set "DB="
if exist "%ROOT%passwords\vault.kdbx" set "DB=%ROOT%passwords\vault.kdbx"

cls
echo.
echo  ==============================================
echo       PASSWORDS - Doomstick - v0.11
echo  ==============================================
echo.
echo  Opening KeePassXC. The launcher window can be
echo  closed. KeePassXC runs independently.
echo.
echo  ==============================================
echo.

REM The empty title argument "" is required by start's syntax.
if defined DB (
  start "" "%BINARY%" "%DB%"
) else (
  start "" "%BINARY%"
)

endlocal & exit /b 0
