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

## Shipped (v0.4 · 2026-05-07)

| Tool | Default size | Port | Notes |
|------|--------------|------|-------|
| **Whisperfile** | ~148 MB (`base.en`) | 8766 | Mozilla Cosmopolitan APE bundle. `--gui` mode serves a drop-an-audio-file UI. |
| **Tesseract.js OCR** | ~15 MB (eng) | `file://` | Pure-browser via `ocr/index.html`. CDN dependencies vendored at build time so the page is fully offline thereafter. |
| **Kiwix + Wikipedia** | ~395 MB (Simple EN) | 8767 | `kiwix-serve` per-OS binary; serves any `zim/*.zim` it finds. Drop more ZIMs to extend. |
| **DevDocs** | varies | `file://` | Not auto-fetched. Manual setup via [`docs/setup-devdocs.md`](setup-devdocs.md) — the launcher opens whatever's in `docs-offline/`. |
| **Organic Maps + .pbf** | ~700 KB (Monaco placeholder) | mobile-only | OSM regional data; sideload to phone. See [`maps/README.md`](../maps/README.md) to swap region. |

**Aggregate cost over the v0.3 baseline:** about 560 MB to the kit's
default footprint. Bumping the Wikipedia ZIM to `wikipedia_en_top_nopic`
(~6 GB) and a real-region `.pbf` (~700 MB) pushes the total to ~29 GB —
still under any sensibly-sized USB stick.

---

## Pending — high payoff (next picks)

Ranked by "value per gigabyte" given the prepper / off-grid framing.

### 🥇 redbean — single-file APE webserver with Lua + SQLite (~6 MB)

The natural pair to llamafile. Same author (Justine Tunney), same
Cosmopolitan APE polyglot. Adds:

- A real HTTP server we can put behind the cockpit (replacing direct
  `file://` for tools that need server-side state).
- Lua scripting for the agent loop — periodic vault janitor, daily
  summarizer, RAG indexer — without needing a host runtime.
- SQLite handlers for persistent chat history, RAG index, journal
  metadata. Eliminates Hollama's localStorage gotcha.

**Why we haven't shipped yet:** until v0.4, no tool actually needed
server-side state. Once the RAG layer or agent loop ships, redbean is
the obvious server to put them behind. Defer until then.

### 🥇 Piper TTS — text → audio (~100 MB for one English voice)

Completes the voice stack that whisperfile started. Pipeline:

```
mic → whisperfile → llamafile (Gemma 4) → piper → speaker
```

End-to-end voice assistant, fully offline, no API keys. None of the 12
projects we surveyed in `docs/research/competition/` ship this. Real
differentiator surface.

**Implementation sketch:** download Piper's static x86_64 binary +
one voice model (e.g. `en_US-amy-medium.onnx`, ~60 MB).
Add `start-tts.{bat,sh,command}` and a small bridge page that records
mic, posts to whisperfile, posts the transcript to llamafile, plays the
piped output. ~1 day's work after Piper binaries are pinned.

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

This is in the existing TODO under "Build / improve" but worth
re-listing here once redbean lands — RAG over `workspace/` is the
single biggest functional upgrade left to make on the kit.

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

The kit version (`v0.4`) ticks when a side-arm batch ships. Side-arm
sizes / URLs in `build-usb.{sh,ps1}` are pinned to a known release
because:

- Hugging Face occasionally re-quantizes shards (changes file size).
- Geofabrik regional `.pbf` URLs are stable but file contents update
  daily — not a problem for us (any vintage works) but worth noting.
- Kiwix-tools and Wikipedia ZIM filenames embed dates; bump them
  intentionally per kit version.

If we add CI for the kit, the smoke test should run `build-usb` against
`./usb-layout/` and verify all five side arms launch and respond on
their respective ports / open the expected pages.
