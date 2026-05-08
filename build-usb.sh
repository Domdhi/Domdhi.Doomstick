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
  $0 ./usb-layout                Local dry-run target
  $0 -y /mnt/usb                 CI / scripted builds

Defaults / 'full' bundle download size:
  AI core    ~22.3 GB   (43 MB runtime + 5 GB E4B + 17 GB 26B + 329 MB embed)
  Side arms  ~ 560 MB   (whisperfile + kiwix + simple-en zim + tesseract + monaco pbf)
  Total      ~22.9 GB

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
  DOOM_ZIM_URL="https://download.kiwix.org/zim/wikipedia/wikipedia_en_simple_all_nopic_2024-06.zim"
  DOOM_ZIM_FILE="wikipedia_en_simple_all_nopic_2024-06.zim"
  DOOM_ZIM_BYTES=395000000
  DOOM_ZIM_LABEL="Simple English"

  DOOM_INCLUDE_OSM=1
  DOOM_PBF_URL="https://download.geofabrik.de/europe/monaco-latest.osm.pbf"
  DOOM_PBF_FILE="monaco-latest.osm.pbf"
  DOOM_PBF_BYTES=700000

  DOOM_INCLUDE_WHISPER=1
  DOOM_WHISPER_URL="https://huggingface.co/Mozilla/whisperfile/resolve/main/whisper-base.en.llamafile?download=true"
  DOOM_WHISPER_FILE="whisper-base.en.llamafile"
  DOOM_WHISPER_BYTES=148000000
  DOOM_WHISPER_LABEL="base.en"

  DOOM_INCLUDE_OCR=1
  DOOM_OCR_LANGS="eng"

  DOOM_INCLUDE_DOCS=1

  DOOM_INCLUDE_REDBEAN=1
  DOOM_INCLUDE_DOOM=1
  DOOM_INCLUDE_TTS=1
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
  # Schema (post v0.7):
  #   1 label  2 e4b  3 moe  4 emb  5 wiki  6 osm  7 whisper  8 ocr  9 docs
  #   10 redbean  11 doom  12 tts  13 zim_idx  14 osm_idx  15 whisper_idx
  #   16 est  17 summary
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
  local zim_idx osm_idx whisper_idx
  zim_idx="$(tsv_field "$row" 13)"
  osm_idx="$(tsv_field "$row" 14)"
  whisper_idx="$(tsv_field "$row" 15)"

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
  [ "${DOOM_INCLUDE_TTS:-0}" = "1" ]     && total=$((total + 210000000))  # sherpa runtime (3× ~30 MB) + Supertonic int8 (~120 MB)
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
  "$TARGET/zim" \
  "$TARGET/maps" \
  "$TARGET/ocr/lib" \
  "$TARGET/ocr/lang-data" \
  "$TARGET/docs-offline" \
  "$TARGET/doom"

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
# Linux/macOS ship as multi-file tar.bz2 (binary + .so/.dylib next to it);
# Windows ships as a single standalone .exe. Pin to v1.13.1 (released
# 2026-05-08) — Supertonic supported since v1.12.29. Update version, sizes,
# and any new platform binaries here when bumping.
SHERPA_VERSION="v1.13.1"
SHERPA_LINUX_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-linux-x64-shared.tar.bz2"
SHERPA_LINUX_BYTES=30000000
SHERPA_MAC_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-osx-arm64-shared.tar.bz2"
SHERPA_MAC_BYTES=30000000
SHERPA_WIN_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-non-streaming-tts-x64-${SHERPA_VERSION}.exe"
SHERPA_WIN_BYTES=20400000

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
if [ "${DOOM_INCLUDE_REDBEAN:-0}" = "1" ]; then
  fetch "$REDBEAN_URL" "$TARGET/ai-kit/redbean/$REDBEAN_FILE" "$REDBEAN_BYTES" "redbean 3.0.0 (~5.5 MB)"
  chmod +x "$TARGET/ai-kit/redbean/$REDBEAN_FILE"
  cp "$REPO/redbean/.init.lua"  "$TARGET/ai-kit/redbean/.init.lua"
  cp "$REPO/redbean/README.txt" "$TARGET/ai-kit/redbean/README.txt"

  # Bake .init.lua into the redbean.com polyglot's appended zip. redbean
  # reads .init.lua from its asset zip — `-D <docroot>` overlays static
  # files but does NOT expose .init.lua as an asset, and the `-A` flag is
  # broken in 3.0.0 (StoreAsset regression on Arm64 work). zip-appending is
  # the documented approach and what `--assimilate` does internally.
  # Doing this on the *target* binary, not the repo source, so the canonical
  # fetched binary stays untouched.
  if command -v zip >/dev/null 2>&1; then
    ( cd "$TARGET/ai-kit/redbean" && zip -q "$REDBEAN_FILE" .init.lua )
    echo "  baked .init.lua into $TARGET/ai-kit/redbean/$REDBEAN_FILE"
  else
    echo "  WARNING: 'zip' not found — redbean will not load .init.lua at runtime."
    echo "           Install zip (apt: zip / brew: zip / mac: ships in xcode-select) and re-run."
  fi
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

# ---------------------------------------------------------------- TTS

# Sherpa-ONNX runtime + Supertonic int8 model. v0.7 customer of redbean's
# /tts route (port 8768). Native C++ binaries per OS (no Python on host).
if [ "${DOOM_INCLUDE_TTS:-0}" = "1" ]; then
  echo
  echo "==> tts (sherpa-onnx + supertonic)"

  # Linux runtime — multi-file shared tarball. Extract to ai-kit/sherpa-tts/linux/.
  if [ ! -x "$TARGET/ai-kit/sherpa-tts/linux/sherpa-onnx-offline-tts" ]; then
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
  if [ ! -x "$TARGET/ai-kit/sherpa-tts/mac/sherpa-onnx-offline-tts" ]; then
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

  # Windows runtime — single statically-built .exe. No extraction.
  if [ ! -f "$TARGET/ai-kit/sherpa-tts/win/sherpa-onnx-offline-tts.exe" ]; then
    fetch "$SHERPA_WIN_URL" "$TARGET/ai-kit/sherpa-tts/win/sherpa-onnx-offline-tts.exe" "$SHERPA_WIN_BYTES" "sherpa-onnx ${SHERPA_VERSION} win-x64 (single .exe)"
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

# ---------------------------------------------------------------- launchers + dashboard

echo
echo "==> launchers + dashboard"

cp "$REPO/launchers/start.bat"     "$TARGET/start.bat"
cp "$REPO/launchers/start.command" "$TARGET/start.command"
cp "$REPO/launchers/start.sh"      "$TARGET/start.sh"

# Side-arm launchers — copied unconditionally so the USB layout is consistent;
# launchers themselves print a clear error if the underlying data isn't present.
for tool in whisper wiki ocr docs doom; do
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
cp "$REPO/dashboard/README.txt"  "$TARGET/README.txt"

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
