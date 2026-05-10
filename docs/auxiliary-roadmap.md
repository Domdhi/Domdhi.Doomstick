# Auxiliary Equipment Roadmap

Living inventory of side-arm tools — what's shipped with the kit, what's
pending, and what's worth considering. Updated when items move between
columns. Source for this doc was the README §09 "Pending Equipment"
table, expanded with research from
[`docs/research/competition.md`](research/competition.md) and from
operational notes captured in earlier sessions.

> **Where action items live.** This doc is the *inventory* — sizes,
> ports, status, rationale. Actionable open work is mirrored in
> [`TODO.md`](../TODO.md) under "Build / improve → Greenfield zones",
> with attribution back here. When an item ships, update both
> (move it to "Shipped" here, check it off in TODO.md). Themed
> epic groupings (which side arms ship together) live in
> [`research/backlog-grouping-2026-05-09.md`](research/backlog-grouping-2026-05-09.md).

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

### v0.8 (2026-05-09) — RAG + cockpit

- **EmbeddingGemma RAG layer via redbean** — `/rag/ingest` chunks Markdown
  → embeds via llamafile (port 8769) → stores raw float32 BLOBs in
  SQLite. `/rag/query` does pure-Lua cosine top-K (no sqlite-vec — see
  CLAUDE.md gotcha "redbean lsqlite3 has no FTS5 / no load_extension").
  Round-trip ~500 ms on 1000-chunk corpus.
- **Hollama 0.35.4 vendored** at `dashboard/chat/` (MIT, 78c63850) +
  5-file adapter pattern (`_extras-*.js`) injecting `#filename`
  autocomplete, workspace dropdown, server-backed session persistence,
  3-server provider seeding, and journal sidebar.
- **Per-USB chat persistence + journal** via redbean: `/chat/save`,
  `/chat/list`, `/chat/load` (UPSERT on UUID); `/journal/append`,
  `/journal/today` (daily markdown with auto-ingest into RAG).
- **Workspace primitive** — folder convention at `workspace/<name>/docs/`
  on the USB. Drop a folder of `.md` / `.txt`, ingest, ask. Per-workspace
  scoping at every endpoint.
- **New side-arm:** `start-embed.{bat,sh,command}` runs llamafile
  `--embedding` on port 8769. EmbeddingGemma-300M Q8 (~329 MB) already
  in `models/` since v0.3 — no extra fetch.
- **New launcher:** `start.{bat,command,sh}` (chat tab).

### v0.9 (2026-05-09) — age-encrypted recovery vault

| Tool | Default size | Port | Notes |
|------|--------------|------|-------|
| **age v1.3.1 + recovery vault** | ~25 MB total (3 per-OS native Go binaries, ~9 MB each) | n/a (CLI, no port) | Per-OS binaries at `ai-kit/age/{linux,mac,win}/`. User creates `vault/recovery.tar.age` via the documented ceremony; launcher `start-vault.{sh,command,bat}` decrypts to host tmpdir to preserve POSIX `0600` on SSH keys (exFAT can't store mode bits). Air-gapped from redbean — no HTTP surface, no `/vault/decrypt` endpoint. BSD-3 license, native Go (no Cosmopolitan APE polyglot, no Defender false-positive). Full ceremony walkthrough: [`docs/vault-guide.md`](vault-guide.md). On-USB short reference: `vault/README.txt`. KeePassXC Portable deferred (no target version set — would force a Windows-only caveat that breaks the kit's same-files-everywhere axiom). |

**Key decisions** (full rationale in [`docs/research/v0.9-vault-security-2026-05-09.md`](research/v0.9-vault-security-2026-05-09.md)):
- Always-on (no `bundles.tsv` knob) — 25 MB doesn't warrant a wizard prompt; `DOOM_INCLUDE_VAULT=1` env-var override is the suppression hatch.
- Decrypt to host tmpdir, NOT to USB — exFAT strips POSIX mode bits.
- Passphrase-only default; YubiKey + FIDO2 ceremonies documented but not bundled (hardware-required ceremonies kill the "plug into a stranger's machine" axiom).
- No auto-cleanup or auto-re-encrypt — both are footguns; cleanup is explicit.

### v0.10 (2026-05-10) — offline image generation

| Tool | Default size | Port | Notes |
|------|--------------|------|-------|
| **stable-diffusion.cpp `master-596-90e87bc` + FLUX.2 klein 4B Q4\_K\_M** | ~5.0 GB total (~60 MB per-OS sd-cli + libstable-diffusion + 2.43 GB transformer GGUF + 238 MB VAE safetensors + 2.33 GB Qwen3-4B text encoder) | n/a (CLI, no port) | Per-OS native binaries at `ai-kit/sd-img/{linux,mac,win}/`. FLUX.2 klein 4B Q4\_K\_M transformer GGUF + small-decoder VAE safetensors at `ai-kit/sd-img/models/`. Qwen3-4B Q4\_K\_M text encoder at `ai-kit/models/` — same file doubles as the lightest AI core option in `start.{sh,bat,command}` picker (runtime-detected menu choice [3]). Recipe: `sd-cli --diffusion-model … --vae … --llm … --steps 4 --cfg-scale 1.0 --sampling-method euler --diffusion-fa --offload-to-cpu` per [`sd.cpp/docs/flux2.md`](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux2.md). All Apache-2.0. Launcher `start-img.{sh,command,bat}` reads a prompt from stdin, writes a 1024×1024 PNG to the USB root. Standalone — no redbean coupling, no port allocated. ~1-3 min per image on CPU; ~8-10 GB working RAM (transformer + Qwen3 + VAE all loaded). Model pivoted from original SDXL Turbo Q4 plan (see rationale below). Full usage guide: [`docs/img-guide.md`](img-guide.md). |

**Why FLUX.2 klein, not SDXL Turbo Q4?** The original pending entry specified SDXL Turbo Q4\_K\_M. At ship time, no Q4\_K\_M quantization of SDXL Turbo exists as a downloadable GGUF — the closest available is Q8\_0 at ~4 GB, and that file is distributed under the Stability AI Community License (registration required, no redistribution, no commercial use). FLUX.2 klein 4B (Black Forest Labs, January 2026) solves both problems: it has an Apache-2.0 license (clean for redistribution) and is supported by stable-diffusion.cpp since 2026-01-18. It is a 4-step distilled model with quality comparable to SDXL Turbo. The catch discovered during v0.10 verification: FLUX.2 is multi-file, NOT a single-file all-in-one — it needs a companion VAE (~238 MB) and a Qwen3-4B text encoder (~2.33 GB) supplied via `--vae` and `--llm` flags. Total image-gen footprint ~5 GB (transformer + VAE + Qwen3) versus SDXL Turbo Q8\_0's single 4 GB file, but the Qwen3 doubles as a kit-wide AI core option, recovering most of the size cost.

**Launcher design decision:** `start-img` does not route through redbean. A single image generation blocks the process for 60-180 seconds; tying up the shared redbean instance for that window would stall DOOM saves, TTS, RAG queries, and journal writes for all other customers. The launcher invokes sd-cli directly as a subprocess and writes output to the USB root.

**Bonus AI core option:** Because FLUX.2 klein's `--llm` flag wants a Qwen3-class encoder, the kit ships Qwen3-4B Q4\_K\_M (~2.33 GB) at `ai-kit/models/` rather than burying it inside `sd-img/`. The `start.{sh,bat,command}` AI core picker runtime-detects this file and offers it as a 3rd menu option (Gemma 4 E4B / Gemma 4 26B / Qwen3 4B). Hollama picks it up automatically via llamafile's `/v1/models`. Tiny/balanced bundles without image gen don't ship Qwen3 — picker gracefully shows 2 options.

---

## Pending — high payoff (next picks)

Ranked by "value per gigabyte" given the prepper / off-grid framing.

---

## Pending — lower payoff (nice-to-haves)

| Item | Size | Notes |
|------|------|-------|
| **Project Gutenberg subset + Calibre Portable** | ~3 GB | A few thousand classic books. Calibre Portable is Win-only. Could ship .epub directly + recommend a portable reader per OS. |
| **Static ffmpeg** | ~80 MB | Audio/video swiss-army. Pairs with whisperfile for live captions, with `sd-img` for animated outputs. |
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

Shipped v0.8 (2026-05-09) — see "v0.8 — RAG + cockpit" above. Architecture
pivoted from sqlite-vec to pure-Lua cosine over BLOB columns at Wave 0 D4
(redbean's lsqlite3 has no FTS5 and no `load_extension`).

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

The kit version (currently `v0.10`) ticks when a side-arm or platform
batch ships. Recent cadence: v0.4 first side arms (2026-05-07) → v0.5
redbean + DOOM + wizard (2026-05-07) → v0.6 USB-resident DOOM saves
(2026-05-08) → v0.7 TTS via Sherpa-ONNX + Supertonic (2026-05-08) →
v0.8 EmbeddingGemma RAG + chat tab (2026-05-09) → v0.9 age-encrypted
recovery vault (2026-05-09) → v0.10 offline image generation (2026-05-10).

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
a tmp dir (e.g. `/tmp/doomstick-ci`) and verify all side arms launch and respond on their
respective ports / open the expected pages. v0.7 adds a `/tts` smoke
(POST text/plain → assert WAV magic header `RIFF...WAVE`); v0.6 adds a
DOOM `/save` round-trip smoke.
