#!/usr/bin/env bash
# build-usb.sh — fetch the runtime + GGUFs and assemble the kit on a target dir.
#
# Modes:
#   ./build-usb.sh <target-dir>                Wizard (or sources existing config)
#   ./build-usb.sh -y <target-dir>             Skip wizard, use baked defaults
#   ./build-usb.sh -c <conf> <target-dir>      Source a saved config file
#   ./build-usb.sh -i <target-dir>             Force the wizard even if config exists
#   ./build-usb.sh -n <target-dir>             Dry-run: resolve config, print, exit
#   ./build-usb.sh -h | --help                 Show help
#
# After an interactive run, settings are saved to <target>/build-usb-config.sh
# so re-running on the same target skips prompts. Pass -i to re-prompt.
#
# Resumable: re-running skips files whose size already matches expected.
# Doesn't check signatures or hashes — for an air-gapped build, mirror the
# upstream URLs locally and edit the relevant TSV under presets/.

set -euo pipefail

REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PRESETS="$REPO/presets"

# ---------------------------------------------------------------- usage

usage() {
  cat <<EOF
Usage:
  $0 <target-dir>                Wizard mode (or sources <target>/build-usb-config.sh)
  $0 -y <target-dir>             Non-interactive — use baked defaults
  $0 -c <config.sh> <target-dir> Source the named config file
  $0 -i <target-dir>             Force wizard even if config exists at target
  $0 -n <target-dir>             Dry-run: resolve config, print, exit
  $0 -h | --help                 This help

Examples:
  $0 /mnt/usb                    Linux: wizard, then build
  $0 /Volumes/USB                macOS
  $0 /tmp/doomstick-test         Local dry-run target (any writable dir)
  $0 -y /mnt/usb                 CI / scripted builds

Defaults / 'full' bundle download size:
  AI core    ~22.3 GB   (43 MB runtime + 5 GB E4B + 17 GB 26B + 329 MB embed)
  Side arms  ~ 910 MB   (whisperfile small.en + kiwix + simple-en zim + tesseract + monaco pbf)
  TTS        ~ 210 MB   (sherpa-onnx per-OS + Supertonic int8 model)
  Image gen  ~ 2.6 GB   (sd.cpp per-OS + FLUX.2 klein 4B Q4_K_M)
  Total      ~28.5 GB   (full; ~23.3 GB without image gen)

Re-runs skip files already present with the right size.
EOF
}

# ---------------------------------------------------------------- arg parsing

MODE="wizard"
TARGET=""
CONFIG_PATH=""
FORCE_WIZARD=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -y|--non-interactive) MODE="noninteractive"; shift ;;
    -i|--interactive) FORCE_WIZARD=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -c|--config)
      [ -n "${2:-}" ] || { echo "error: -c requires a path" >&2; exit 2; }
      MODE="config"; CONFIG_PATH="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "error: unknown flag '$1'" >&2; usage; exit 2 ;;
    *)
      [ -z "$TARGET" ] || { echo "error: unexpected extra argument '$1'" >&2; exit 2; }
      TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { usage; exit 2; }

# ---------------------------------------------------------------- baked defaults

# Today's behavior — also matches the 'full' bundle. Keep these two in sync.
apply_baked_defaults() {
  DOOM_INCLUDE_E4B=1
  DOOM_INCLUDE_MOE=1
  DOOM_INCLUDE_EMB=1

  DOOM_INCLUDE_WIKI=1
  DOOM_ZIM_URL="https://download.kiwix.org/zim/wikipedia/wikipedia_en_simple_all_nopic_2026-02.zim"
  DOOM_ZIM_FILE="wikipedia_en_simple_all_nopic_2026-02.zim"
  DOOM_ZIM_BYTES=966064955
  DOOM_ZIM_LABEL="Simple English"

  DOOM_INCLUDE_OSM=1
  DOOM_PBF_URL="https://download.geofabrik.de/europe/monaco-latest.osm.pbf"
  DOOM_PBF_FILE="monaco-latest.osm.pbf"
  DOOM_PBF_BYTES=700000

  DOOM_INCLUDE_WHISPER=1
  DOOM_WHISPER_URL="https://huggingface.co/Mozilla/whisperfile/resolve/main/whisper-small.en.llamafile?download=true"
  DOOM_WHISPER_FILE="whisper-small.en.llamafile"
  DOOM_WHISPER_BYTES=497053916
  DOOM_WHISPER_LABEL="small.en"

  DOOM_INCLUDE_OCR=1
  DOOM_OCR_LANGS="eng"

  DOOM_INCLUDE_DOCS=1

  DOOM_INCLUDE_REDBEAN=1
  DOOM_INCLUDE_DOOM=1
  DOOM_INCLUDE_TTS=1
  DOOM_INCLUDE_IMG=1
  DOOM_INCLUDE_PASSWORDS=1
  DOOM_INCLUDE_FFMPEG=1
}

# ---------------------------------------------------------------- TSV loader

# Loads a TSV into TSV_LABELS[] and TSV_FIELDS[] (the latter holds the rest of
# each row, tab-joined). Skips comments and blanks. Used by the wizard.
TSV_LABELS=()
TSV_FIELDS=()
load_tsv() {
  local file="$1"
  TSV_LABELS=()
  TSV_FIELDS=()
  [ -f "$file" ] || { echo "error: missing preset file: $file" >&2; exit 2; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    local label rest
    label="${line%%	*}"
    rest="${line#*	}"
    TSV_LABELS+=("$label")
    TSV_FIELDS+=("$rest")
  done < "$file"
}

# Pulls one tab-separated field (1-indexed) out of a TSV_FIELDS row.
tsv_field() {
  local row="$1"
  local idx="$2"
  local i=1
  local remainder="$row"
  local part=""
  while [ "$i" -lt "$idx" ]; do
    remainder="${remainder#*	}"
    i=$((i+1))
  done
  part="${remainder%%	*}"
  printf '%s' "$part"
}

# ---------------------------------------------------------------- prompt helpers

# When stdin is a TTY (interactive shell), read prompts from it. When stdin is
# piped (test harness, automation), read from the pipe. /dev/tty would always
# bypass the pipe and reach the user's terminal — wrong for piped tests.
if [ -t 0 ]; then
  TTY_IN="/dev/tty"
  [ -r "$TTY_IN" ] || TTY_IN="/dev/stdin"
else
  TTY_IN="/dev/stdin"
fi

prompt_choice() {
  # prompt_choice "<label>" <default-1-indexed> opt1 opt2 ...
  # UI goes to stderr; only the picked number goes to stdout (caller captures via $(...)).
  local label="$1" default="$2"; shift 2
  local -a opts=("$@")
  local n=${#opts[@]} pick=""
  while true; do
    {
      echo
      echo "  $label"
      local i
      for i in "${!opts[@]}"; do
        local marker="  "
        [ "$((i+1))" = "$default" ] && marker="* "
        printf "%s[%d] %s\n" "$marker" "$((i+1))" "${opts[$i]}"
      done
      printf "  Pick [1-%d, default %d]: " "$n" "$default"
    } >&2
    IFS= read -r pick <"$TTY_IN" || pick=""
    pick="${pick:-$default}"
    case "$pick" in
      ''|*[!0-9]*) echo "  → not a number, try again" >&2 ;;
      *)
        if [ "$pick" -ge 1 ] && [ "$pick" -le "$n" ]; then
          printf '%s' "$pick"
          return 0
        fi
        echo "  → out of range 1..$n, try again" >&2
        ;;
    esac
  done
}

prompt_yes_no() {
  # prompt_yes_no "<label>" <Y|N>   → 0 yes, 1 no
  local label="$1" default="${2:-Y}" reply
  local hint="[Y/n]"; [ "$default" = "N" ] && hint="[y/N]"
  while true; do
    printf "  %s %s: " "$label" "$hint" >&2
    IFS= read -r reply <"$TTY_IN" || reply=""
    reply="${reply:-$default}"
    case "$reply" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo])     return 1 ;;
      *) echo "  → answer y or n" >&2 ;;
    esac
  done
}

prompt_subset() {
  # prompt_subset "<label>" "<keys-csv>" "<labels-csv>" "<default-csv>"
  # Keys map 1:1 to labels by position. Default is what's accepted on Enter.
  # User can answer "all", "none", or a comma-separated key list.
  # UI to stderr; result CSV to stdout.
  local label="$1"
  local keys_csv="$2"
  local labels_csv="$3"
  local default_csv="$4"
  local OLDIFS="$IFS"
  IFS=','
  local -a keys=($keys_csv)
  local -a labels=($labels_csv)
  IFS="$OLDIFS"
  local sample="${keys[0]}"
  [ "${#keys[@]}" -ge 2 ] && sample="${keys[0]},${keys[1]}"
  while true; do
    {
      echo
      echo "  $label"
      local i
      for i in "${!keys[@]}"; do
        local default_marker="  "
        case ",$default_csv," in *",${keys[$i]},"*) default_marker="* " ;; esac
        printf "%s[%s] %s\n" "$default_marker" "${keys[$i]}" "${labels[$i]}"
      done
      printf "  Pick subset (e.g. '%s' or 'all' or 'none', default '%s'): " "$sample" "$default_csv"
    } >&2
    local reply
    IFS= read -r reply <"$TTY_IN" || reply=""
    reply="${reply:-$default_csv}"
    reply="$(echo "$reply" | tr -d ' ')"
    case "$reply" in
      all)  printf '%s' "$keys_csv"; return 0 ;;
      none) printf ''; return 0 ;;
      *)
        # Validate every token is a known key.
        local ok=1 token
        IFS=','
        for token in $reply; do
          local found=0
          for k in "${keys[@]}"; do [ "$k" = "$token" ] && { found=1; break; }; done
          [ "$found" = "0" ] && { ok=0; echo "  → unknown key: $token" >&2; break; }
        done
        IFS="$OLDIFS"
        if [ "$ok" = "1" ]; then printf '%s' "$reply"; return 0; fi
        ;;
    esac
  done
}

prompt_string() {
  local label="$1" default="$2" reply
  printf "  %s [%s]: " "$label" "$default" >&2
  IFS= read -r reply <"$TTY_IN" || reply=""
  printf '%s' "${reply:-$default}"
}

human_bytes() {
  # Loose human-readable formatter. Inputs are bytes.
  local n="$1"
  if [ "$n" -ge 1000000000 ]; then
    awk -v n="$n" 'BEGIN { printf "%.1f GB", n/1000000000 }'
  elif [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN { printf "%.0f MB", n/1000000 }'
  else
    awk -v n="$n" 'BEGIN { printf "%.0f KB", n/1000 }'
  fi
}

# ---------------------------------------------------------------- bundles

apply_bundle() {
  # apply_bundle "tiny" | "balanced" | "full"
  local name="$1"
  load_tsv "$PRESETS/bundles.tsv"
  local i found=-1
  for i in "${!TSV_LABELS[@]}"; do
    [ "${TSV_LABELS[$i]}" = "$name" ] && { found=$i; break; }
  done
  [ "$found" -ge 0 ] || { echo "error: unknown bundle '$name'" >&2; exit 2; }
  local row="${TSV_FIELDS[$found]}"
  # Schema (v0.11, 21 columns):
  #   1 label  2 e4b  3 moe  4 emb  5 wiki  6 osm  7 whisper  8 ocr  9 docs
  #   10 redbean  11 doom  12 tts  13 img  14 passwords  15 ffmpeg
  #   16 zim_idx  17 osm_idx  18 whisper_idx  19 estimated_bytes  20 summary
  DOOM_INCLUDE_E4B="$(tsv_field "$row" 2)"
  DOOM_INCLUDE_MOE="$(tsv_field "$row" 3)"
  DOOM_INCLUDE_EMB="$(tsv_field "$row" 4)"
  DOOM_INCLUDE_WIKI="$(tsv_field "$row" 5)"
  DOOM_INCLUDE_OSM="$(tsv_field "$row" 6)"
  DOOM_INCLUDE_WHISPER="$(tsv_field "$row" 7)"
  DOOM_INCLUDE_OCR="$(tsv_field "$row" 8)"
  DOOM_INCLUDE_DOCS="$(tsv_field "$row" 9)"
  DOOM_INCLUDE_REDBEAN="$(tsv_field "$row" 10)"
  DOOM_INCLUDE_DOOM="$(tsv_field "$row" 11)"
  DOOM_INCLUDE_TTS="$(tsv_field "$row" 12)"
  DOOM_INCLUDE_IMG="$(tsv_field "$row" 13)"
  DOOM_INCLUDE_PASSWORDS="$(tsv_field "$row" 14)"
  DOOM_INCLUDE_FFMPEG="$(tsv_field "$row" 15)"
  local zim_idx osm_idx whisper_idx
  zim_idx="$(tsv_field "$row" 16)"
  osm_idx="$(tsv_field "$row" 17)"
  whisper_idx="$(tsv_field "$row" 18)"

  # Resolve indices into URL/FILE/BYTES via the per-thing TSVs.
  if [ "$DOOM_INCLUDE_WIKI" = "1" ] && [ "$zim_idx" -ge 1 ]; then
    load_tsv "$PRESETS/zim.tsv"
    local r="${TSV_FIELDS[$((zim_idx-1))]}"
    DOOM_ZIM_LABEL="${TSV_LABELS[$((zim_idx-1))]}"
    DOOM_ZIM_URL="$(tsv_field "$r" 1)"
    DOOM_ZIM_FILE="$(tsv_field "$r" 2)"
    DOOM_ZIM_BYTES="$(tsv_field "$r" 3)"
  fi
  if [ "$DOOM_INCLUDE_OSM" = "1" ] && [ "$osm_idx" -ge 1 ]; then
    load_tsv "$PRESETS/osm.tsv"
    local r="${TSV_FIELDS[$((osm_idx-1))]}"
    DOOM_PBF_URL="$(tsv_field "$r" 1)"
    DOOM_PBF_FILE="$(tsv_field "$r" 2)"
    DOOM_PBF_BYTES="$(tsv_field "$r" 3)"
  fi
  if [ "$DOOM_INCLUDE_WHISPER" = "1" ] && [ "$whisper_idx" -ge 1 ]; then
    load_tsv "$PRESETS/whisper.tsv"
    local r="${TSV_FIELDS[$((whisper_idx-1))]}"
    DOOM_WHISPER_LABEL="${TSV_LABELS[$((whisper_idx-1))]}"
    DOOM_WHISPER_URL="$(tsv_field "$r" 1)"
    DOOM_WHISPER_FILE="$(tsv_field "$r" 2)"
    DOOM_WHISPER_BYTES="$(tsv_field "$r" 3)"
  fi

  DOOM_OCR_LANGS="eng"
  if [ "$DOOM_INCLUDE_OCR" != "1" ]; then DOOM_OCR_LANGS=""; fi
}

# ---------------------------------------------------------------- wizard

run_wizard() {
  echo
  echo "============================================================"
  echo "  DOOMSTICK Build Wizard"
  echo "  Target: $TARGET"
  echo "============================================================"

  # Bundle prelude
  load_tsv "$PRESETS/bundles.tsv"
  local -a bundle_options=()
  local i
  for i in "${!TSV_LABELS[@]}"; do
    bundle_options+=("${TSV_LABELS[$i]} — $(tsv_field "${TSV_FIELDS[$i]}" 1)")
  done
  bundle_options+=("custom — pick each option individually")
  local pick
  pick="$(prompt_choice "Pick a bundle." 2 "${bundle_options[@]}")"

  if [ "$pick" -le "${#TSV_LABELS[@]}" ]; then
    apply_bundle "${TSV_LABELS[$((pick-1))]}"
    return 0
  fi

  # ---------- custom flow: 6 prompts ----------
  echo
  echo "  --- Custom configuration ---"

  # 1. Models — subset over E4B, MOE, EMB
  local models_csv
  models_csv="$(prompt_subset \
    "Which AI models?" \
    "e4b,moe,emb" \
    "Gemma 4 E4B (~5 GB),Gemma 4 26B-A4B (~17 GB),EmbeddingGemma 300M (~329 MB)" \
    "e4b,emb")"
  case ",$models_csv," in (*,e4b,*) DOOM_INCLUDE_E4B=1 ;; (*) DOOM_INCLUDE_E4B=0 ;; esac
  case ",$models_csv," in (*,moe,*) DOOM_INCLUDE_MOE=1 ;; (*) DOOM_INCLUDE_MOE=0 ;; esac
  case ",$models_csv," in (*,emb,*) DOOM_INCLUDE_EMB=1 ;; (*) DOOM_INCLUDE_EMB=0 ;; esac

  # 2. Wikipedia ZIM
  load_tsv "$PRESETS/zim.tsv"
  local -a zim_opts=("${TSV_LABELS[@]}" "Custom URL" "Skip Wikipedia")
  local zim_pick
  zim_pick="$(prompt_choice "Wikipedia ZIM?" 1 "${zim_opts[@]}")"
  local zim_n=${#TSV_LABELS[@]}
  if [ "$zim_pick" -le "$zim_n" ]; then
    DOOM_INCLUDE_WIKI=1
    local r="${TSV_FIELDS[$((zim_pick-1))]}"
    DOOM_ZIM_LABEL="${TSV_LABELS[$((zim_pick-1))]}"
    DOOM_ZIM_URL="$(tsv_field "$r" 1)"
    DOOM_ZIM_FILE="$(tsv_field "$r" 2)"
    DOOM_ZIM_BYTES="$(tsv_field "$r" 3)"
  elif [ "$zim_pick" = "$((zim_n+1))" ]; then
    DOOM_INCLUDE_WIKI=1
    DOOM_ZIM_URL="$(prompt_string "Custom ZIM URL" "https://download.kiwix.org/zim/wikipedia/...")"
    DOOM_ZIM_FILE="$(basename "$DOOM_ZIM_URL")"
    DOOM_ZIM_BYTES=1000000
    DOOM_ZIM_LABEL="custom"
  else
    DOOM_INCLUDE_WIKI=0
    DOOM_ZIM_URL=""; DOOM_ZIM_FILE=""; DOOM_ZIM_BYTES=0; DOOM_ZIM_LABEL="(skipped)"
  fi

  # 3. OSM region
  load_tsv "$PRESETS/osm.tsv"
  local -a osm_opts=("${TSV_LABELS[@]}" "Custom Geofabrik URL" "Skip maps")
  local osm_pick
  osm_pick="$(prompt_choice "OSM region for mobile maps?" 1 "${osm_opts[@]}")"
  local osm_n=${#TSV_LABELS[@]}
  if [ "$osm_pick" -le "$osm_n" ]; then
    DOOM_INCLUDE_OSM=1
    local r="${TSV_FIELDS[$((osm_pick-1))]}"
    DOOM_PBF_URL="$(tsv_field "$r" 1)"
    DOOM_PBF_FILE="$(tsv_field "$r" 2)"
    DOOM_PBF_BYTES="$(tsv_field "$r" 3)"
  elif [ "$osm_pick" = "$((osm_n+1))" ]; then
    DOOM_INCLUDE_OSM=1
    DOOM_PBF_URL="$(prompt_string "Custom .osm.pbf URL" "https://download.geofabrik.de/...")"
    DOOM_PBF_FILE="$(basename "$DOOM_PBF_URL")"
    DOOM_PBF_BYTES=1000000
  else
    DOOM_INCLUDE_OSM=0
    DOOM_PBF_URL=""; DOOM_PBF_FILE=""; DOOM_PBF_BYTES=0
  fi

  # 4. Whisper
  load_tsv "$PRESETS/whisper.tsv"
  local -a w_opts=("${TSV_LABELS[@]}" "Skip whisper")
  local w_pick
  w_pick="$(prompt_choice "Whisper voice-to-text model?" 2 "${w_opts[@]}")"
  local w_n=${#TSV_LABELS[@]}
  if [ "$w_pick" -le "$w_n" ]; then
    DOOM_INCLUDE_WHISPER=1
    local r="${TSV_FIELDS[$((w_pick-1))]}"
    DOOM_WHISPER_LABEL="${TSV_LABELS[$((w_pick-1))]}"
    DOOM_WHISPER_URL="$(tsv_field "$r" 1)"
    DOOM_WHISPER_FILE="$(tsv_field "$r" 2)"
    DOOM_WHISPER_BYTES="$(tsv_field "$r" 3)"
  else
    DOOM_INCLUDE_WHISPER=0
    DOOM_WHISPER_URL=""; DOOM_WHISPER_FILE=""; DOOM_WHISPER_BYTES=0; DOOM_WHISPER_LABEL="(skipped)"
  fi

  # 5. OCR languages
  load_tsv "$PRESETS/ocr.tsv"
  local ocr_keys ocr_labels
  ocr_keys="$(IFS=','; echo "${TSV_LABELS[*]}")"
  local -a ocr_label_arr=()
  for i in "${!TSV_LABELS[@]}"; do
    ocr_label_arr+=("${TSV_LABELS[$i]} — $(tsv_field "${TSV_FIELDS[$i]}" 1)")
  done
  ocr_labels="$(IFS=','; echo "${ocr_label_arr[*]}")"
  local ocr_csv
  ocr_csv="$(prompt_subset "OCR language packs?" "$ocr_keys" "$ocr_labels" "eng")"
  if [ -n "$ocr_csv" ]; then
    DOOM_INCLUDE_OCR=1
    DOOM_OCR_LANGS="$(echo "$ocr_csv" | tr ',' ' ')"
  else
    DOOM_INCLUDE_OCR=0
    DOOM_OCR_LANGS=""
  fi

  # 6. Side-arm toggles. Whisper/wiki/osm/ocr already gated above; ask
  # remaining content-light toggles individually.
  if prompt_yes_no "Include DevDocs landing zone? (manual setup, ~1 KB)" "Y"; then
    DOOM_INCLUDE_DOCS=1
  else
    DOOM_INCLUDE_DOCS=0
  fi

  if prompt_yes_no "Include redbean local platform layer? (~5.5 MB, port 8768 — needed for DOOM)" "Y"; then
    DOOM_INCLUDE_REDBEAN=1
  else
    DOOM_INCLUDE_REDBEAN=0
  fi

  if prompt_yes_no "Include DOOM (Dwasm port + shareware DOOM1.WAD, ~7.5 MB)?" "Y"; then
    DOOM_INCLUDE_DOOM=1
    if [ "${DOOM_INCLUDE_REDBEAN:-0}" != "1" ]; then
      echo "  → DOOM needs redbean to serve. Re-enabling redbean." >&2
      DOOM_INCLUDE_REDBEAN=1
    fi
  else
    DOOM_INCLUDE_DOOM=0
  fi

  # 9. TTS — Sherpa-ONNX runtime + Supertonic int8 model
  if prompt_yes_no "Include TTS (Sherpa-ONNX + Supertonic, ~210 MB across 3 OS binaries + model)?" "Y"; then
    DOOM_INCLUDE_TTS=1
    if [ "${DOOM_INCLUDE_REDBEAN:-0}" != "1" ]; then
      echo "  → TTS rides on redbean's /tts route. Re-enabling redbean." >&2
      DOOM_INCLUDE_REDBEAN=1
    fi
  else
    DOOM_INCLUDE_TTS=0
  fi

  # 10. Image gen — sd.cpp + FLUX.2 klein 4B Q4_K_M
  if prompt_yes_no "Include offline image gen (sd.cpp + FLUX.2 klein 4B Q4, ~2.6 GB)?" "N"; then
    DOOM_INCLUDE_IMG=1
  else
    DOOM_INCLUDE_IMG=0
  fi

  # 11. KeePassXC — cross-OS password manager (GPL-2.0+)
  if prompt_yes_no "Include KeePassXC password manager (cross-OS, ~250 MB)?" "Y"; then
    DOOM_INCLUDE_PASSWORDS=1
  else
    DOOM_INCLUDE_PASSWORDS=0
  fi

  # 12. ffmpeg — static cross-OS media swiss-army knife (GPL-3.0+)
  if prompt_yes_no "Include static ffmpeg (cross-OS media swiss-army, ~210 MB)?" "Y"; then
    DOOM_INCLUDE_FFMPEG=1
  else
    DOOM_INCLUDE_FFMPEG=0
  fi
}

# ---------------------------------------------------------------- estimate / free space

estimate_total_bytes() {
  local total=0
  total=$((total + 43800000))  # runtime, always
  [ "${DOOM_INCLUDE_E4B:-0}" = "1" ] && total=$((total + 5000000000))
  [ "${DOOM_INCLUDE_MOE:-0}" = "1" ] && total=$((total + 17000000000))
  [ "${DOOM_INCLUDE_EMB:-0}" = "1" ] && total=$((total + 329000000))
  [ "${DOOM_INCLUDE_WHISPER:-0}" = "1" ] && total=$((total + ${DOOM_WHISPER_BYTES:-0}))
  [ "${DOOM_INCLUDE_WIKI:-0}" = "1" ] && total=$((total + ${DOOM_ZIM_BYTES:-0} + 18000000))   # +18 MB for kiwix-tools tarballs
  [ "${DOOM_INCLUDE_OSM:-0}" = "1" ] && total=$((total + ${DOOM_PBF_BYTES:-0}))
  if [ "${DOOM_INCLUDE_OCR:-0}" = "1" ]; then
    total=$((total + 2600000))  # tesseract.js lib bundle
    local lang
    for lang in $DOOM_OCR_LANGS; do
      total=$((total + 12000000))   # rough avg per pack
    done
  fi
  [ "${DOOM_INCLUDE_REDBEAN:-0}" = "1" ] && total=$((total + 5500000))    # redbean.com
  [ "${DOOM_INCLUDE_DOOM:-0}" = "1" ]    && total=$((total + 7500000))    # Dwasm bundle ~3.2 MB + DOOM1.WAD ~4.2 MB
  [ "${DOOM_INCLUDE_TTS:-0}" = "1" ]       && total=$((total + 210000000))  # sherpa runtime (3× ~30 MB) + Supertonic int8 (~120 MB)
  [ "${DOOM_INCLUDE_IMG:-0}" = "1" ]       && total=$((total + 2646469190)) # sd.cpp 3-OS (42 MB) + FLUX.2 klein 4B Q4_K_M (~2.6 GB)
  [ "${DOOM_INCLUDE_PASSWORDS:-0}" = "1" ] && total=$((total + 250000000))  # KeePassXC 3-OS (~47 MB AppImage + ~36 MB dmg + ~35 MB zip + extracted)
  [ "${DOOM_INCLUDE_FFMPEG:-0}" = "1" ]    && total=$((total + 210000000))  # ffmpeg 3-OS (~117 MB linux64 + ~28 MB mac + ~157 MB win)
  printf '%s' "$total"
}

free_bytes_at() {
  local path="$1" out
  # Walk up to the closest existing ancestor — df fails on a not-yet-existent path.
  while [ ! -e "$path" ] && [ "$path" != "/" ]; do
    path="$(dirname "$path")"
  done
  out=$(df -PB1 "$path" 2>/dev/null | awk 'NR==2 {print $4}')
  [ -n "$out" ] && [ "$out" != "0" ] && printf '%s' "$out" || printf '0'
}

print_summary_and_confirm() {
  local needed free
  needed=$(estimate_total_bytes)
  free=$(free_bytes_at "$TARGET")

  echo
  echo "  ---------------- Summary ----------------"
  printf "  %-12s %s\n" "Models:"   "$( [ "${DOOM_INCLUDE_E4B:-0}" = "1" ] && echo -n 'E4B '; [ "${DOOM_INCLUDE_MOE:-0}" = "1" ] && echo -n '26B '; [ "${DOOM_INCLUDE_EMB:-0}" = "1" ] && echo -n 'Embed '; echo)"
  printf "  %-12s %s\n" "Wikipedia:" "$( [ "${DOOM_INCLUDE_WIKI:-0}" = "1" ] && echo "${DOOM_ZIM_LABEL:-?}" || echo '(skipped)')"
  printf "  %-12s %s\n" "OSM maps:"  "$( [ "${DOOM_INCLUDE_OSM:-0}" = "1" ] && echo "${DOOM_PBF_FILE:-?}" || echo '(skipped)')"
  printf "  %-12s %s\n" "Whisper:"   "$( [ "${DOOM_INCLUDE_WHISPER:-0}" = "1" ] && echo "${DOOM_WHISPER_LABEL:-?}" || echo '(skipped)')"
  printf "  %-12s %s\n" "OCR:"       "$( [ "${DOOM_INCLUDE_OCR:-0}" = "1" ] && echo "$DOOM_OCR_LANGS" || echo '(skipped)')"
  printf "  %-12s %s\n" "DevDocs:"   "$( [ "${DOOM_INCLUDE_DOCS:-0}" = "1" ] && echo 'included (manual setup)' || echo '(skipped)')"
  printf "  %-12s %s\n" "redbean:"   "$( [ "${DOOM_INCLUDE_REDBEAN:-0}" = "1" ] && echo 'included (port 8768)' || echo '(skipped)')"
  printf "  %-12s %s\n" "DOOM:"      "$( [ "${DOOM_INCLUDE_DOOM:-0}" = "1" ] && echo 'included (Dwasm + shareware WAD)' || echo '(skipped)')"
  printf "  %-12s %s\n" "TTS:"       "$( [ "${DOOM_INCLUDE_TTS:-0}" = "1" ] && echo 'included (Sherpa-ONNX + Supertonic int8)' || echo '(skipped)')"
  printf "  %-12s %s\n" "Img gen:"   "$( [ "${DOOM_INCLUDE_IMG:-0}" = "1" ] && echo 'included (sd.cpp + FLUX.2 klein 4B Q4_K_M)' || echo '(skipped)')"
  printf "  %-12s %s\n" "Passwords:" "$( [ "${DOOM_INCLUDE_PASSWORDS:-0}" = "1" ] && echo 'included (KeePassXC password manager)' || echo '(skipped)')"
  printf "  %-12s %s\n" "ffmpeg:"    "$( [ "${DOOM_INCLUDE_FFMPEG:-0}" = "1" ] && echo 'included (static ffmpeg, cross-OS media swiss-army)' || echo '(skipped)')"
  echo
  printf "  Estimated download: %s\n" "$(human_bytes "$needed")"
  if [ "$free" -gt 0 ]; then
    printf "  Free at target:     %s\n" "$(human_bytes "$free")"
    if [ "$needed" -gt "$free" ]; then
      echo "  → WARNING: estimated download exceeds free space at $TARGET"
    fi
  fi
  echo "  -----------------------------------------"

  if ! prompt_yes_no "Save these settings and proceed?" "Y"; then
    echo "Aborted by user."
    exit 0
  fi
}

# ---------------------------------------------------------------- config writer

write_config() {
  local path="$1"
  cat >"$path" <<EOF
# Doomstick build config — written $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Re-run:        ./build-usb.sh "$TARGET"   (auto-sources this file)
# Re-customize:  ./build-usb.sh -i "$TARGET"
# Override one:  edit the relevant DOOM_* line below

DOOM_INCLUDE_E4B=${DOOM_INCLUDE_E4B}
DOOM_INCLUDE_MOE=${DOOM_INCLUDE_MOE}
DOOM_INCLUDE_EMB=${DOOM_INCLUDE_EMB}

DOOM_INCLUDE_WIKI=${DOOM_INCLUDE_WIKI}
DOOM_ZIM_URL="${DOOM_ZIM_URL:-}"
DOOM_ZIM_FILE="${DOOM_ZIM_FILE:-}"
DOOM_ZIM_BYTES=${DOOM_ZIM_BYTES:-0}
DOOM_ZIM_LABEL="${DOOM_ZIM_LABEL:-}"

DOOM_INCLUDE_OSM=${DOOM_INCLUDE_OSM}
DOOM_PBF_URL="${DOOM_PBF_URL:-}"
DOOM_PBF_FILE="${DOOM_PBF_FILE:-}"
DOOM_PBF_BYTES=${DOOM_PBF_BYTES:-0}

DOOM_INCLUDE_WHISPER=${DOOM_INCLUDE_WHISPER}
DOOM_WHISPER_URL="${DOOM_WHISPER_URL:-}"
DOOM_WHISPER_FILE="${DOOM_WHISPER_FILE:-}"
DOOM_WHISPER_BYTES=${DOOM_WHISPER_BYTES:-0}
DOOM_WHISPER_LABEL="${DOOM_WHISPER_LABEL:-}"

DOOM_INCLUDE_OCR=${DOOM_INCLUDE_OCR}
DOOM_OCR_LANGS="${DOOM_OCR_LANGS:-}"

DOOM_INCLUDE_DOCS=${DOOM_INCLUDE_DOCS}

DOOM_INCLUDE_REDBEAN=${DOOM_INCLUDE_REDBEAN:-0}
DOOM_INCLUDE_DOOM=${DOOM_INCLUDE_DOOM:-0}
DOOM_INCLUDE_TTS=${DOOM_INCLUDE_TTS:-0}
DOOM_INCLUDE_IMG=${DOOM_INCLUDE_IMG:-0}
DOOM_INCLUDE_PASSWORDS=${DOOM_INCLUDE_PASSWORDS:-0}
DOOM_INCLUDE_FFMPEG=${DOOM_INCLUDE_FFMPEG:-0}
EOF
  echo "  [save] wrote config: $path"
}

# ---------------------------------------------------------------- mode dispatch

case "$MODE" in
  noninteractive)
    apply_baked_defaults
    ;;
  config)
    [ -f "$CONFIG_PATH" ] || { echo "error: config not found: $CONFIG_PATH" >&2; exit 2; }
    # shellcheck disable=SC1090
    . "$CONFIG_PATH"
    ;;
  wizard)
    if [ -f "$TARGET/build-usb-config.sh" ] && [ "$FORCE_WIZARD" = "0" ]; then
      echo "==> Sourcing existing config: $TARGET/build-usb-config.sh"
      echo "    (Pass -i to re-prompt and overwrite.)"
      # shellcheck disable=SC1090
      . "$TARGET/build-usb-config.sh"
    else
      mkdir -p "$TARGET"
      run_wizard
      print_summary_and_confirm
      write_config "$TARGET/build-usb-config.sh"
    fi
    ;;
esac

# ---------------------------------------------------------------- dry-run early-exit

if [ "$DRY_RUN" = "1" ]; then
  echo
  echo "  ---------------- Resolved DOOM_* state ----------------"
  # `set` also dumps function bodies; filter via `compgen -v` to list variable
  # names only, then look up each value.
  for v in $(compgen -v | grep '^DOOM_' | sort); do
    eval "echo \"  $v=\${$v}\""
  done
  echo "  -------------------------------------------------------"
  exit 0
fi

# ---------------------------------------------------------------- prep dirs

mkdir -p \
  "$TARGET/ai-kit/runtime" \
  "$TARGET/ai-kit/models" \
  "$TARGET/ai-kit/whisper" \
  "$TARGET/ai-kit/kiwix/linux" \
  "$TARGET/ai-kit/kiwix/mac" \
  "$TARGET/ai-kit/kiwix/win" \
  "$TARGET/ai-kit/redbean" \
  "$TARGET/ai-kit/sherpa-tts/linux" \
  "$TARGET/ai-kit/sherpa-tts/mac" \
  "$TARGET/ai-kit/sherpa-tts/win" \
  "$TARGET/ai-kit/sherpa-tts/models/supertonic" \
  "$TARGET/ai-kit/sd-img/linux" \
  "$TARGET/ai-kit/sd-img/mac" \
  "$TARGET/ai-kit/sd-img/win" \
  "$TARGET/ai-kit/sd-img/models" \
  "$TARGET/ai-kit/keepassxc/linux" \
  "$TARGET/ai-kit/keepassxc/mac" \
  "$TARGET/ai-kit/keepassxc/win" \
  "$TARGET/ai-kit/ffmpeg/linux" \
  "$TARGET/ai-kit/ffmpeg/mac" \
  "$TARGET/ai-kit/ffmpeg/win" \
  "$TARGET/zim" \
  "$TARGET/maps" \
  "$TARGET/ocr/lib" \
  "$TARGET/ocr/lang-data" \
  "$TARGET/docs-offline" \
  "$TARGET/doom" \
  "$TARGET/chat" \
  "$TARGET/workspace/default/docs" \
  "$TARGET/workspace/default/journal" \
  "$TARGET/workspace/default/_inbox" \
  "$TARGET/ai-kit/redbean/lua"

# ---------------------------------------------------------------- helpers (build phase)

LLAMAFILE_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.1/llamafile-0.10.1-thin"
LLAMAFILE_BYTES=43800000

E4B_URL="https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true"
E4B_FILE="gemma-4-E4B-it-Q4_K_M.gguf"
E4B_BYTES=5000000000
MOE_URL="https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf?download=true"
MOE_FILE="gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
MOE_BYTES=17000000000
EMB_URL="https://huggingface.co/ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/resolve/main/embeddinggemma-300m-qat-Q8_0.gguf?download=true"
EMB_FILE="embeddinggemma-300m-qat-Q8_0.gguf"
EMB_BYTES=329000000

KIWIX_LINUX_URL="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64.tar.gz"
KIWIX_MAC_URL="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_macos-x86_64.tar.gz"
KIWIX_WIN_URL="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_win-i686.zip"

TESSJS_URL="https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js"
TESSWORKER_URL="https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/worker.min.js"
TESSCORE_URL="https://cdn.jsdelivr.net/npm/tesseract.js-core@5.1.1/tesseract-core.wasm.js"
TESSWASM_URL="https://cdn.jsdelivr.net/npm/tesseract.js-core@5.1.1/tesseract-core.wasm"
TESSLANG_URL_BASE="https://github.com/tesseract-ocr/tessdata_fast/raw/main"

REDBEAN_URL="https://redbean.dev/redbean-3.0.0.com"
REDBEAN_FILE="redbean.com"
REDBEAN_BYTES=5500000

# Shareware DOOM1.WAD — id Software has long permitted free redistribution
# of the shareware Episode 1 WAD. ibiblio mirrors it via the SliTaz package
# archive. If this URL goes 404, alternates: archive.org's DoomShareware
# items, or zdoom.org's wad mirror. The 4196020-byte file is canonical.
DOOM_WAD_URL="https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad"
DOOM_WAD_FILE="doom1.wad"
DOOM_WAD_BYTES=4196020

# Sherpa-ONNX TTS runtime — native C++ binary, per-OS (no APE polyglot).
# All three OSes ship as multi-file tar.bz2 (binary + onnxruntime DLLs/SOs
# next to it). Pin to v1.13.1 (released 2026-05-08) — Supertonic supported
# since v1.12.29. Update version, sizes, and any new platform binaries here
# when bumping.
#
# Windows: pick the MT-Release variant. "MT" = static CRT, so the kit runs
# on hosts without the Visual C++ Redistributable installed (essential for
# "plug into a stranger's machine"). MD-Release is 4 MB smaller but silently
# breaks on hosts missing the redist. The release also offers a standalone
# `sherpa-onnx-non-streaming-tts-x64-<ver>.exe` — DO NOT USE: that's the GUI
# app ("Text-to-Speech with Next-gen Kaldi"), not the CLI we need. See the
# CLAUDE.md "Windows sherpa-onnx" gotcha.
SHERPA_VERSION="v1.13.1"
SHERPA_LINUX_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-linux-x64-shared.tar.bz2"
SHERPA_LINUX_BYTES=30000000
SHERPA_MAC_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-osx-arm64-shared.tar.bz2"
SHERPA_MAC_BYTES=30000000
SHERPA_WIN_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-win-x64-shared-MT-Release.tar.bz2"
SHERPA_WIN_BYTES=23278074

# Supertonic int8 model — int8-quantized ONNX bundle for Sherpa-ONNX TTS.
# Single archive containing duration_predictor.int8.onnx, text_encoder.int8.onnx,
# vector_estimator.int8.onnx, vocoder.int8.onnx, tts.json, unicode_indexer.bin,
# voice.bin (one English voice). Released by k2-fsa under tts-models tag.
SUPERTONIC_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-tts-int8-2026-03-06.tar.bz2"
SUPERTONIC_ARCHIVE="sherpa-onnx-supertonic-tts-int8-2026-03-06.tar.bz2"
SUPERTONIC_DIR_NAME="sherpa-onnx-supertonic-tts-int8-2026-03-06"
SUPERTONIC_BYTES=120000000

verify_size() {
  local path="$1" expected="$2" actual
  [ -f "$path" ] || return 1
  actual=$(stat -c '%s' "$path" 2>/dev/null || stat -f '%z' "$path" 2>/dev/null || echo 0)
  [ "$actual" -ge "$((expected * 95 / 100))" ]
}

fetch() {
  local url="$1" dest="$2" expected="$3" label="$4"
  if verify_size "$dest" "$expected"; then
    echo "  [skip] $label already present"
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
echo "==> models"
[ "${DOOM_INCLUDE_E4B:-0}" = "1" ] && fetch "$E4B_URL" "$TARGET/ai-kit/models/$E4B_FILE" "$E4B_BYTES" "Gemma 4 E4B Q4_K_M (~5 GB)"
[ "${DOOM_INCLUDE_MOE:-0}" = "1" ] && fetch "$MOE_URL" "$TARGET/ai-kit/models/$MOE_FILE" "$MOE_BYTES" "Gemma 4 26B-A4B UD-Q4_K_M (~17 GB)"
[ "${DOOM_INCLUDE_EMB:-0}" = "1" ] && fetch "$EMB_URL" "$TARGET/ai-kit/models/$EMB_FILE" "$EMB_BYTES" "EmbeddingGemma 300M Q8 (~329 MB)"

# ---------------------------------------------------------------- side arms

echo
echo "==> side arms"

# Whisper
if [ "${DOOM_INCLUDE_WHISPER:-0}" = "1" ] && [ -n "${DOOM_WHISPER_URL:-}" ]; then
  fetch "$DOOM_WHISPER_URL" "$TARGET/ai-kit/whisper/$DOOM_WHISPER_FILE" "$DOOM_WHISPER_BYTES" "Whisperfile $DOOM_WHISPER_LABEL"
  chmod +x "$TARGET/ai-kit/whisper/$DOOM_WHISPER_FILE"
fi

# Kiwix tools (only if including wiki content)
if [ "${DOOM_INCLUDE_WIKI:-0}" = "1" ]; then
  KIWIX_LINUX_TGZ="$TARGET/ai-kit/kiwix/linux/kiwix-tools.tar.gz"
  KIWIX_MAC_TGZ="$TARGET/ai-kit/kiwix/mac/kiwix-tools.tar.gz"
  KIWIX_WIN_ZIP="$TARGET/ai-kit/kiwix/win/kiwix-tools.zip"
  if [ ! -x "$TARGET/ai-kit/kiwix/linux/kiwix-serve" ]; then
    fetch "$KIWIX_LINUX_URL" "$KIWIX_LINUX_TGZ" 6000000 "kiwix-tools (linux)"
    tar -xzf "$KIWIX_LINUX_TGZ" -C "$TARGET/ai-kit/kiwix/linux" --strip-components=1
    rm -f "$KIWIX_LINUX_TGZ"
    chmod +x "$TARGET/ai-kit/kiwix/linux/"* 2>/dev/null || true
  fi
  if [ ! -x "$TARGET/ai-kit/kiwix/mac/kiwix-serve" ]; then
    fetch "$KIWIX_MAC_URL" "$KIWIX_MAC_TGZ" 6000000 "kiwix-tools (macOS)"
    tar -xzf "$KIWIX_MAC_TGZ" -C "$TARGET/ai-kit/kiwix/mac" --strip-components=1
    rm -f "$KIWIX_MAC_TGZ"
    chmod +x "$TARGET/ai-kit/kiwix/mac/"* 2>/dev/null || true
  fi
  if [ ! -f "$TARGET/ai-kit/kiwix/win/kiwix-serve.exe" ]; then
    fetch "$KIWIX_WIN_URL" "$KIWIX_WIN_ZIP" 6000000 "kiwix-tools (windows)"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -j "$KIWIX_WIN_ZIP" -d "$TARGET/ai-kit/kiwix/win" >/dev/null
      rm -f "$KIWIX_WIN_ZIP"
    else
      echo "  [warn] unzip not available; leaving $KIWIX_WIN_ZIP for manual extraction"
    fi
  fi
  fetch "$DOOM_ZIM_URL" "$TARGET/zim/$DOOM_ZIM_FILE" "$DOOM_ZIM_BYTES" "Wikipedia: $DOOM_ZIM_LABEL"
fi

# OCR
if [ "${DOOM_INCLUDE_OCR:-0}" = "1" ]; then
  fetch "$TESSJS_URL"     "$TARGET/ocr/lib/tesseract.min.js"        500000  "tesseract.js"
  fetch "$TESSWORKER_URL" "$TARGET/ocr/lib/worker.min.js"           50000   "tesseract.js worker"
  fetch "$TESSCORE_URL"   "$TARGET/ocr/lib/tesseract-core.wasm.js"  3000    "tesseract-core wrapper"
  fetch "$TESSWASM_URL"   "$TARGET/ocr/lib/tesseract-core.wasm"     2000000 "tesseract-core wasm"
  for lang in $DOOM_OCR_LANGS; do
    fetch "$TESSLANG_URL_BASE/$lang.traineddata" "$TARGET/ocr/lang-data/$lang.traineddata" 5000000 "tesseract pack: $lang"
  done
fi

# OSM
if [ "${DOOM_INCLUDE_OSM:-0}" = "1" ] && [ -n "${DOOM_PBF_URL:-}" ]; then
  fetch "$DOOM_PBF_URL" "$TARGET/maps/$DOOM_PBF_FILE" "$DOOM_PBF_BYTES" "OSM .pbf ($DOOM_PBF_FILE)"
fi

# redbean — local platform layer (port 8768)
# Fetch + stage; the zip-bake (.init.lua + doom/* if included) happens
# AFTER DOOM staging in a single combined step below.
if [ "${DOOM_INCLUDE_REDBEAN:-0}" = "1" ]; then
  fetch "$REDBEAN_URL" "$TARGET/ai-kit/redbean/$REDBEAN_FILE" "$REDBEAN_BYTES" "redbean 3.0.0 (~5.5 MB)"
  chmod +x "$TARGET/ai-kit/redbean/$REDBEAN_FILE"
  cp "$REPO/redbean/.init.lua"           "$TARGET/ai-kit/redbean/.init.lua"
  cp "$REPO/redbean/README.txt"          "$TARGET/ai-kit/redbean/README.txt"
  # v0.8 RAG: pure-Lua cosine module — baked into redbean.com's appended zip
  # at .lua/rag-cosine.lua so `require("rag-cosine")` in .init.lua resolves.
  cp "$REPO/redbean/lua/rag-cosine.lua"  "$TARGET/ai-kit/redbean/lua/rag-cosine.lua"
fi

# DOOM — Dwasm port (vendored under doom/ in repo) + shareware DOOM1.WAD (fetched)
if [ "${DOOM_INCLUDE_DOOM:-0}" = "1" ]; then
  fetch "$DOOM_WAD_URL" "$TARGET/doom/$DOOM_WAD_FILE" "$DOOM_WAD_BYTES" "DOOM1.WAD shareware (~4.2 MB)"
  cp "$REPO/doom/index.html"        "$TARGET/doom/index.html"
  cp "$REPO/doom/index.js"          "$TARGET/doom/index.js"
  cp "$REPO/doom/index.data"        "$TARGET/doom/index.data"
  cp "$REPO/doom/index.wasm"        "$TARGET/doom/index.wasm"
  cp "$REPO/doom/LICENSE-GPL-2.0"   "$TARGET/doom/LICENSE-GPL-2.0"
  cp "$REPO/doom/NOTICE.md"         "$TARGET/doom/NOTICE.md"
fi

# Bake .init.lua (+ doom/* when shipped) into redbean.com's appended zip.
#
# Why baked into the zip and not just `-D <docroot>`:
#   - redbean reads .init.lua from its asset zip; -D overlays static files
#     but does NOT expose .init.lua as an asset, and the `-A` runtime-add
#     flag is broken in 3.0.0 (StoreAsset regression).
#   - When the USB is exFAT (typical) and accessed from native Windows,
#     Cosmopolitan's stat() reports directories as mode 040700, which fails
#     redbean's static-serve "other readable" check → 403 on /doom/. Files
#     served from the appended zip skip that filesystem check entirely.
#
# Why bake on a /tmp ext4 dir and cp back instead of zipping in place:
#   - zip's atomic-rename (temp ziXXXXXX → original) fails on WSL DrvFs
#     mounts of exFAT, leaving the original gone and an orphan temp file.
#     Plain cp from /tmp → target works fine; no atomic rename involved.
#
# Doing the bake on the *target* binary so the canonical repo source stays
# untouched. Idempotent: zip updates existing entries on re-bake.
if [ "${DOOM_INCLUDE_REDBEAN:-0}" = "1" ] && command -v zip >/dev/null 2>&1; then
  rm -f "$TARGET/ai-kit/redbean/"zi?????? 2>/dev/null || true   # sweep prior-run orphans

  BAKE_TMP="$(mktemp -d)"
  cp "$TARGET/ai-kit/redbean/$REDBEAN_FILE" "$BAKE_TMP/$REDBEAN_FILE"
  cp "$TARGET/ai-kit/redbean/.init.lua"     "$BAKE_TMP/.init.lua"

  # v0.8 RAG: stage rag-cosine.lua at .lua/rag-cosine.lua so redbean's
  # require("rag-cosine") finds it in the zip's package.path.
  mkdir -p "$BAKE_TMP/.lua"
  cp "$TARGET/ai-kit/redbean/lua/rag-cosine.lua" "$BAKE_TMP/.lua/rag-cosine.lua"

  BAKE_ENTRIES=".init.lua .lua/rag-cosine.lua"
  if [ "${DOOM_INCLUDE_DOOM:-0}" = "1" ]; then
    mkdir -p "$BAKE_TMP/doom"
    cp "$TARGET/doom/index.html"      "$BAKE_TMP/doom/"
    cp "$TARGET/doom/index.js"        "$BAKE_TMP/doom/"
    cp "$TARGET/doom/index.data"      "$BAKE_TMP/doom/"
    cp "$TARGET/doom/index.wasm"      "$BAKE_TMP/doom/"
    cp "$TARGET/doom/$DOOM_WAD_FILE"  "$BAKE_TMP/doom/"
    cp "$TARGET/doom/LICENSE-GPL-2.0" "$BAKE_TMP/doom/"
    cp "$TARGET/doom/NOTICE.md"       "$BAKE_TMP/doom/"
    BAKE_ENTRIES="$BAKE_ENTRIES doom/index.html doom/index.js doom/index.data doom/index.wasm doom/$DOOM_WAD_FILE doom/LICENSE-GPL-2.0 doom/NOTICE.md"
  fi

  ( cd "$BAKE_TMP" && zip -q "$REDBEAN_FILE" $BAKE_ENTRIES )
  cp "$BAKE_TMP/$REDBEAN_FILE" "$TARGET/ai-kit/redbean/$REDBEAN_FILE"
  # Keep redbean.com.exe in sync with redbean.com so Windows launches the
  # freshly-baked binary, not a stale .exe from a prior deploy. (start-doom.bat
  # only runs the .exe variant; its `if not exist` guard skips the copy when
  # .exe already exists, so build-usb has to refresh it here.)
  cp "$BAKE_TMP/$REDBEAN_FILE" "$TARGET/ai-kit/redbean/$REDBEAN_FILE.exe"
  rm -rf "$BAKE_TMP"

  if [ "${DOOM_INCLUDE_DOOM:-0}" = "1" ]; then
    echo "  baked .init.lua + doom/ into $TARGET/ai-kit/redbean/$REDBEAN_FILE (+.exe synced)"
  else
    echo "  baked .init.lua into $TARGET/ai-kit/redbean/$REDBEAN_FILE (+.exe synced)"
  fi
elif [ "${DOOM_INCLUDE_REDBEAN:-0}" = "1" ]; then
  echo "  WARNING: 'zip' not found — redbean will not load .init.lua at runtime."
  echo "           Install zip (apt: zip / brew: zip / mac: ships in xcode-select) and re-run."
fi

# ---------------------------------------------------------------- TTS

# Sherpa-ONNX runtime + Supertonic int8 model. v0.7 customer of redbean's
# /tts route (port 8768). Native C++ binaries per OS (no Python on host).
if [ "${DOOM_INCLUDE_TTS:-0}" = "1" ]; then
  echo
  echo "==> tts (sherpa-onnx + supertonic)"

  # Linux runtime — multi-file shared tarball. Extract to ai-kit/sherpa-tts/linux/.
  # -f not -x: exFAT without metadata mount option strips execute bits.
  if [ ! -f "$TARGET/ai-kit/sherpa-tts/linux/sherpa-onnx-offline-tts" ]; then
    SHERPA_LINUX_TBZ="$TARGET/ai-kit/sherpa-tts/linux/sherpa-onnx.tar.bz2"
    fetch "$SHERPA_LINUX_URL" "$SHERPA_LINUX_TBZ" "$SHERPA_LINUX_BYTES" "sherpa-onnx ${SHERPA_VERSION} linux-x64"
    tar -xjf "$SHERPA_LINUX_TBZ" -C "$TARGET/ai-kit/sherpa-tts/linux" --strip-components=1
    rm -f "$SHERPA_LINUX_TBZ"
    # Sherpa releases nest binaries under bin/ and shared libs under lib/.
    # Flatten so the .init.lua handler can find sherpa-onnx-offline-tts at
    # the top of ai-kit/sherpa-tts/linux/ and the .so files alongside it.
    if [ -x "$TARGET/ai-kit/sherpa-tts/linux/bin/sherpa-onnx-offline-tts" ]; then
      mv "$TARGET/ai-kit/sherpa-tts/linux/bin/"* "$TARGET/ai-kit/sherpa-tts/linux/" 2>/dev/null || true
      mv "$TARGET/ai-kit/sherpa-tts/linux/lib/"* "$TARGET/ai-kit/sherpa-tts/linux/" 2>/dev/null || true
      rmdir "$TARGET/ai-kit/sherpa-tts/linux/bin" "$TARGET/ai-kit/sherpa-tts/linux/lib" 2>/dev/null || true
    fi
    chmod +x "$TARGET/ai-kit/sherpa-tts/linux/sherpa-onnx-offline-tts" 2>/dev/null || true
  fi

  # macOS runtime — same shape as Linux. arm64 only for now (M-series).
  if [ ! -f "$TARGET/ai-kit/sherpa-tts/mac/sherpa-onnx-offline-tts" ]; then
    SHERPA_MAC_TBZ="$TARGET/ai-kit/sherpa-tts/mac/sherpa-onnx.tar.bz2"
    fetch "$SHERPA_MAC_URL" "$SHERPA_MAC_TBZ" "$SHERPA_MAC_BYTES" "sherpa-onnx ${SHERPA_VERSION} osx-arm64"
    tar -xjf "$SHERPA_MAC_TBZ" -C "$TARGET/ai-kit/sherpa-tts/mac" --strip-components=1
    rm -f "$SHERPA_MAC_TBZ"
    if [ -x "$TARGET/ai-kit/sherpa-tts/mac/bin/sherpa-onnx-offline-tts" ]; then
      mv "$TARGET/ai-kit/sherpa-tts/mac/bin/"* "$TARGET/ai-kit/sherpa-tts/mac/" 2>/dev/null || true
      mv "$TARGET/ai-kit/sherpa-tts/mac/lib/"* "$TARGET/ai-kit/sherpa-tts/mac/" 2>/dev/null || true
      rmdir "$TARGET/ai-kit/sherpa-tts/mac/bin" "$TARGET/ai-kit/sherpa-tts/mac/lib" 2>/dev/null || true
    fi
    chmod +x "$TARGET/ai-kit/sherpa-tts/mac/sherpa-onnx-offline-tts" 2>/dev/null || true
  fi

  # Windows runtime — multi-file shared tarball, same shape as Linux/Mac.
  # bin/sherpa-onnx-offline-tts.exe + bin/onnxruntime*.dll + lib/*.dll.
  # Static CRT (MT-Release), so no Visual C++ Redistributable needed on host.
  # Guard requires both the .exe AND onnxruntime.dll — earlier kits shipped
  # the standalone GUI .exe under this same filename, and that variant lacks
  # onnxruntime.dll, so this clause refetches the proper CLI archive over it.
  if [ ! -f "$TARGET/ai-kit/sherpa-tts/win/sherpa-onnx-offline-tts.exe" ] || \
     [ ! -f "$TARGET/ai-kit/sherpa-tts/win/onnxruntime.dll" ]; then
    rm -f "$TARGET/ai-kit/sherpa-tts/win/sherpa-onnx-offline-tts.exe"
    SHERPA_WIN_TBZ="$TARGET/ai-kit/sherpa-tts/win/sherpa-onnx.tar.bz2"
    fetch "$SHERPA_WIN_URL" "$SHERPA_WIN_TBZ" "$SHERPA_WIN_BYTES" "sherpa-onnx ${SHERPA_VERSION} win-x64 (MT-Release)"
    tar -xjf "$SHERPA_WIN_TBZ" -C "$TARGET/ai-kit/sherpa-tts/win" --strip-components=1
    rm -f "$SHERPA_WIN_TBZ"
    # Same flatten pattern as Linux/Mac — the .exe and its onnxruntime DLLs
    # need to sit at the top of ai-kit/sherpa-tts/win/ for the .init.lua
    # TtsHandler to find them and for Windows DLL search to resolve deps.
    if [ -f "$TARGET/ai-kit/sherpa-tts/win/bin/sherpa-onnx-offline-tts.exe" ]; then
      mv "$TARGET/ai-kit/sherpa-tts/win/bin/"* "$TARGET/ai-kit/sherpa-tts/win/" 2>/dev/null || true
      mv "$TARGET/ai-kit/sherpa-tts/win/lib/"* "$TARGET/ai-kit/sherpa-tts/win/" 2>/dev/null || true
      rmdir "$TARGET/ai-kit/sherpa-tts/win/bin" "$TARGET/ai-kit/sherpa-tts/win/lib" 2>/dev/null || true
    fi
  fi

  # Supertonic int8 model — shared across all 3 OS binaries. Single tarball,
  # extract to ai-kit/sherpa-tts/models/supertonic/. The archive nests
  # everything under sherpa-onnx-supertonic-tts-int8-2026-03-06/ so
  # --strip-components=1 lands the files directly under supertonic/.
  if [ ! -f "$TARGET/ai-kit/sherpa-tts/models/supertonic/voice.bin" ]; then
    SUPERTONIC_TBZ="$TARGET/ai-kit/sherpa-tts/models/$SUPERTONIC_ARCHIVE"
    fetch "$SUPERTONIC_URL" "$SUPERTONIC_TBZ" "$SUPERTONIC_BYTES" "Supertonic int8 (~120 MB)"
    tar -xjf "$SUPERTONIC_TBZ" -C "$TARGET/ai-kit/sherpa-tts/models/supertonic" --strip-components=1
    rm -f "$SUPERTONIC_TBZ"
  fi
fi

# ---------------------------------------------------------------- image gen (sd.cpp + flux.2 klein)

# stable-diffusion.cpp runtime + FLUX.2 klein 4B Q4_K_M model. v0.10 standalone
# launcher (start-img.{sh,bat,command}) — NOT a redbean route (60-180s blocking
# image gen would DoS every other 8768 customer). Native C++ binaries per OS,
# no Python on host. sd.cpp uses rolling master-N-sha tags, NOT semver.
IMG_VERSION="master-596-90e87bc"
IMG_LINUX_URL="https://github.com/leejet/stable-diffusion.cpp/releases/download/${IMG_VERSION}/sd-master-90e87bc-bin-Linux-Ubuntu-24.04-x86_64.zip"
IMG_MAC_URL="https://github.com/leejet/stable-diffusion.cpp/releases/download/${IMG_VERSION}/sd-master-90e87bc-bin-Darwin-macOS-15.7.4-arm64.zip"
IMG_WIN_URL="https://github.com/leejet/stable-diffusion.cpp/releases/download/${IMG_VERSION}/sd-master-90e87bc-bin-win-avx2-x64.zip"
IMG_LINUX_BYTES=11560677
IMG_MAC_BYTES=21432078
IMG_WIN_BYTES=9165331

# FLUX.2 klein 4B Q4_K_M — Black Forest Labs (Jan 2026), Apache-2.0. Transformer-
# only GGUF (~2.6 GB). NOT all-in-one: sd.cpp needs companion VAE (--vae) +
# Qwen3-4B text encoder (--llm) supplied separately. See sd.cpp docs/flux2.md.
IMG_MODEL_URL="https://huggingface.co/unsloth/FLUX.2-klein-4B-GGUF/resolve/main/flux-2-klein-4b-Q4_K_M.gguf"
IMG_MODEL_BYTES=2604311104
IMG_MODEL_FILENAME="flux-2-klein-4b-Q4_K_M.gguf"

# Qwen3-4B Q4_K_M — Apache-2.0 (Alibaba/Qwen). Doubles as FLUX.2 klein text
# encoder (sd.cpp --llm flag) AND a standalone AI core option in start.{sh,bat,
# command} picker (runtime-detected). Lives at ai-kit/models/ alongside Gemma
# weights, NOT inside sd-img/ — shared resource. ~2.33 GB.
IMG_LLM_URL="https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true"
IMG_LLM_BYTES=2497281312
IMG_LLM_FILENAME="Qwen3-4B-Q4_K_M.gguf"

# FLUX.2 small-decoder VAE — Black Forest Labs, Apache-2.0. Ungated alternative
# to the gated FLUX.2-dev VAE. ~238 MB.
IMG_VAE_URL="https://huggingface.co/black-forest-labs/FLUX.2-small-decoder/resolve/main/full_encoder_small_decoder.safetensors?download=true"
IMG_VAE_BYTES=249519092
IMG_VAE_FILENAME="full_encoder_small_decoder.safetensors"

# KeePassXC — cross-OS password manager, GPL-2.0+.
# Linux: AppImage (self-contained, extract on-the-fly with --appimage-extract).
# macOS: arm64 .dmg (deferred extraction — hdiutil runs at first launch, not
#   at build time, because dmg mounting can't run on Linux/WSL).
# Windows: Win64.zip (flattened with unzip -j); keepassxc.ini activates portable
#   mode so KeePassXC stores its config/db next to the binary, not in %APPDATA%.
KEEPASSXC_VERSION="2.7.12"
KEEPASSXC_LINUX_FILENAME="KeePassXC-${KEEPASSXC_VERSION}-x86_64.AppImage"
KEEPASSXC_LINUX_URL="https://github.com/keepassxreboot/keepassxc/releases/download/${KEEPASSXC_VERSION}/${KEEPASSXC_LINUX_FILENAME}"
KEEPASSXC_LINUX_BYTES=49283072   # placeholder ~47 MB; pinned size for verify_size
KEEPASSXC_MAC_FILENAME="KeePassXC-${KEEPASSXC_VERSION}-arm64.dmg"
KEEPASSXC_MAC_URL="https://github.com/keepassxreboot/keepassxc/releases/download/${KEEPASSXC_VERSION}/${KEEPASSXC_MAC_FILENAME}"
KEEPASSXC_MAC_BYTES=37748736     # ~36 MB
KEEPASSXC_WIN_FILENAME="KeePassXC-${KEEPASSXC_VERSION}-Win64.zip"
KEEPASSXC_WIN_URL="https://github.com/keepassxreboot/keepassxc/releases/download/${KEEPASSXC_VERSION}/${KEEPASSXC_WIN_FILENAME}"
KEEPASSXC_WIN_BYTES=36700160     # ~35 MB

# ffmpeg — GPL-3.0+. BtbN builds for Linux/Windows; Martin-Riedl for macOS arm64.
#
# NOTE: BtbN's "latest" tag is rolling for the n7.1 stable branch — re-running
# build-usb on different days may fetch different patch builds. The n7.1 major
# version is pinned; only the specific commit within that release line can vary.
# Trade-off: always-current security patches without the pain of manual version
# bumps. Pin to a specific commit tag only if reproducible builds matter.
FFMPEG_VERSION="n7.1"
FFMPEG_LINUX64_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-${FFMPEG_VERSION}-latest-linux64-gpl-7.1.tar.xz"
FFMPEG_LINUX64_BYTES=122683392   # ~117 MB
FFMPEG_LINUXARM64_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-${FFMPEG_VERSION}-latest-linuxarm64-gpl-7.1.tar.xz"
FFMPEG_LINUXARM64_BYTES=104857600  # ~100 MB
FFMPEG_MAC_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1777624525_N-124279-g0f6ba39122/ffmpeg.zip"
FFMPEG_MAC_BYTES=28950528         # ~27.6 MB live-verified
FFMPEG_WIN_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-${FFMPEG_VERSION}-latest-win64-gpl-7.1.zip"
FFMPEG_WIN_BYTES=164626432        # ~157 MB

if [ "${DOOM_INCLUDE_IMG:-0}" = "1" ]; then
  echo
  echo "==> image gen (sd.cpp ${IMG_VERSION} + FLUX.2 klein)"

  # Linux runtime — .zip with files at root (sd-cli + libstable-diffusion.so + sd-server + *.txt).
  # Two-file guard: binary AND shared lib must be present (catches partial-extraction failures).
  # Use -f not -x: exFAT without metadata mount option strips execute bits, so -x would
  # evaluate false on a freshly-extracted binary and trigger needless re-fetch.
  if [ ! -f "$TARGET/ai-kit/sd-img/linux/sd-cli" ] || [ ! -f "$TARGET/ai-kit/sd-img/linux/libstable-diffusion.so" ]; then
    SD_LINUX_ZIP="/tmp/sd-linux.zip"
    fetch "$IMG_LINUX_URL" "$SD_LINUX_ZIP" "$IMG_LINUX_BYTES" "sd.cpp ${IMG_VERSION} linux-x64"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o "$SD_LINUX_ZIP" -d "$TARGET/ai-kit/sd-img/linux" >/dev/null
      chmod +x "$TARGET/ai-kit/sd-img/linux/sd-cli" 2>/dev/null || true
      rm -f "$SD_LINUX_ZIP"
    else
      echo "  [warn] unzip not available; leaving $SD_LINUX_ZIP for manual extraction"
    fi
  fi

  # macOS runtime — same shape as Linux. arm64 only.
  if [ ! -f "$TARGET/ai-kit/sd-img/mac/sd-cli" ] || [ ! -f "$TARGET/ai-kit/sd-img/mac/libstable-diffusion.dylib" ]; then
    SD_MAC_ZIP="/tmp/sd-mac.zip"
    fetch "$IMG_MAC_URL" "$SD_MAC_ZIP" "$IMG_MAC_BYTES" "sd.cpp ${IMG_VERSION} osx-arm64"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o "$SD_MAC_ZIP" -d "$TARGET/ai-kit/sd-img/mac" >/dev/null
      chmod +x "$TARGET/ai-kit/sd-img/mac/sd-cli" 2>/dev/null || true
      rm -f "$SD_MAC_ZIP"
    else
      echo "  [warn] unzip not available; leaving $SD_MAC_ZIP for manual extraction"
    fi
  fi

  # Windows runtime — .zip with sd-cli.exe + stable-diffusion.dll + sd-server.exe + *.txt at root.
  # Files-at-root means no flatten/--strip-components needed.
  if [ ! -f "$TARGET/ai-kit/sd-img/win/sd-cli.exe" ] || [ ! -f "$TARGET/ai-kit/sd-img/win/stable-diffusion.dll" ]; then
    SD_WIN_ZIP="/tmp/sd-win.zip"
    fetch "$IMG_WIN_URL" "$SD_WIN_ZIP" "$IMG_WIN_BYTES" "sd.cpp ${IMG_VERSION} win-avx2-x64"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o "$SD_WIN_ZIP" -d "$TARGET/ai-kit/sd-img/win" >/dev/null
      rm -f "$SD_WIN_ZIP"
    else
      echo "  [warn] unzip not available; leaving $SD_WIN_ZIP for manual extraction"
    fi
  fi

  # FLUX.2 klein 4B Q4_K_M transformer GGUF — 2.6 GB. NOT all-in-one (see comment
  # block above). VAE + text-encoder companions fetched below.
  if [ ! -f "$TARGET/ai-kit/sd-img/models/$IMG_MODEL_FILENAME" ]; then
    fetch "$IMG_MODEL_URL" "$TARGET/ai-kit/sd-img/models/$IMG_MODEL_FILENAME" "$IMG_MODEL_BYTES" "FLUX.2 klein 4B Q4_K_M (~2.6 GB)"
  fi

  # FLUX.2 small-decoder VAE companion — required for sd.cpp --vae flag.
  if [ ! -f "$TARGET/ai-kit/sd-img/models/$IMG_VAE_FILENAME" ]; then
    fetch "$IMG_VAE_URL" "$TARGET/ai-kit/sd-img/models/$IMG_VAE_FILENAME" "$IMG_VAE_BYTES" "FLUX.2 small-decoder VAE (~238 MB)"
  fi

  # Qwen3-4B Q4_K_M text encoder + AI core option — required for sd.cpp --llm
  # flag. Lives at ai-kit/models/ so start.{sh,bat,command} can detect it as
  # a 3rd AI core menu option (E4B / 26B / Qwen3-4B).
  if [ ! -f "$TARGET/ai-kit/models/$IMG_LLM_FILENAME" ]; then
    fetch "$IMG_LLM_URL" "$TARGET/ai-kit/models/$IMG_LLM_FILENAME" "$IMG_LLM_BYTES" "Qwen3-4B Q4_K_M (~2.33 GB) — FLUX.2 text encoder + AI core option"
  fi
fi

# ---------------------------------------------------------------- vault (age)
# age encryption engine — per-OS pre-built binaries (no APE polyglot).
# Sherpa pattern: one subdir per OS, binary flattened to top of that dir.
# Releases: https://github.com/FiloSottile/age/releases/tag/v1.3.1
# Archives nest under age/ (strip-components=1 lands binary directly in OS dir).
# Always-on (research D1) — no bundle.tsv knob; DOOM_INCLUDE_VAULT=1 default,
# env-var override hatch only.

AGE_VERSION="v1.3.1"
AGE_LINUX_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz"
AGE_LINUX_BYTES=6000000
AGE_MAC_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-darwin-arm64.tar.gz"
AGE_MAC_BYTES=6000000
AGE_WIN_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-windows-amd64.zip"
AGE_WIN_BYTES=6000000

if [ "${DOOM_INCLUDE_VAULT:-1}" = "1" ]; then
  echo
  echo "==> vault (age ${AGE_VERSION})"

  mkdir -p "$TARGET/ai-kit/age/linux" "$TARGET/ai-kit/age/mac" "$TARGET/ai-kit/age/win"

  if [ ! -x "$TARGET/ai-kit/age/linux/age" ]; then
    AGE_LINUX_TGZ="$TARGET/ai-kit/age/linux/age.tar.gz"
    fetch "$AGE_LINUX_URL" "$AGE_LINUX_TGZ" "$AGE_LINUX_BYTES" "age ${AGE_VERSION} linux-amd64"
    tar -xzf "$AGE_LINUX_TGZ" -C "$TARGET/ai-kit/age/linux" --strip-components=1
    rm -f "$AGE_LINUX_TGZ"
    chmod +x "$TARGET/ai-kit/age/linux/age" 2>/dev/null || true
  fi

  if [ ! -x "$TARGET/ai-kit/age/mac/age" ]; then
    AGE_MAC_TGZ="$TARGET/ai-kit/age/mac/age.tar.gz"
    fetch "$AGE_MAC_URL" "$AGE_MAC_TGZ" "$AGE_MAC_BYTES" "age ${AGE_VERSION} darwin-arm64"
    tar -xzf "$AGE_MAC_TGZ" -C "$TARGET/ai-kit/age/mac" --strip-components=1
    rm -f "$AGE_MAC_TGZ"
    chmod +x "$TARGET/ai-kit/age/mac/age" 2>/dev/null || true
  fi

  if [ ! -f "$TARGET/ai-kit/age/win/age.exe" ]; then
    AGE_WIN_ZIP="$TARGET/ai-kit/age/win/age.zip"
    fetch "$AGE_WIN_URL" "$AGE_WIN_ZIP" "$AGE_WIN_BYTES" "age ${AGE_VERSION} windows-amd64"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -j "$AGE_WIN_ZIP" -d "$TARGET/ai-kit/age/win" "*/age.exe" "*/age-keygen.exe" >/dev/null
      rm -f "$AGE_WIN_ZIP"
    else
      echo "  [warn] unzip not available; leaving age.zip for manual extraction"
    fi
  fi

  # vault/ skeleton — only the README; recovery.tar.age is user-created, not fetched
  mkdir -p "$TARGET/vault"
  [ -f "$REPO/vault/README.txt" ] && cp "$REPO/vault/README.txt" "$TARGET/vault/README.txt"
fi

# ---------------------------------------------------------------- KeePassXC (passwords)

# KeePassXC — cross-OS password manager, GPL-2.0+. v0.11.
# Linux: extract AppImage to binary + share/; macOS: ship raw .dmg (launcher
# does hdiutil at first run); Windows: flatten zip + write portable-mode .ini.
# Guard on -f (not -x): exFAT strips execute bits, -x would always re-fetch.
if [ "${DOOM_INCLUDE_PASSWORDS:-0}" = "1" ]; then
  echo
  echo "==> passwords (KeePassXC ${KEEPASSXC_VERSION})"

  # Linux — fetch AppImage, extract it, move binary + share/ into place.
  # Extraction creates squashfs-root/; we pull the binary and share/ out of it
  # and drop the AppImage + squashfs-root afterwards.
  if [ ! -f "$TARGET/ai-kit/keepassxc/linux/keepassxc" ]; then
    KEEPASSXC_LINUX_APPIMAGE="/tmp/${KEEPASSXC_LINUX_FILENAME}"
    fetch "$KEEPASSXC_LINUX_URL" "$KEEPASSXC_LINUX_APPIMAGE" "$KEEPASSXC_LINUX_BYTES" "KeePassXC ${KEEPASSXC_VERSION} linux-x86_64 AppImage"
    chmod +x "$KEEPASSXC_LINUX_APPIMAGE"
    ( cd /tmp && ./"${KEEPASSXC_LINUX_FILENAME}" --appimage-extract >/dev/null 2>&1 )
    mv /tmp/squashfs-root/usr/bin/keepassxc "$TARGET/ai-kit/keepassxc/linux/keepassxc"
    if [ -d /tmp/squashfs-root/usr/share ]; then
      cp -r /tmp/squashfs-root/usr/share "$TARGET/ai-kit/keepassxc/linux/share"
    fi
    rm -f "$KEEPASSXC_LINUX_APPIMAGE"
    rm -rf /tmp/squashfs-root
    chmod +x "$TARGET/ai-kit/keepassxc/linux/keepassxc" 2>/dev/null || true
  else
    echo "  [skip] KeePassXC linux binary already present"
  fi

  # macOS — ship raw .dmg; extraction deferred to launcher (hdiutil can't run
  # on Linux/WSL). The start-passwords.command launcher does hdiutil attach
  # at first run and copies KeePassXC.app out.
  if [ ! -f "$TARGET/ai-kit/keepassxc/mac/${KEEPASSXC_MAC_FILENAME}" ]; then
    fetch "$KEEPASSXC_MAC_URL" "$TARGET/ai-kit/keepassxc/mac/${KEEPASSXC_MAC_FILENAME}" "$KEEPASSXC_MAC_BYTES" "KeePassXC ${KEEPASSXC_VERSION} macOS arm64 dmg"
  else
    echo "  [skip] KeePassXC mac dmg already present"
  fi

  # Windows — flatten zip into ai-kit/keepassxc/win/, then write portable .ini.
  # keepassxc.ini with PortableMode=true tells KeePassXC to store config and
  # databases next to the binary instead of %APPDATA% (portable USB usage).
  if [ ! -f "$TARGET/ai-kit/keepassxc/win/KeePassXC.exe" ]; then
    KEEPASSXC_WIN_ZIP="/tmp/${KEEPASSXC_WIN_FILENAME}"
    fetch "$KEEPASSXC_WIN_URL" "$KEEPASSXC_WIN_ZIP" "$KEEPASSXC_WIN_BYTES" "KeePassXC ${KEEPASSXC_VERSION} Win64 zip"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -j "$KEEPASSXC_WIN_ZIP" -d "$TARGET/ai-kit/keepassxc/win" >/dev/null
      rm -f "$KEEPASSXC_WIN_ZIP"
      # Write portable-mode config so KeePassXC stores data next to the binary.
      # Only emit when extraction succeeded — a half-baked state (ini present,
      # exe absent) would mislead the launcher's missing-binary guard.
      cat >"$TARGET/ai-kit/keepassxc/win/keepassxc.ini" <<'KPXCINI'
[General]
PortableMode=true
KPXCINI
    else
      echo "  [warn] unzip not available; leaving $KEEPASSXC_WIN_ZIP for manual extraction"
    fi
  else
    echo "  [skip] KeePassXC windows binary already present"
  fi
fi

# ---------------------------------------------------------------- ffmpeg

# ffmpeg — GPL-3.0+. BtbN rolling-latest builds for Linux (x64 + arm64) and
# Windows; Martin-Riedl static builds for macOS arm64. v0.11.
# Guard on -f (not -x): exFAT strips execute bits.
if [ "${DOOM_INCLUDE_FFMPEG:-0}" = "1" ]; then
  echo
  echo "==> ffmpeg (${FFMPEG_VERSION})"

  # Linux — architecture-detected; DOOM_FFMPEG_LINUX_ARCH overrides (default x64).
  # Only one variant is fetched per build host. tar.xz (capital J for xz).
  # Archive nests under ffmpeg-<ver>-latest-<arch>-gpl-7.1/ so --strip-components=1
  # lands bin/ and doc/ directly; we then move bin/ffmpeg + bin/ffprobe into place.
  if [ ! -f "$TARGET/ai-kit/ffmpeg/linux/ffmpeg" ]; then
    _ffmpeg_arch="${DOOM_FFMPEG_LINUX_ARCH:-}"
    if [ -z "$_ffmpeg_arch" ]; then
      case "$(uname -m)" in
        aarch64) _ffmpeg_arch="linuxarm64" ;;
        *)       _ffmpeg_arch="linux64" ;;
      esac
    fi
    if [ "$_ffmpeg_arch" = "linuxarm64" ]; then
      _ffmpeg_linux_url="$FFMPEG_LINUXARM64_URL"
      _ffmpeg_linux_bytes="$FFMPEG_LINUXARM64_BYTES"
      _ffmpeg_linux_label="ffmpeg ${FFMPEG_VERSION} linux-arm64"
    else
      _ffmpeg_linux_url="$FFMPEG_LINUX64_URL"
      _ffmpeg_linux_bytes="$FFMPEG_LINUX64_BYTES"
      _ffmpeg_linux_label="ffmpeg ${FFMPEG_VERSION} linux-x64"
    fi
    FFMPEG_LINUX_TAR="/tmp/ffmpeg-linux.tar.xz"
    fetch "$_ffmpeg_linux_url" "$FFMPEG_LINUX_TAR" "$_ffmpeg_linux_bytes" "$_ffmpeg_linux_label"
    FFMPEG_LINUX_STAGE="/tmp/ffmpeg-linux-stage"
    mkdir -p "$FFMPEG_LINUX_STAGE"
    tar -xJf "$FFMPEG_LINUX_TAR" --strip-components=1 -C "$FFMPEG_LINUX_STAGE"
    mv "$FFMPEG_LINUX_STAGE/bin/ffmpeg"  "$TARGET/ai-kit/ffmpeg/linux/ffmpeg"
    mv "$FFMPEG_LINUX_STAGE/bin/ffprobe" "$TARGET/ai-kit/ffmpeg/linux/ffprobe"
    rm -f "$FFMPEG_LINUX_TAR"
    rm -rf "$FFMPEG_LINUX_STAGE"
    chmod +x "$TARGET/ai-kit/ffmpeg/linux/ffmpeg" "$TARGET/ai-kit/ffmpeg/linux/ffprobe" 2>/dev/null || true
  else
    echo "  [skip] ffmpeg linux binary already present"
  fi

  # macOS — Martin-Riedl arm64 static build. zip contains ffmpeg + ffprobe at root.
  if [ ! -f "$TARGET/ai-kit/ffmpeg/mac/ffmpeg" ]; then
    FFMPEG_MAC_ZIP="/tmp/ffmpeg-mac.zip"
    fetch "$FFMPEG_MAC_URL" "$FFMPEG_MAC_ZIP" "$FFMPEG_MAC_BYTES" "ffmpeg ${FFMPEG_VERSION} macOS arm64 (Martin-Riedl)"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o "$FFMPEG_MAC_ZIP" -d "$TARGET/ai-kit/ffmpeg/mac" >/dev/null
      rm -f "$FFMPEG_MAC_ZIP"
      chmod +x "$TARGET/ai-kit/ffmpeg/mac/ffmpeg" "$TARGET/ai-kit/ffmpeg/mac/ffprobe" 2>/dev/null || true
    else
      echo "  [warn] unzip not available; leaving $FFMPEG_MAC_ZIP for manual extraction"
    fi
  else
    echo "  [skip] ffmpeg mac binary already present"
  fi

  # Windows — BtbN win64-gpl build. zip nests under ffmpeg-<ver>-latest-win64-gpl-7.1/
  # so unzip -j flattens bin/ffmpeg.exe + bin/ffprobe.exe + bin/*.dll into ai-kit/ffmpeg/win/.
  if [ ! -f "$TARGET/ai-kit/ffmpeg/win/ffmpeg.exe" ]; then
    FFMPEG_WIN_ZIP="/tmp/ffmpeg-win.zip"
    fetch "$FFMPEG_WIN_URL" "$FFMPEG_WIN_ZIP" "$FFMPEG_WIN_BYTES" "ffmpeg ${FFMPEG_VERSION} win64-gpl (BtbN)"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -j "$FFMPEG_WIN_ZIP" -d "$TARGET/ai-kit/ffmpeg/win" >/dev/null
      rm -f "$FFMPEG_WIN_ZIP"
    else
      echo "  [warn] unzip not available; leaving $FFMPEG_WIN_ZIP for manual extraction"
    fi
  else
    echo "  [skip] ffmpeg windows binary already present"
  fi
fi

# ---------------------------------------------------------------- license copies (v0.11 GPL side-arms)

if [ "${DOOM_INCLUDE_PASSWORDS:-0}" = "1" ]; then
  cp "$REPO/licenses/keepassxc-NOTICE.md"       "$TARGET/ai-kit/keepassxc/NOTICE.md"
  cp "$REPO/licenses/keepassxc-LICENSE-GPL-2.0" "$TARGET/ai-kit/keepassxc/LICENSE-GPL-2.0"
fi

if [ "${DOOM_INCLUDE_FFMPEG:-0}" = "1" ]; then
  cp "$REPO/licenses/ffmpeg-NOTICE.md"       "$TARGET/ai-kit/ffmpeg/NOTICE.md"
  cp "$REPO/licenses/ffmpeg-LICENSE-GPL-3.0" "$TARGET/ai-kit/ffmpeg/LICENSE-GPL-3.0"
fi

# ---------------------------------------------------------------- passwords/ skeleton

# passwords/ landing zone — README tells user how to create their first .kdbx.
# Recovery.kdbx is user-created at runtime, not shipped. Mirror the vault/
# skeleton pattern: guard the copy with [ -f ] so re-runs are a no-op when the
# source README doesn't exist yet (V11-7 wave, coming after launchers).
mkdir -p "$TARGET/passwords"
[ -f "$REPO/passwords/README.txt" ] && cp "$REPO/passwords/README.txt" "$TARGET/passwords/README.txt" || true

# ---------------------------------------------------------------- launchers + dashboard

echo
echo "==> launchers + dashboard"

cp "$REPO/launchers/start.bat"     "$TARGET/start.bat"
cp "$REPO/launchers/start.command" "$TARGET/start.command"
cp "$REPO/launchers/start.sh"      "$TARGET/start.sh"

# Side-arm launchers — copied unconditionally so the USB layout is consistent;
# launchers themselves print a clear error if the underlying data isn't present.
for tool in whisper wiki ocr docs doom embed vault img passwords ffmpeg; do
  cp "$REPO/launchers/start-$tool.bat"     "$TARGET/start-$tool.bat"
  cp "$REPO/launchers/start-$tool.command" "$TARGET/start-$tool.command"
  cp "$REPO/launchers/start-$tool.sh"      "$TARGET/start-$tool.sh"
done

chmod +x "$TARGET/start.command" "$TARGET/start.sh" \
  "$TARGET"/start-*.command "$TARGET"/start-*.sh

cp -r "$REPO/ocr/index.html"   "$TARGET/ocr/index.html"
cp -r "$REPO/ocr/README.txt"   "$TARGET/ocr/README.txt"
cp -r "$REPO/maps/README.md"   "$TARGET/maps/README.md"
cp -r "$REPO/docs-offline/README.txt" "$TARGET/docs-offline/README.txt"

cp "$REPO/dashboard/index.html"  "$TARGET/index.html"
cp "$REPO/dashboard/mobile.html" "$TARGET/mobile.html"
cp "$REPO/dashboard/README.txt"  "$TARGET/README.txt"

# v0.8: vendored Hollama chat tab + workspace skeleton + workspace README
cp -r "$REPO/dashboard/chat/." "$TARGET/chat/"
cp    "$REPO/workspace/README.md" "$TARGET/workspace/README.md"

echo
echo "------------------------------------------------------------"
echo "  Done."
echo "  Kit assembled at: $TARGET"
echo
echo "  Next:"
echo "    Linux:    $TARGET/start.sh"
echo "    macOS:    open $TARGET/start.command"
echo "    Windows:  double-click $TARGET\\start.bat"
echo
echo "  Re-run with new settings:  $0 -i $TARGET"
echo "------------------------------------------------------------"
