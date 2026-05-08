#!/usr/bin/env bash
# Wiki launcher: serves any .zim file in zim/ via kiwix-serve on port 8767.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PORT=8767
ZIM_DIR="$ROOT/zim"
LOG="$ROOT/ai-kit/kiwix.log"

# Detect OS for the right kiwix-serve binary.
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="win" ;;
esac
KIWIX="$ROOT/ai-kit/kiwix/$OS/kiwix-serve"
[ "$OS" = "win" ] && KIWIX="$KIWIX.exe"

if [ ! -x "$KIWIX" ]; then
  echo "  ERROR: $KIWIX not found or not executable."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi

# Glob the ZIMs.
shopt -s nullglob
ZIMS=( "$ZIM_DIR"/*.zim )
shopt -u nullglob
if [ "${#ZIMS[@]}" -eq 0 ]; then
  echo "  No .zim files in $ZIM_DIR. Add a Wikipedia ZIM and re-run."
  exit 1
fi

clear
echo
echo "  =============================================="
echo "           Kiwix - Offline Wikipedia"
echo "  =============================================="
echo

pkill -f kiwix-serve 2>/dev/null || true

if command -v ss >/dev/null 2>&1 && ss -lntH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "  Port $PORT is in use."
  exit 1
fi

"$KIWIX" --port "$PORT" "${ZIMS[@]}" > "$LOG" 2>&1 &
KPID=$!

echo "  Starting kiwix-serve on port $PORT..."
echo "  Log: $LOG"

TRIES=0
while ! curl -sf -m 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; do
  sleep 1
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 15 ]; then
    echo "  ERROR: kiwix-serve did not come up. See $LOG"
    kill "$KPID" 2>/dev/null || true
    exit 1
  fi
done

echo "  Server up. Opening browser at http://127.0.0.1:$PORT ..."
xdg-open "http://127.0.0.1:$PORT" 2>/dev/null || open "http://127.0.0.1:$PORT" 2>/dev/null || true

echo
echo "  =============================================="
echo "   Kiwix is running. Press Enter to STOP."
echo "  =============================================="
read -r _

kill "$KPID" 2>/dev/null || true
echo "  Stopped."
