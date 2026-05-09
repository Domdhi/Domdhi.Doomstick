#!/usr/bin/env bash
# Whisperfile launcher: runs whatever whisper-*.llamafile the build wizard
# staged into ai-kit/whisper/ (tiny.en / small.en / medium.en) as an HTTP
# server on :8766. Lives at the USB root; references ai-kit/whisper/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PORT=8766
WHISPER=""
for f in "$ROOT/ai-kit/whisper/"whisper-*.llamafile; do
  [ -f "$f" ] && WHISPER="$f" && break
done
LOG="$ROOT/ai-kit/whisper.log"

if [ -z "$WHISPER" ]; then
  echo "  ERROR: no whisper-*.llamafile found in $ROOT/ai-kit/whisper/."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi
WHISPER_NAME="$(basename "$WHISPER")"

clear
echo
echo "  =============================================="
echo "           Whisperfile - Audio to Text"
echo "  =============================================="
echo

pkill -f "$WHISPER_NAME" 2>/dev/null || true

if command -v ss >/dev/null 2>&1 && ss -lntH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "  Port $PORT is in use. Close the offending app and re-run."
  exit 1
fi

# `sh` prefix dodges WSL APE interception.
sh "$WHISPER" --host 127.0.0.1 --port "$PORT" > "$LOG" 2>&1 &
WPID=$!

echo "  Loading Whisperfile (~5 seconds)..."
echo "  Log: $LOG"
echo

TRIES=0
while ! curl -sf -m 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; do
  sleep 1
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 30 ]; then
    echo "  ERROR: whisperfile did not come up. See $LOG"
    kill "$WPID" 2>/dev/null || true
    exit 1
  fi
done

echo "  Server up. Opening browser at http://127.0.0.1:$PORT ..."
xdg-open "http://127.0.0.1:$PORT" 2>/dev/null || open "http://127.0.0.1:$PORT" 2>/dev/null || true

echo
echo "  =============================================="
echo "   Whisperfile is running. Press Enter to STOP."
echo "  =============================================="
echo
read -r _

kill "$WPID" 2>/dev/null || true
echo "  Stopped."
