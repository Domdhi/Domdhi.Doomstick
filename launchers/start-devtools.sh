#!/usr/bin/env bash
# devtools PATH-primer launcher: adds ripgrep, fzf, jq, 7-Zip, and VSCodium to PATH
# for this terminal session, then hands control to the user's shell.
# Lives at the USB root; references ai-kit/devtools/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Detect OS for the right devtools binary directory.
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="win" ;;
esac
DEVTOOLS_DIR="$ROOT/ai-kit/devtools/$OS"
RG_BIN="$DEVTOOLS_DIR/rg"
[ "$OS" = "win" ] && RG_BIN="$DEVTOOLS_DIR/rg.exe"

if [ ! -f "$RG_BIN" ]; then
  echo "  ERROR: $RG_BIN not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

# macOS: create a codium symlink if VSCodium.app is present and symlink doesn't exist yet
if [ "$OS" = "mac" ]; then
  CODIUM_APP="$DEVTOOLS_DIR/vscode/VSCodium.app/Contents/MacOS/codium"
  CODIUM_LINK="$DEVTOOLS_DIR/vscode/codium"
  if [ -f "$CODIUM_APP" ] && [ ! -f "$CODIUM_LINK" ]; then
    ln -sf "$CODIUM_APP" "$CODIUM_LINK" 2>/dev/null || true
  fi
fi

export PATH="$DEVTOOLS_DIR:$DEVTOOLS_DIR/vscode:$PATH"

clear
echo
echo "  ================================================"
echo "       DEV TOOLS SESSION — Doomstick · v0.12"
echo "  ================================================"
echo
echo "  ripgrep, fzf, jq, 7-Zip, and VSCodium (codium)"
echo "  are on PATH for this session."
echo
echo "  Examples:"
echo "    Recursive search:   rg 'pattern' ."
echo "    Fuzzy file picker:  fzf"
echo "    JSON field:         jq '.field' data.json"
echo "    Extract archive:    7zzs x archive.7z      (Linux; 7zz on macOS)"
echo "    Open editor:        codium ."
echo
echo "  Type 'exit' to close this session."
echo

exec "${SHELL:-/bin/bash}"
