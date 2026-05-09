#!/usr/bin/env bash
# EmbeddingGemma launcher: runs the 300M Q8 embedding model as an HTTP server
# on :8769 using llamafile's --embedding mode. Exposes /v1/embeddings (OpenAI-
# compat). Background service for /rag — no browser UI. Lives at the USB root;
# references ai-kit/runtime/ and ai-kit/models/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PORT=8769
MODEL="embeddinggemma-300m-qat-Q8_0.gguf"
LOG="$ROOT/ai-kit/embed.log"

if [ ! -f "$ROOT/ai-kit/runtime/llamafile" ]; then
  echo "  ERROR: ai-kit/runtime/llamafile not found."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi

if [ ! -f "$ROOT/ai-kit/models/$MODEL" ]; then
  echo "  ERROR: ai-kit/models/$MODEL not found."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi

clear
echo
echo "  =============================================="
echo "        EmbeddingGemma - Embedding Server"
echo "  =============================================="
echo

# Clean up any orphan from a previous run. Target the model name, NOT llamafile
# — pkill -f llamafile would kill the main AI on port 8765.
pkill -f "embeddinggemma" 2>/dev/null || true

if command -v ss >/dev/null 2>&1 && ss -lntH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "  Port $PORT is in use. Close the offending app and re-run."
  exit 1
fi

# `sh` prefix dodges WSL APE interception (see CLAUDE.md "WSL intercepts APE binaries").
sh "$ROOT/ai-kit/runtime/llamafile" \
  -m "$ROOT/ai-kit/models/$MODEL" \
  --embedding \
  --host 127.0.0.1 \
  --port "$PORT" \
  > "$LOG" 2>&1 &
EPID=$!

echo "  Loading EmbeddingGemma (~5-15 seconds)..."
echo "  Log: $LOG"
echo

TRIES=0
while ! curl -sf -m 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; do
  sleep 1
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 60 ]; then
    echo "  ERROR: embedding server did not come up. See $LOG"
    kill "$EPID" 2>/dev/null || true
    exit 1
  fi
done

echo "  Server up at http://127.0.0.1:$PORT"
echo "  Warming up model (forces full load before first RAG call)..."

# Warm-up: one embedding call so the model is fully in memory before /rag hits
# it. Mitigates redbean's 30s Fetch() timeout on the first cold inference.
# If the warm-up fails, print a warning but continue — server is still usable.
if ! curl -sf -m 30 -X POST "http://127.0.0.1:$PORT/v1/embeddings" \
     -H 'Content-Type: application/json' \
     -d '{"input":"warmup"}' > /dev/null 2>&1; then
  echo "  WARNING: warm-up call failed (first RAG ingest may be slow). See $LOG"
else
  echo "  Warm-up complete. Embedding server is ready."
fi

echo
echo "  =============================================="
echo "   Server:  http://127.0.0.1:$PORT/v1/embeddings"
echo "   Log:     $LOG"
echo "   Press Enter to STOP."
echo "  =============================================="
echo
read -r _

kill "$EPID" 2>/dev/null || true
echo "  Stopped."
