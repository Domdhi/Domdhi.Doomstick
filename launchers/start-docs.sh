#!/usr/bin/env bash
# DevDocs launcher: opens the static offline DevDocs page.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PAGE="$ROOT/docs-offline/index.html"

if [ ! -f "$PAGE" ]; then
  echo "  ERROR: $PAGE not found."
  echo "         DevDocs is not auto-fetched by build-usb. See:"
  echo "         $ROOT/docs-offline/README.txt"
  echo "         (or repo: docs/setup-devdocs.md)"
  exit 1
fi

xdg-open "$PAGE" 2>/dev/null || open "$PAGE" 2>/dev/null || {
  echo "  Could not auto-open. Open this file in your browser:"
  echo "    $PAGE"
}
