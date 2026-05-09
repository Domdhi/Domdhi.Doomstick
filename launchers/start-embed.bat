@echo off
REM EmbeddingGemma launcher: runs the 300M Q8 embedding model as an HTTP server
REM on :8769 using llamafile's --embedding mode. Exposes /v1/embeddings (OpenAI-
REM compat). Background service for /rag -- no browser UI. Lives at the USB root;
REM references ai-kit\runtime\ and ai-kit\models\ alongside.
setlocal
set "ROOT=%~dp0"
set "PORT=8769"
set "MODEL=embeddinggemma-300m-qat-Q8_0.gguf"
set "LOG=%ROOT%ai-kit\embed.log"

if not exist "%ROOT%ai-kit\runtime\llamafile.exe" (
  echo.
  echo  ERROR: ai-kit\runtime\llamafile.exe not found.
  echo         Run build-usb.ps1 against this stick first.
  pause
  exit /b 1
)

if not exist "%ROOT%ai-kit\models\%MODEL%" (
  echo.
  echo  ERROR: ai-kit\models\%MODEL% not found.
  echo         Run build-usb.ps1 against this stick first.
  pause
  exit /b 1
)

cls
echo.
echo  ==============================================
echo        EmbeddingGemma - Embedding Server
echo  ==============================================
echo.

REM Clean up any orphan embedding process from a previous run.
REM We target the model filename in the CommandLine rather than llamafile.exe
REM directly — killing llamafile.exe would also kill the main AI on port 8765
REM if it happens to be running.
wmic process where "CommandLine like '%%embeddinggemma%%'" delete >nul 2>&1

REM Preflight: only block if something is actively LISTENING on the port.
powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue; if ($c) { $p = Get-Process -Id $c[0].OwningProcess -ErrorAction SilentlyContinue; Write-Host ('  Port %PORT% is being held by PID ' + $c[0].OwningProcess + ' (' + $p.ProcessName + '.exe).') -ForegroundColor Red; Write-Host '  Close that app or edit this .bat to set PORT to a free port.' -ForegroundColor Red; exit 1 } else { exit 0 }"
if errorlevel 1 ( pause & endlocal & exit /b 1 )

REM Run llamafile minimized in --embedding mode, redirecting output to the log.
start "EmbeddingGemma" /MIN cmd /c ""%ROOT%ai-kit\runtime\llamafile.exe" -m "%ROOT%ai-kit\models\%MODEL%" --embedding --host 127.0.0.1 --port %PORT% > "%LOG%" 2>&1"

echo  Loading EmbeddingGemma (~5-15 seconds)...
echo  Log: %LOG%
echo.

set /a "TRIES=0"
:wait
set /a "TRIES+=1"
timeout /t 1 >nul
powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/ -TimeoutSec 2) | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  if %TRIES% GEQ 60 (
    echo  ERROR: embedding server did not come up. See %LOG%
    pause
    endlocal & exit /b 1
  )
  goto wait
)

echo  Server up at http://127.0.0.1:%PORT%
echo  Warming up model (forces full load before first RAG call)...

REM Warm-up: one embedding call so the model is fully in memory before /rag
REM hits it. Mitigates redbean's 30s Fetch() timeout on the first cold call.
REM If it fails, print a warning but continue -- server is still usable.
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:%PORT%/v1/embeddings -Method POST -ContentType 'application/json' -Body '{\"input\":\"warmup\"}' -TimeoutSec 30 | Out-Null; Write-Host '  Warm-up complete. Embedding server is ready.' } catch { Write-Host '  WARNING: warm-up call failed (first RAG ingest may be slow).' }"

echo.
echo  ==============================================
echo   Server:  http://127.0.0.1:%PORT%/v1/embeddings
echo   Log:     %LOG%
echo   Press any key to STOP.
echo  ==============================================
echo.
pause >nul

REM Kill by model name pattern again (same reason as above).
wmic process where "CommandLine like '%%embeddinggemma%%'" delete >nul 2>&1
endlocal
exit /b 0
