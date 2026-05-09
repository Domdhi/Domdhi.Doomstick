# Auxiliary Equipment Roadmap

Living inventory of side-arm tools — what's shipped with the kit, what's
pending, and what's worth considering. Updated when items move between
columns. Source for this doc was the README §09 "Pending Equipment"
table, expanded with research from
[`docs/research/competition.md`](research/competition.md) and from
operational notes captured in earlier sessions.

The kit's organizing principle for side arms: each tool gets its own
launcher, its own port (or `file://`), its own `ai-kit/<tool>/` folder
or top-level data dir, and never collides with the AI core (port 8765).
Tools are independent — running them in parallel works.

---

## Shipped

### v0.4 (2026-05-07) — first side-arm batch

| Tool | Default size | Port | Notes |
|------|--------------|------|-------|
| **Whisperfile** | ~497 MB (`small.en`) | 8766 | Mozilla Cosmopolitan APE bundle. `--gui` mode serves a drop-an-audio-file UI. Default flipped from `base.en` to `small.en` on 2026-05-08 after Mozilla removed `base.en` from the upstream HF repo; wizard offers tiny/small/medium with a RAM-cost hint. |
| **Tesseract.js OCR** | ~15 MB (eng) | `file://` | Pure-browser via `ocr/index.html`. CDN dependencies vendored at build time so the page is fully offline thereafter. |
| **Kiwix + Wikipedia** | ~395 MB (Simple EN) | 8767 | `kiwix-serve` per-OS binary; serves any `zim/*.zim` it finds. Drop more ZIMs to extend. |
| **DevDocs** | varies | `file://` | Not auto-fetched. Manual setup via [`docs/setup-devdocs.md`](setup-devdocs.md) — the launcher opens whatever's in `docs-offline/`. |
| **Organic Maps + .pbf** | ~700 KB (Monaco placeholder) | mobile-only | OSM regional data; sideload to phone. See [`maps/README.md`](../maps/README.md) to swap region. |

### v0.5 (2026-05-07) — platform layer + DOOM + interactive build

| Tool | Default size | Port | Notes |
|------|--------------|------|-------|
| **redbean** | ~6 MB | 8768 | Single-file APE webserver with Lua + SQLite (Justine Tunney). `redbean/.init.lua` ships `/health` plus stubs for `/save /load /list /tts /rag`. Foundation for every subsequent server-side customer. **Note:** `.init.lua` is read from the appended zip inside `redbean.com`, NOT from disk — see CLAUDE.md "redbean reads `.init.lua` from its appended zip". |
| **DOOM (Dwasm + shareware DOOM1.WAD)** | ~10 MB | 8768 (via redbean) | PrBoom+ via emscripten, served at `/doom/`. `doom/` is a GPL-2.0 subdirectory; license boundary documented in `doom/NOTICE.md`. |
| **Interactive `build-usb` wizard** | n/a | n/a | Bundle prelude (`tiny / balanced / full / custom`) + 6 per-knob prompts (models, ZIM, OSM region, Whisper variant, OCR langs, DevDocs). Writes `<target>/build-usb-config.sh` for deterministic re-runs. Modes: default wizard, `-y`, `-c`, `-i`, `-n`. Menu data in shared `presets/*.tsv`. |

### v0.6 (2026-05-08) — USB-resident DOOM saves

| Customer | Backend | Notes |
|----------|---------|-------|
| **redbean `/save /list /load`** | SQLite at `ai-kit/redbean/saves.db` | Schema: `saves(slot INTEGER PRIMARY KEY 0..5, name TEXT, data BLOB, updated_at TEXT)`. Client: `doom/index.html` pre-fetches saves on boot, hooks `FS.trackingDelegate.onCloseFile` (+ wraps `FS.close` as backup) to POST `doomsavN.dsg` writes back to redbean. Saves now travel with the USB across hosts. |

### v0.7 (2026-05-08) — TTS, no Python on host

| Tool | Default size | Port | Notes |
|------|--------------|------|-------|
| **Sherpa-ONNX + Supertonic int8** | ~210 MB total (~120 MB shared model + ~90 MB binaries combined across 3 OSes) | 8768 (via redbean `/tts`) | Native C++ runtime per OS at `ai-kit/sherpa-tts/{linux,mac,win}/`. Win = single statically-built `.exe` (~20 MB); Linux/Mac = binary + `.so`/`.dylib` siblings (~30 MB each). Supertonic int8 ONNX bundle shared at `ai-kit/sherpa-tts/models/supertonic/` (~99M params). POST `text/plain` → `audio/wav`. Live smoke 2026-05-08: 416 KB WAV in 629 ms (faster-than-realtime). |

**Why not Piper or Kokoro?** Originally selected Kokoro-82M (TTS Arena #1) but
its reference runtime is the `kokoro` Python package + ONNX Runtime —
violates "no Python as runtime requirement on the host" rule. Shipping
portable Python on the USB across Win/Mac/Linux is multi-day per-OS
packaging work. Sherpa-ONNX is the same per-OS native-binary pattern
Whisperfile and Kiwix already use. Supertonic 3 (~99M params, RTF 0.3 on
a literal e-reader) is the same speed class as Kokoro. Trade-off: lose
"TTS Arena #1" marketing line, gain ship-clean against the Avoid rule.
Full rationale in CLAUDE.md "TTS — per-OS native binaries" gotcha.

Piper was the original v0.3-era candidate but never shipped — superseded
by Sherpa+Supertonic in v0.7.

**Voice loop status:** mic → whisperfile → llamafile (Gemma 4) → sherpa-tts
→ speaker is now end-to-end shippable. None of the 12 surveyed projects
in `docs/research/competition/` ship this combo.

**Aggregate cost over the v0.3 baseline:** about 785 MB to the kit's
default footprint (560 MB v0.4 side arms + ~6 MB redbean + ~10 MB DOOM +
~210 MB sherpa-tts). Bumping the Wikipedia ZIM to `wikipedia_en_top_nopic`
(~6 GB) and a real-region `.pbf` (~700 MB) pushes the total to ~29 GB —
still under any sensibly-sized USB stick. Adding the EmbeddingGemma 300M
Q8 model already shipped in `models/` puts the AI core (E4B + 26B + Embed)
at ~22.3 GB on top.

---

## Pending — high payoff (next picks)

Ranked by "value per gigabyte" given the prepper / off-grid framing.

### 🥇 EmbeddingGemma RAG layer via redbean `/rag/{ingest,query}` (3–5 days)

The wedge nobody else has matched. Designed and queued for the next `/do`.

- **Vector store:** sqlite-vec (asg017/sqlite-vec) — embeds vectors
  directly in SQLite alongside the existing saves DB. No extra runtime,
  no separate process. Same on-disk pattern as v0.6 DOOM saves.
- **Chunking:** recursive 512-token split with 15% overlap, metadata-enriched.
- **Embeddings:** llamafile's `--embedding` mode against the
  EmbeddingGemma-300M Q8 GGUF (~329 MB, already shipped in `models/`).
- **Endpoints:** `POST /rag/ingest`, `GET /rag/query`. Currently 501 stubs
  in `redbean/.init.lua`.
- **Implementation pattern:** copy `TtsHandler` shape (line 271+ of
  `redbean/.init.lua`) for the subprocess half (embedding ingest);
  `SaveHandler` shape for the SQLite half. Both are worked examples in
  the same file.

Full design: [`docs/research/tts-rag-2026-05-08.md`](research/tts-rag-2026-05-08.md).
Pairs with the journaling tab and the agent layer in `TODO.md` "Build /
improve" → unlocks both.

---

## Pending — medium payoff

### 🥈 stable-diffusion.cpp + SDXL Turbo Q4 (~3 GB)

Offline image generation. The `stable-diffusion.cpp` runtime is a small
C++ binary (~5 MB), the model is the bulk. SDXL Turbo Q4_K_M is the
sweet spot: good quality, ~3 GB, runs on CPU.

**Why not yet:** the dashboard's prepper / survival framing doesn't
naturally cover image gen — it's a "fun" tool more than a "knowledge in
a tin" tool. Defer until v0.5 when we have the cockpit story sorted.

### 🥈 age-encrypted recovery vault (negligible size)

A `vault.tar.age` at the USB root containing dotfiles, SSH/GPG keys,
2FA backup codes, scanned ID copies. The recipe is the encryption
ceremony, not the data — vault contents are entirely user-supplied.

The kit ships:
- `age` binary (~1 MB, static, cross-OS)
- `vault/README.md` with the encryption + decryption ritual
- A blank passphrase prompt at first run

**Why not yet:** uncontroversial, easy to ship — just hasn't bubbled to
the top of the queue. Could land in any v0.x release.

---

## Pending — lower payoff (nice-to-haves)

| Item | Size | Notes |
|------|------|-------|
| **Project Gutenberg subset + Calibre Portable** | ~3 GB | A few thousand classic books. Calibre Portable is Win-only. Could ship .epub directly + recommend a portable reader per OS. |
| **Static ffmpeg** | ~80 MB | Audio/video swiss-army. Pairs with whisperfile for live captions, with stable-diffusion for animated outputs. |
| **Bigger Wikipedia ZIMs** | up to ~50 GB | The launcher already picks up any `zim/*.zim`. Add a build-script flag to fetch `wikipedia_en_top_nopic` (~6 GB) or the full `wikipedia_en_all_nopic` (~50 GB). |
| **Multilingual Kiwix** | varies | Per-language ZIM selection. Build script needs a config knob. |
| **Bootable rescue ISOs + Ventoy** | 5–20 GB | Currently BYO. Could pre-populate `iso/` and ship a Ventoy installer. |
| **Portable dev tools bundle** | ~200 MB | PortableGit, ripgrep, fzf, jq, 7-Zip, VS Code Portable. Currently BYO. |

---

## Pending — newly identified (v0.4 brainstorm)

Items not in the original §09 menu but worth scoping next time we sit
with the backlog.

### Offline TLS root certificate bundle

Most of the offline stack is HTTP, but the moment any side arm reaches
to an upstream server (air-gap testing, RSS reader, etc.) you need a
local CA bundle. Ship `cacert.pem` from `curl.se/ca/cacert.pem`
(~250 KB) under `ai-kit/certs/` so anything we add later that does
HTTPS has a sane default.

### Per-OS portable browser (Firefox / Chromium)

Hollama, our OCR page, the Kiwix UI, and DevDocs all run in the host's
browser. If the host doesn't have one (cleanroom recovery scenario),
a bundled portable browser is a ~120 MB add per OS. Three OSes = ~360
MB total. Trade-off: real survival utility vs. sizeable disk hit.

### "Field manual" markdown corpus

The DOOMSTICK marketing leans hard on the prepper framing but the kit
doesn't actually ship any survival reference material. A small curated
markdown bundle (~50 MB) with first-aid, knot-tying, edible-plants,
amateur-radio basics, hand-pumped well diagnostics, etc., would be
high-signal for the prepper audience. Either curated by us or pulled
from public-domain field manuals (USACE, Red Cross PDFs).

### Hardware diagnostic toolkit

memtest86, Hiren's BootCD PE, smartmontools — for "the laptop is
acting weird, is it the RAM?" scenarios. Mostly ISOs that pair with
Ventoy. Not really new but worth grouping under "diagnostics" with
its own dashboard card.

### Local-first password manager (KeePassXC Portable)

`vault/` covers SSH/GPG keys; KeePassXC covers website passwords.
Ships as portable .exe per OS, ~30 MB. Pairs with the age vault.

### `redbean`-hosted RAG over the journal/workspace

Promoted to "Pending — high payoff" #1 above now that redbean has shipped
(v0.5) and its `/rag` endpoints are in-place as 501 stubs ready to fill in.

---

## Anti-patterns (don't ship)

- **Anything Electron-per-OS.** ~120–250 MB per platform = 360–750 MB
  cross-OS for one feature. Tauri or static SPA only.
  ([Cherry Studio, AnythingLLM, Obsidian](research/competition.md))
- **Anything that runs only on Windows.** Llamafile's cross-OS APE is
  the moat. Side arms that regress to per-OS binaries are tolerable
  (kiwix-serve, Piper, Ventoy) only if they're tiny and the per-OS
  overhead is negligible.
- **Anything requiring a host Python / Node / Docker / JRE.** Every
  required runtime is a host that won't run our kit.
- **Anything that downloads more on first run.** Pre-stage everything
  in `build-usb`. Auxiliary tools must work fully offline after the
  USB is built.
- **Anything paywalled or freemium.** Smart Connections is a cautionary
  tale (free tier paywalls OpenAI-compat — useless to us).
- **Anything that writes to `%APPDATA%` / `~/.config` with no override
  flag.** Side-arm config and state must live next-to-binary so it
  rides the USB.

---

## Versioning notes

The kit version (currently `v0.7`) ticks when a side-arm or platform
batch ships. Recent cadence: v0.4 first side arms (2026-05-07) → v0.5
redbean + DOOM + wizard (2026-05-07) → v0.6 USB-resident DOOM saves
(2026-05-08) → v0.7 TTS via Sherpa-ONNX + Supertonic (2026-05-08).

Side-arm sizes / URLs in `build-usb.{sh,ps1}` are pinned to a known
release because:

- Hugging Face occasionally re-quantizes shards (changes file size).
- Geofabrik regional `.pbf` URLs are stable but file contents update
  daily — not a problem for us (any vintage works) but worth noting.
- Kiwix-tools and Wikipedia ZIM filenames embed dates; bump them
  intentionally per kit version.

**Known URL drift (resolved 2026-05-08):** the whisperfile fetch URL for
`whisper-base.en.llamafile` returned 404 — Mozilla had deleted that variant
from the upstream HF repo. Default flipped to `whisper-small.en.llamafile`
(byte-verified, ~497 MB). Tiny / small / medium .en variants remain; large
multilingual variants exist but aren't in the wizard. See `TODO.md` "Build
script & deploy bugs (closed)".

If we add CI for the kit, the smoke test should run `build-usb` against
`./usb-layout/` and verify all side arms launch and respond on their
respective ports / open the expected pages. v0.7 adds a `/tts` smoke
(POST text/plain → assert WAV magic header `RIFF...WAVE`); v0.6 adds a
DOOM `/save` round-trip smoke.
