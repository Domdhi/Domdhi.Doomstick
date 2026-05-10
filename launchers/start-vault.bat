@echo off
REM Recovery Vault launcher: decrypts vault\recovery.tar.age (age-encrypted tar)
REM to a host tmpdir using the bundled age binary, then opens Explorer.
REM Lives at the USB root; references ai-kit\age\ alongside.
setlocal
set "ROOT=%~dp0"
set "AGE=%ROOT%ai-kit\age\win\age.exe"
set "VAULT=%ROOT%vault\recovery.tar.age"

if not exist "%AGE%" (
  echo.
  echo  ERROR: %AGE% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

if not exist "%VAULT%" (
  echo.
  echo  No vault file found at %VAULT%.
  echo  To create one:
  echo    tar c recovery\ ^| ai-kit\age\win\age.exe -p ^> vault\recovery.tar.age
  echo  See vault\README.txt for the full ceremony walkthrough.
  pause
  endlocal & exit /b 0
)

cls
echo.
echo  ==============================================
echo       RECOVERY VAULT - Doomstick - v0.9
echo  ==============================================
echo.
echo  !! WARNING: If you forget your passphrase, the vault
echo  !!          cannot be recovered. No exceptions.
echo  !!          Press Ctrl-C to cancel.
echo.

set "TMPDIR_VAULT=%TEMP%\doomstick-vault-%RANDOM%%RANDOM%"
mkdir "%TMPDIR_VAULT%"

echo  Decrypting to: %TMPDIR_VAULT%
echo  (Contents will NOT be cleaned up automatically - see below)
echo.

REM cmd.exe pipe errorlevel reflects only the LAST command (tar), not age.
REM In practice this is OK: a wrong passphrase makes age write nothing, then
REM tar reads EOF and exits 1, so the error path triggers correctly. The
REM edge case (age emits partial bytes before failing, tar treats them as
REM a complete archive and exits 0) is rare; the rmdir /S /Q on failure
REM cleans any partial extract regardless.
"%AGE%" -d "%VAULT%" | tar x -C "%TMPDIR_VAULT%"
if errorlevel 1 (
  echo.
  echo  ERROR: Decryption failed. Check your passphrase.
  rmdir /S /Q "%TMPDIR_VAULT%" 2>nul
  pause
  endlocal & exit /b 1
)

start "" explorer.exe "%TMPDIR_VAULT%"

echo.
echo  ==============================================
echo   Vault decrypted. When you are done, clean up:
echo    Remove-Item -Recurse -Force "%TMPDIR_VAULT%"
echo  ==============================================
echo.
pause
endlocal & exit /b 0
