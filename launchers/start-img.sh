#!/usr/bin/env bash
# Image gen launcher: invokes stable-diffusion.cpp CLI with FLUX.2 klein 4B
# transformer + Qwen3-4B text encoder + small-decoder VAE to generate a
# 1024x1024 PNG from a user prompt. Lives at the USB root; references
# ai-kit/sd-img/ + ai-kit/models/ alongside.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Detect OS for the right sd-cli binary.
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="win" ;;
esac
SD_CLI="$ROOT/ai-kit/sd-img/$OS/sd-cli"
[ "$OS" = "win" ] && SD_CLI="$SD_CLI.exe"

SD_MODEL="$ROOT/ai-kit/sd-img/models/flux-2-klein-4b-Q4_K_M.gguf"
SD_VAE="$ROOT/ai-kit/sd-img/models/full_encoder_small_decoder.safetensors"
SD_LLM="$ROOT/ai-kit/models/Qwen3-4B-Q4_K_M.gguf"

if [ ! -f "$SD_CLI" ]; then
  echo "  ERROR: $SD_CLI not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

if [ ! -f "$SD_MODEL" ]; then
  echo "  ERROR: $SD_MODEL not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

if [ ! -f "$SD_VAE" ]; then
  echo "  ERROR: $SD_VAE not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

if [ ! -f "$SD_LLM" ]; then
  echo "  ERROR: $SD_LLM not found. Run ./build-usb.sh against this stick first."
  exit 1
fi

# Set library search path so bundled .so/.dylib siblings resolve at runtime.
case "$OS" in
  linux) export LD_LIBRARY_PATH="$ROOT/ai-kit/sd-img/linux" ;;
  mac)   export DYLD_LIBRARY_PATH="$ROOT/ai-kit/sd-img/mac" ;;
esac

clear
echo
echo "  =============================================="
echo "       IMAGE GEN — Doomstick · v0.10"
echo "  =============================================="
echo
echo "  Image gen takes 1-3 minutes on CPU."
echo "  Needs ~8-10 GB working RAM — close other apps if low on memory."
echo "  Press Ctrl-C to cancel."
echo

read -e -p "Prompt: " PROMPT
if [ -z "$PROMPT" ]; then
  echo "  No prompt entered. Aborting."
  exit 1
fi

OUT_PNG="$ROOT/img-out-$(date +%Y%m%d-%H%M%S).png"

"$SD_CLI" --diffusion-model "$SD_MODEL" --vae "$SD_VAE" --llm "$SD_LLM" \
  -p "$PROMPT" -H 1024 -W 1024 \
  --steps 4 --cfg-scale 1.0 --sampling-method euler \
  --diffusion-fa --offload-to-cpu \
  -o "$OUT_PNG"
if [ $? -ne 0 ]; then
  echo "  Image generation failed. See output above for details."
  exit 1
fi

echo
echo "  Image written to: $OUT_PNG"

case "$OS" in
  linux) xdg-open "$OUT_PNG" 2>/dev/null & ;;
  mac)   open "$OUT_PNG" ;;
  win)   start "" "$OUT_PNG" ;;
esac
