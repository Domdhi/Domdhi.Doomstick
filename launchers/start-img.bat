@echo off
REM Image gen launcher: invokes stable-diffusion.cpp CLI with FLUX.2 klein 4B
REM transformer + Qwen3-4B text encoder + small-decoder VAE to generate a
REM 1024x1024 PNG from a user prompt. Lives at the USB root; references
REM ai-kit\sd-img\ + ai-kit\models\ alongside.
setlocal
set "ROOT=%~dp0"
set "SD_CLI=%ROOT%ai-kit\sd-img\win\sd-cli.exe"
set "SD_MODEL=%ROOT%ai-kit\sd-img\models\flux-2-klein-4b-Q4_K_M.gguf"
set "SD_VAE=%ROOT%ai-kit\sd-img\models\full_encoder_small_decoder.safetensors"
set "SD_LLM=%ROOT%ai-kit\models\Qwen3-4B-Q4_K_M.gguf"

if not exist "%SD_CLI%" (
  echo.
  echo  ERROR: %SD_CLI% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

if not exist "%SD_MODEL%" (
  echo.
  echo  ERROR: %SD_MODEL% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

if not exist "%SD_VAE%" (
  echo.
  echo  ERROR: %SD_VAE% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

if not exist "%SD_LLM%" (
  echo.
  echo  ERROR: %SD_LLM% not found. Run build-usb.ps1 against this stick first.
  pause
  endlocal & exit /b 1
)

cls
echo.
echo  ==============================================
echo       IMAGE GEN - Doomstick - v0.10
echo  ==============================================
echo.
echo  Image gen takes 1-3 minutes on CPU.
echo  Needs ~8-10 GB working RAM - close other apps if low on memory.
echo  Press Ctrl-C to cancel.
echo.

set "PROMPT="
set /p PROMPT="Prompt: "
if "%PROMPT%"=="" (
  echo  No prompt entered. Aborting.
  pause
  endlocal & exit /b 1
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%i"
set "OUT_PNG=%ROOT%img-out-%TS%.png"

"%SD_CLI%" --diffusion-model "%SD_MODEL%" --vae "%SD_VAE%" --llm "%SD_LLM%" ^
  -p "%PROMPT%" -H 1024 -W 1024 ^
  --steps 4 --cfg-scale 1.0 --sampling-method euler ^
  --diffusion-fa --offload-to-cpu ^
  -o "%OUT_PNG%"
if errorlevel 1 (
  echo.
  echo  Image generation failed. See output above for details.
  pause
  endlocal & exit /b 1
)

echo.
echo  Image written to: %OUT_PNG%
start "" "%OUT_PNG%"

pause
endlocal & exit /b 0
