#!/usr/bin/env bash
# Recovery Vault launcher: decrypts vault/recovery.tar.age (age-encrypted tar)
# to a host tmpdir using the bundled age binary, then opens the file manager.
# Lives at the USB root; references ai-kit/age/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VAULT="$ROOT/vault/recovery.tar.age"

# Detect OS for the right age binary.
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="win" ;;
esac
AGE="$ROOT/ai-kit/age/$OS/age"
[ "$OS" = "win" ] && AGE="$AGE.exe"

if [ ! -f "$AGE" ]; then
  echo "  ERROR: $AGE not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

if [ ! -f "$VAULT" ]; then
  echo "  No vault file found at $VAULT."
  echo "  To create one:"
  echo "    tar c recovery/ | \"$AGE\" -p > \"$VAULT\""
  echo "  See vault/README.txt for the full ceremony walkthrough."
  exit 0
fi

clear
echo
echo "  =============================================="
echo "       RECOVERY VAULT — Doomstick · v0.9"
echo "  =============================================="
echo
echo "  !! WARNING: If you forget your passphrase, the vault"
echo "  !!          cannot be recovered. No exceptions."
echo "  !!          Press Ctrl-C to cancel."
echo

TMPDIR_VAULT="$(mktemp -d -t doomstick-vault-XXXXXX)"
echo "  Decrypting to: $TMPDIR_VAULT"
echo "  (Contents will NOT be cleaned up automatically — see below)"
echo

"$AGE" -d "$VAULT" | tar x -C "$TMPDIR_VAULT"
if [ ${PIPESTATUS[0]} -ne 0 ] || [ ${PIPESTATUS[1]} -ne 0 ]; then
  echo "  ERROR: Decryption failed. Check your passphrase."
  # rm -rf (not rmdir) — age may emit partial bytes before failing, leaving
  # partial extracts in the tmpdir. rmdir would silently fail on non-empty.
  rm -rf "$TMPDIR_VAULT" 2>/dev/null
  exit 1
fi

case "$OS" in
  linux) xdg-open "$TMPDIR_VAULT" 2>/dev/null & ;;
  mac)   open "$TMPDIR_VAULT" 2>/dev/null & ;;
esac

echo
echo "  =============================================="
echo "   Vault decrypted. When you are done, clean up:"
echo "   rm -rf $TMPDIR_VAULT"
echo "  =============================================="
echo
