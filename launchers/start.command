#!/usr/bin/env bash
# Unified launcher: shows a menu, picks a model, runs it.
# Lives at the USB root; references ai-kit/runtime/ and ai-kit/models/ alongside.
# llamafile runs in the background; full output goes to ai-kit/llamafile-<model>.log.
# `sh` prefix avoids WSL's "APE is running on WIN32 inside WSL" interception.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PORT=8765

# Qwen3-4B is the FLUX.2 klein text encoder (--llm flag of sd-cli) AND a
# standalone AI core option. Runtime-detected so tiny/balanced bundles that
# skip image gen don't see a broken menu entry.
HAS_QWEN=0
[ -f "$ROOT/ai-kit/models/Qwen3-4B-Q4_K_M.gguf" ] && HAS_QWEN=1

while :; do
  clear
  echo
  echo "  =============================================="
  echo "           Portable Offline AI Kit"
  echo "  =============================================="
  echo
  echo "    Pick a model to load:"
  echo
  echo "    [1]  Gemma 4 E4B   --   5 GB    needs 8+ GB RAM"
  echo "    [2]  Gemma 4 26B   --  17 GB   needs 18+ GB RAM  (MoE, surprisingly fast)"
  if [ "$HAS_QWEN" = "1" ]; then
    echo "    [3]  Qwen3 4B      --  2.3 GB  needs 4+ GB RAM   (lightest, multilingual)"
    PROMPT_HINT="    Choose 1, 2 or 3 (or Ctrl-C to cancel): "
  else
    PROMPT_HINT="    Choose 1 or 2 (or Ctrl-C to cancel): "
  fi
  echo
  read -r -p "$PROMPT_HINT" CHOICE

  case "$CHOICE" in
    1)
      MODEL="gemma-4-E4B-it-Q4_K_M.gguf"
      LABEL="Gemma 4 E4B"
      WAIT_TRIES=45
      POLL_SEC=2
      LOAD_HINT="about 15-30 seconds"
      LOG="$ROOT/ai-kit/llamafile-e4b.log"
      break
      ;;
    2)
      MODEL="gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
      LABEL="Gemma 4 26B-A4B"
      WAIT_TRIES=60
      POLL_SEC=3
      LOAD_HINT="about 45-90 seconds"
      LOG="$ROOT/ai-kit/llamafile-26b.log"
      break
      ;;
    3)
      if [ "$HAS_QWEN" != "1" ]; then
        echo
        echo "    Invalid choice. Try again."
        sleep 1
        continue
      fi
      MODEL="Qwen3-4B-Q4_K_M.gguf"
      LABEL="Qwen3 4B"
      WAIT_TRIES=45
      POLL_SEC=2
      LOAD_HINT="about 15-30 seconds"
      LOG="$ROOT/ai-kit/llamafile-qwen3.log"
      break
      ;;
    *)
      echo
      echo "    Invalid choice. Try again."
      sleep 1
      ;;
  esac
done

clear
echo
echo "  =============================================="
echo "         $LABEL - Starting"
echo "  =============================================="
echo

pkill -f llamafile 2>/dev/null || true

if command -v ss >/dev/null 2>&1 && ss -lntH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "  Port $PORT is in use. Close whatever's on it,"
  echo "  or edit this script to set PORT to a free port."
  exit 1
fi

sh "$ROOT/ai-kit/runtime/llamafile" -m "$ROOT/ai-kit/models/$MODEL" \
  --server --host 127.0.0.1 --port "$PORT" -c 8192 > "$LOG" 2>&1 &
LLAMAPID=$!

echo "  Loading $LABEL from USB ($LOAD_HINT)..."
echo "  Log: $LOG"
echo

TRIES=0
while ! curl -sf -m 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; do
  sleep "$POLL_SEC"
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$WAIT_TRIES" ]; then
    echo "  ERROR: model did not come up in time."
    echo "         Open the log to see what went wrong: $LOG"
    kill "$LLAMAPID" 2>/dev/null || true
    exit 1
  fi
done

CHAT_PATH="$ROOT/chat/index.html"
if [ -f "$CHAT_PATH" ]; then
  echo "  Server up. Opening chat tab from $CHAT_PATH ..."
  xdg-open "$CHAT_PATH" 2>/dev/null || open "$CHAT_PATH" 2>/dev/null || true
else
  echo "  Server up. Chat tab missing — opening bare llamafile UI at http://127.0.0.1:$PORT ..."
  xdg-open "http://127.0.0.1:$PORT" 2>/dev/null || open "http://127.0.0.1:$PORT" 2>/dev/null || true
fi

echo
echo "  =============================================="
echo "   $LABEL is running."
echo "   Press Enter here to STOP the model."
echo "  =============================================="
echo
read -r _

kill "$LLAMAPID" 2>/dev/null || true
echo "  Stopped."
