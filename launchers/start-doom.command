#!/usr/bin/env bash
# DOOM launcher (macOS .command shim) — same logic as start-doom.sh.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PORT=8768
REDBEAN="$ROOT/ai-kit/redbean/redbean.com"
DOOM_DIR="$ROOT/doom"
LOG="$ROOT/ai-kit/redbean.log"

if [ ! -f "$REDBEAN" ]; then
  echo "  ERROR: $REDBEAN not found."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi
if [ ! -f "$DOOM_DIR/index.html" ]; then
  echo "  ERROR: $DOOM_DIR/index.html not found."
  exit 1
fi
if [ ! -f "$DOOM_DIR/doom1.wad" ]; then
  echo "  WARNING: doom1.wad not present — game will fail to load."
fi

clear
echo
echo "  =============================================="
echo "          DOOM — Doomstick · v0.5"
echo "  =============================================="
echo

# Strip macOS quarantine xattr from redbean on first launch.
xattr -d com.apple.quarantine "$REDBEAN" 2>/dev/null || true

if curl -sf -m 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "  redbean already running on $PORT — reusing."
  RPID=""
else
  pkill -f "redbean.com" 2>/dev/null || true
  # .init.lua is baked into redbean.com's appended zip by build-usb.sh —
  # no per-launch staging needed. cd $ROOT so saves.db lands at
  # ai-kit/redbean/saves.db (relative to redbean's CWD).
  ( cd "$ROOT" && "$REDBEAN" -p "$PORT" -D "$ROOT" -L "$LOG" > "$LOG" 2>&1 ) &
  RPID=$!

  echo "  Loading redbean..."
  echo "  Log: $LOG"

  TRIES=0
  while ! curl -sf -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; do
    sleep 1
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge 15 ]; then
      echo "  ERROR: redbean did not come up. See $LOG"
      kill "$RPID" 2>/dev/null || true
      exit 1
    fi
  done
fi

URL="http://127.0.0.1:$PORT/doom/"
echo "  Server up. Opening browser at $URL ..."
open "$URL" 2>/dev/null || true

echo
echo "  =============================================="
echo "   DOOM is running. Press Enter to STOP."
echo "  =============================================="
read -r _

if [ -n "$RPID" ]; then
  kill "$RPID" 2>/dev/null || true
  echo "  Stopped redbean."
else
  echo "  (Left existing redbean running — another tool may be using it.)"
fi
