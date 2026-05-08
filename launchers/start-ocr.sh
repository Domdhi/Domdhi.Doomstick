#!/usr/bin/env bash
# OCR launcher: opens the static OCR page. No server needed.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PAGE="$ROOT/ocr/index.html"

if [ ! -f "$PAGE" ]; then
  echo "  ERROR: $PAGE not found."
  echo "         Run ./build-usb.sh against this stick first."
  exit 1
fi

xdg-open "$PAGE" 2>/dev/null || open "$PAGE" 2>/dev/null || {
  echo "  Could not auto-open. Open this file in your browser:"
  echo "    $PAGE"
}
