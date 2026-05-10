#!/usr/bin/env bash
# KeePassXC launcher: opens the bundled KeePassXC GUI with the kit's password
# database (passwords/vault.kdbx) if it exists. Lives at the USB root;
# references ai-kit/keepassxc/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Detect OS for the right KeePassXC binary.
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="win" ;;
esac

BINARY=""

case "$OS" in
  linux)
    # Primary path: extracted binary (present after first-run extraction, or
    # when the USB was built on Linux/WSL which lands the binary directly).
    PRIMARY="$ROOT/ai-kit/keepassxc/linux/keepassxc"
    if [ -f "$PRIMARY" ]; then
      BINARY="$PRIMARY"
    else
      # Fallback: raw AppImage (shipped when the USB was built on Windows, which
      # cannot extract the AppImage at build time). On first launch we extract it
      # in place so subsequent runs use the primary path above and skip this block.
      APPIMAGE="$(ls "$ROOT/ai-kit/keepassxc/linux/"KeePassXC*.AppImage 2>/dev/null | head -1)"
      if [ -n "$APPIMAGE" ] && [ -f "$APPIMAGE" ]; then
        echo "  First-run: extracting AppImage to permanent binary..."
        chmod +x "$APPIMAGE"
        # Run extraction inside the linux/ directory so squashfs-root lands there.
        (cd "$ROOT/ai-kit/keepassxc/linux" && "$APPIMAGE" --appimage-extract) 2>/dev/null
        SQUASH="$ROOT/ai-kit/keepassxc/linux/squashfs-root"
        if [ -f "$SQUASH/usr/bin/keepassxc" ]; then
          mv "$SQUASH/usr/bin/keepassxc" "$ROOT/ai-kit/keepassxc/linux/keepassxc"
          [ -d "$SQUASH/usr/share" ] && mv "$SQUASH/usr/share" "$ROOT/ai-kit/keepassxc/linux/share"
          rm -f "$APPIMAGE"
          rm -rf "$SQUASH"
          BINARY="$ROOT/ai-kit/keepassxc/linux/keepassxc"
          echo "  Extraction complete."
        else
          echo "  ERROR: AppImage extraction did not produce expected binary."
          rm -rf "$SQUASH" 2>/dev/null
          exit 1
        fi
      fi
    fi
    ;;
  mac)
    # Primary path: extracted .app (present after first-run mount, or when the
    # USB was built on macOS which lands KeePassXC.app directly).
    APP="$ROOT/ai-kit/keepassxc/mac/KeePassXC.app"
    PRIMARY="$APP/Contents/MacOS/KeePassXC"
    if [ -f "$PRIMARY" ]; then
      BINARY="$PRIMARY"
    else
      # Fallback: raw .dmg (shipped when the USB was built on Windows or Linux,
      # which cannot mount the .dmg at build time). Mount, copy, and eject on
      # first launch so subsequent runs use the .app directly.
      DMG="$ROOT/ai-kit/keepassxc/mac/KeePassXC-2.7.12-arm64.dmg"
      if [ -f "$DMG" ]; then
        echo "  First-run: mounting DMG and extracting KeePassXC.app..."
        hdiutil attach "$DMG" -quiet
        if [ -d "/Volumes/KeePassXC/KeePassXC.app" ]; then
          cp -R "/Volumes/KeePassXC/KeePassXC.app" "$ROOT/ai-kit/keepassxc/mac/"
          xattr -dr com.apple.quarantine "$ROOT/ai-kit/keepassxc/mac/KeePassXC.app"
          hdiutil detach /Volumes/KeePassXC -quiet
          BINARY="$ROOT/ai-kit/keepassxc/mac/KeePassXC.app/Contents/MacOS/KeePassXC"
          echo "  Extraction complete."
        else
          hdiutil detach /Volumes/KeePassXC -quiet 2>/dev/null
          echo "  ERROR: KeePassXC.app not found in mounted DMG."
          exit 1
        fi
      fi
    fi
    ;;
  win)
    # Windows path: binary landed directly by build script; no extraction needed.
    BINARY="$ROOT/ai-kit/keepassxc/win/KeePassXC.exe"
    ;;
esac

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
  echo "  ERROR: KeePassXC binary not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

# Pass the kit database as argv if it exists; otherwise KeePassXC shows its
# built-in open-file dialog so the user can navigate to their own database.
DB=""
if [ -f "$ROOT/passwords/vault.kdbx" ]; then
  DB="$ROOT/passwords/vault.kdbx"
fi

clear
echo
echo "  =============================================="
echo "       PASSWORDS — Doomstick · v0.11"
echo "  =============================================="
echo
echo "  Opening KeePassXC. The launcher window can be"
echo "  closed. KeePassXC runs independently."
echo
echo "  =============================================="
echo

"$BINARY" ${DB:+"$DB"} &
disown
