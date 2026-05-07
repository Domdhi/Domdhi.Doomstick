#!/usr/bin/env bash
# build-usb.sh — fetch the runtime + GGUFs and assemble the kit on a target dir.
#
# Usage:
#   ./build-usb.sh <target-dir>            e.g. /mnt/usb, /Volumes/USB, ./usb-layout
#
# Resumable: re-running skips files whose size already matches the expected size.
# Doesn't check signatures or hashes — for an air-gapped build, mirror the
# upstream URLs locally and edit the URL constants below.

set -euo pipefail

# ---------------------------------------------------------------- args + paths

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<EOF
Usage: $0 <target-dir>

Examples:
  $0 /mnt/usb            Linux: copy onto a mounted USB
  $0 /Volumes/USB        macOS: copy onto a mounted USB
  $0 ./usb-layout        Local dry-run: populate the in-repo skeleton

The script downloads ~22 GB total (43 MB runtime + 5 GB + 17 GB + 329 MB).
A re-run skips files that already exist with the right size.
EOF
  exit 0
fi

TARGET="$1"
REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

mkdir -p "$TARGET/ai-kit/runtime" "$TARGET/ai-kit/models"

# ---------------------------------------------------------------- constants

LLAMAFILE_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.1/llamafile-0.10.1-thin"
LLAMAFILE_BYTES=43800000      # ~43 MB; loose check, see verify_size below

E4B_URL="https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true"
E4B_FILE="gemma-4-E4B-it-Q4_K_M.gguf"
E4B_BYTES=5000000000          # ~5.0 GB

MOE_URL="https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf?download=true"
MOE_FILE="gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
MOE_BYTES=17000000000         # ~17 GB

EMB_URL="https://huggingface.co/ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/resolve/main/embeddinggemma-300m-qat-Q8_0.gguf?download=true"
EMB_FILE="embeddinggemma-300m-qat-Q8_0.gguf"
EMB_BYTES=329000000           # ~329 MB

# ---------------------------------------------------------------- helpers

# True if the file exists and is at least 95% of the expected byte count.
# We use a loose lower bound because Hugging Face occasionally changes file
# sizes for the same shard name when re-quantizing; an exact equality check
# would force an unnecessary re-download every time.
verify_size() {
  local path="$1"
  local expected="$2"
  [ -f "$path" ] || return 1
  local actual
  actual=$(stat -c '%s' "$path" 2>/dev/null || stat -f '%z' "$path" 2>/dev/null || echo 0)
  [ "$actual" -ge "$((expected * 95 / 100))" ]
}

fetch() {
  local url="$1"
  local dest="$2"
  local expected="$3"
  local label="$4"

  if verify_size "$dest" "$expected"; then
    echo "  [skip] $label already present at $dest"
    return 0
  fi

  echo "  [fetch] $label"
  echo "          $url"
  echo "          -> $dest"
  curl -L --fail --retry 3 --retry-delay 5 --continue-at - -o "$dest" "$url"
}

# ---------------------------------------------------------------- runtime

echo
echo "==> runtime"
fetch "$LLAMAFILE_URL" "$TARGET/ai-kit/runtime/llamafile" "$LLAMAFILE_BYTES" "llamafile-0.10.1-thin"
chmod +x "$TARGET/ai-kit/runtime/llamafile"
cp "$TARGET/ai-kit/runtime/llamafile" "$TARGET/ai-kit/runtime/llamafile.exe"
chmod +x "$TARGET/ai-kit/runtime/llamafile.exe"

# ---------------------------------------------------------------- weights

echo
echo "==> models  (this is the slow part — about 22 GB total)"
fetch "$E4B_URL" "$TARGET/ai-kit/models/$E4B_FILE" "$E4B_BYTES" "Gemma 4 E4B Q4_K_M (~5 GB)"
fetch "$MOE_URL" "$TARGET/ai-kit/models/$MOE_FILE" "$MOE_BYTES" "Gemma 4 26B-A4B UD-Q4_K_M (~17 GB)"
fetch "$EMB_URL" "$TARGET/ai-kit/models/$EMB_FILE" "$EMB_BYTES" "EmbeddingGemma 300M Q8 (~329 MB)"

# ---------------------------------------------------------------- launchers + dashboard

echo
echo "==> launchers + dashboard"
cp "$REPO/launchers/start.bat"     "$TARGET/start.bat"
cp "$REPO/launchers/start.command" "$TARGET/start.command"
cp "$REPO/launchers/start.sh"      "$TARGET/start.sh"
chmod +x "$TARGET/start.command" "$TARGET/start.sh"
cp "$REPO/dashboard/index.html"  "$TARGET/index.html"
cp "$REPO/dashboard/README.txt"  "$TARGET/README.txt"

echo
echo "------------------------------------------------------------"
echo "  Done."
echo "  Kit assembled at: $TARGET"
echo
echo "  Next:"
echo "    Linux:    $TARGET/start.sh"
echo "    macOS:    open $TARGET/start.command"
echo "    Windows:  double-click $TARGET\\start.bat in Explorer"
echo "------------------------------------------------------------"
