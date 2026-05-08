#!/usr/bin/env bash
# Whisperfile launcher: runs whisper-base.en.llamafile in --gui mode.
# Lives at the USB root; references ai-kit/whisper/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PORT=8766
WHISPER="$ROOT/ai-kit/whisper/whisper-base.en.llamafile"
LOG="$ROOT/ai-kit/whisper.log"

if [ ! -f "$WHISPER" ]; then
  echo "  ERROR: $WHISPER not found."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi

clear
echo
echo "  =============================================="
echo "           Whisperfile - Audio to Text"
echo "  =============================================="
echo

pkill -f whisper-base.en.llamafile 2>/dev/null || true

if command -v ss >/dev/null 2>&1 && ss -lntH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "  Port $PORT is in use. Close the offending app and re-run."
  exit 1
fi

# `sh` prefix dodges WSL APE interception.
sh "$WHISPER" --host 127.0.0.1 --port "$PORT" --gui > "$LOG" 2>&1 &
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
