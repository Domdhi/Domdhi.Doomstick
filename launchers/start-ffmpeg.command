#!/usr/bin/env bash
# ffmpeg PATH-primer launcher: adds the bundled ffmpeg/ffprobe to PATH for
# this terminal session, then hands control to the user's shell.
# Lives at the USB root; references ai-kit/ffmpeg/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Detect OS for the right ffmpeg binary directory.
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="win" ;;
esac
FFMPEG_DIR="$ROOT/ai-kit/ffmpeg/$OS"
FFMPEG_BIN="$FFMPEG_DIR/ffmpeg"
[ "$OS" = "win" ] && FFMPEG_BIN="$FFMPEG_DIR/ffmpeg.exe"

if [ ! -f "$FFMPEG_BIN" ]; then
  echo "  ERROR: $FFMPEG_BIN not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

export PATH="$FFMPEG_DIR:$PATH"

clear
echo
echo "  =============================================="
echo "       FFMPEG SESSION — Doomstick · v0.11"
echo "  =============================================="
echo
echo "  ffmpeg and ffprobe are on PATH for this session."
echo
echo "  Examples:"
echo "    Audio extraction:            ffmpeg -i input.mp4 output.wav"
echo "    Whisperfile-format convert:  ffmpeg -i input.wav -ar 16000 -ac 1 out.wav"
echo "    Probe:                       ffprobe input.mp4"
echo
echo "  Type 'exit' to close this session."
echo

exec "${SHELL:-/bin/bash}"
