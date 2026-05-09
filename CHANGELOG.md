# Changelog

All notable changes to the Doomstick kit are documented here. See [README.md](../README.md) for project overview.

Format based on [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased]

### Queued for v0.8+
- **EmbeddingGemma RAG layer** — `/rag/ingest` and `/rag/query` endpoints on redbean, backed by sqlite-vec. Uses EmbeddingGemma-300M (already shipped). Estimated effort: 3-5 days.

---

## [v0.7.3] — 2026-05-08

*Build-script fixes surfaced by Windows end-to-end verification. Kit behavior unchanged when freshly built; this release prevents future builds from regressing the Windows path.*

### Fixed
- **`build-usb.ps1` polyglot zip-bake destroyed APE prelude** — `[ZipFile]::Open(..., Update)` treated `redbean.com` as a pure zip and rewrote it from offset 0 on dispose, silently producing a 3.5 MB pure-zip output instead of the 8.7 MB MZ-prefixed polyglot. Windows then refused to launch the resulting `redbean.com.exe` ("not a valid application"). New `Invoke-PolyglotZipBake` function captures the prelude pre-bake, re-prepends post-bake, and shifts EOCD + every CD entry's local-header-offset by `+preludeSize` so the polyglot remains well-formed. Pre-flight refuses non-MZ inputs; post-flight asserts MZ magic + sane size as a fail-loud guard.
- **`launchers/start-whisper.{bat,sh,command}` sent rejected `--gui` flag** — Whisperfile rejects the flag and the launcher would have failed end-to-end. `--host`/`--port` alone runs whisperfile in HTTP server mode by default.

### Verified
- **End-to-end Windows verification** — Twelve automated tests (USB layout, sherpa CLI binary type, redbean health, DOOM serving, save round-trip, TTS WAV out, TTS edge cases, AI core E4B, whisperfile, kiwix, OCR, dashboard) all passing on a real exFAT USB. Voice loop confirmed: POST text/plain "hello world this is doomstick" to `:8768/tts` → HTTP 200, 219 KB audio/wav in 1.48 s with `RIFF`/`WAVE` magic intact.

---

## [v0.7.2] — 2026-05-08

*"Phone home" — first-class mobile experience. The phone is now a consumer of the kit's data, not an afterthought.*

### Added
- **Mobile-aware dashboard** — `dashboard/index.html` UA-detects mobile (`pointer:coarse` matchMedia + `/Mobi|Android|iPhone|iPad/` UA fallback) and swaps the desktop launcher cards for a Mobile Field Kit section with six curated app cards: Kiwix Reader, Organic Maps, PocketPal AI, OCR (in-browser), DOOM (in-browser), DevDocs. F-Droid / Play Store / App Store links per app where available.
- **DOOM touch controls** — `doom/index.html` got an on-screen D-pad (move) + FIRE/USE/WPN/MENU action cluster. Visible only on `(pointer:coarse)` devices. Buttons synthesize `KeyboardEvent`s into PrBoom's existing input layer — no engine fork. Hold-style buttons bind `pointerdown` to keydown and all four release variants (`pointerup`/`leave`/`cancel`/`out`) to keyup so keys never get stuck pressed when a finger slides off a button. Pointer-lock force-disabled on mobile (broken in mobile browsers; steals taps from overlay).
- **OCR camera capture** — `ocr/index.html` got `<input capture="environment">` for direct rear-camera capture on phones plus a paste-from-clipboard handler for screenshot OCR. The "Take Photo" button is hidden on desktop via `(pointer:coarse)` media query.
- **`dashboard/mobile.html` shim** — Tiny meta-refresh page deployed to USB root as a phone-friendly entry point. Redirects to `index.html#mobile` so a phone user browsing the USB in a file manager has an obvious starting point.

### Decided
- **Mobile is a consumer, not a host** — APE polyglots (llamafile, redbean, whisperfile, sherpa CLI) are desktop ABIs only; phones have different ABIs and sandboxed app models. The "single-binary cross-OS APE moat" stops at desktop. Every shipped *data asset* (ZIM, OSM PBF, GGUF, OCR, DOOM, DevDocs) becomes first-class on phones via curated consumer apps, not by shipping native phone runtimes. AI-on-Android remains a separate future project, not a Doomstick milestone.

---

## [v0.7.1] — 2026-05-08

*Windows-path completion. Three interlocking build-pipeline bugs that only surfaced on real Windows.*

### Fixed
- **Sherpa-ONNX Windows binary mismatch** — Build was fetching `sherpa-onnx-non-streaming-tts-x64-v<ver>.exe` which is the **GUI app** ("Text-to-Speech with Next-gen Kaldi" window), not the CLI tool the redbean TtsHandler invokes. Confirmed live: running it as a subprocess produced the "Cannot find ./model.onnx" help-block exit. Switched to the per-OS multi-file `sherpa-onnx-v1.13.1-win-x64-shared-MT-Release.tar.bz2` archive (~23 MB) and refactored Windows extraction to mirror Linux/macOS (`tar -xjf` + flatten `bin/` and `lib/` into the OS dir so DLL search finds `onnxruntime.dll` next to the binary). Picked **MT-Release** (static CRT) over MD-Release so the kit runs on hosts without the Visual C++ Redistributable installed.
- **Existence-check now requires both binary AND `onnxruntime.dll`** — Without the dual-file check, kits with the old GUI binary at the same filename would skip refetching on the next build. Dual-file guard is self-healing on next build.
- **DrvFs zip-bake atomic-rename failure** — `zip`'s in-place update creates a `ziXXXXXX` temp then atomic-renames to the target — fails on WSL DrvFs/exFAT, leaves the original gone and the temp file orphaned. `build-usb.sh` now stages in `$(mktemp -d)` ext4 dir and plain-`cp`'s the result back; sweeps `zi??????` orphans on entry.
- **DOOM 403 on exFAT via redbean-zip-bake + empty webroot** — Cosmopolitan's `stat()` on Windows-mounted exFAT strips group/other bits (mode `0100600` for files, `040700` for dirs), failing redbean's static-serve "other readable" check → 403 on `/doom/index.html`. Two-part fix: bake `doom/*` into `redbean.com`'s appended zip alongside `.init.lua` (zip assets skip the filesystem permission check), and point `-D` at a dedicated empty `ai-kit/redbean/webroot/` so redbean doesn't find the on-disk `D:\doom\` via implicit-CWD-docroot. Launchers updated to mkdir the webroot and open `/doom/index.html` directly (zip-only mode doesn't auto-resolve trailing slash to `index.html`).
- **`start-doom.bat` ASCII-clean** — Replaced em-dash and middle-dot with ASCII hyphens; cmd CP437 was rendering them as `ΓçÆ` and `π` mojibake.
- **`redbean.com.exe` sync after zip-bake** — Build scripts now `cp redbean.com → redbean.com.exe` after baking. Without this, Windows would launch the stale .exe (start-doom.bat's `if not exist .exe copy` only fires on first run).
- **Whisperfile fetch URL refresh** — Mozilla deleted `whisper-base.en.llamafile` from upstream; default flipped to `whisper-small.en.llamafile` (~497 MB, byte-verified). Tiny / small / medium .en variants remain; large multilingual variants exist but aren't in the wizard.
- **Wikipedia ZIM URL refresh** — Kiwix rolled the Simple-EN dump from `2024-06` to `2026-02`; old URL hard-404. Updated to `wikipedia_en_simple_all_nopic_2026-02.zim` (~921 MB, was ~395 MB) in both build scripts and `presets/zim.tsv`. Aggregate kit size grew ~525 MB.

### Verified (Linux side)
- **AC15a — Windows DOOM + saves walkthrough PASSED** — `D:\start-doom.bat` ASCII-clean, redbean came up cleanly, browser opened to `/doom/index.html`, DOOM rendered, ESC → Save Game → reload → slot persisted. End-to-end /save + /load round-trip works on Windows.

---

## [v0.7] — 2026-05-08

*Text-to-speech via native binaries. No Python on host.*

### Added
- **Text-to-speech (TTS) via redbean `/tts` endpoint** — POST text/plain, receive audio/wav. Powered by Sherpa-ONNX (native C++ runtime, no Python required) + Supertonic int8 model (~120 MB shared, ~210 MB total with binaries). Live smoke test: 416 KB mono WAV in 629 ms (faster-than-realtime). Voice loop ready: microphone → Whisperfile → Gemma 4 → Sherpa-TTS → speaker.
- **Per-OS TTS binaries** — Windows: single statically-linked `sherpa-onnx-offline-tts.exe` (~20 MB). Linux x64 & macOS arm64: native binaries with bundled `.so`/`.dylib` dependencies (~30 MB each extracted). Layout: `ai-kit/sherpa-tts/{linux,mac,win}/`.
- **Defensive LD_LIBRARY_PATH handling** — sherpa subprocess invocation includes platform-specific env vars to ensure native libs load correctly across different host libc versions.

### Infrastructure
- **Engine pivot from Kokoro to Sherpa-ONNX** — Kokoro-82M's reference runtime requires Python (`kokoro` package + ONNX Runtime), violating the kit's "no Python as host runtime" principle. Sherpa ships as native binaries, same pattern already used by Whisperfile and Kiwix. Supertonic 3 (~99M params, RTF 0.3) matches Kokoro's speed class. Decision rationale at `CLAUDE.md` "TTS — per-OS native binaries" section.
- **Subprocess invocation pattern** — redbean's TtsHandler (`.init.lua` line 271+) demonstrates fork+execve pattern safe against shell injection (text passed as single argv item, not through shell). Reference implementation for future native-binary customers.

---

## [v0.6] — 2026-05-08

*USB-resident DOOM saves. Saves travel with the kit across hosts.*

### Added
- **SQLite-backed DOOM save slots** — Six save slots (0-5) stored in `ai-kit/redbean/saves.db`. Schema: `saves(slot INTEGER PRIMARY KEY 0..5, name TEXT, data BLOB, updated_at TEXT)`. Client pre-fetches saves on boot, then wraps Dwasm's `FS.close` + `onCloseFile` events to POST `doomsavN.dsg` writes back to redbean. Saves persist across reboots and host migrations.
- **`/save`, `/load`, and `/list` redbean endpoints** — `POST /save?slot=N` persists DOOM state, `GET /load?slot=N` restores, `GET /list` enumerates populated slots. Slot validity checked on both sides.

### Fixed
- **`.init.lua` zip-append into redbean polyglot** — redbean 3.0.0's `-A` runtime-add flag is broken. Correct load mechanism: zip-append `.init.lua` into the `redbean.com` binary itself. Build script now auto-bakes this on fetch. Prior launcher pattern (copy `.init.lua` to USB root + cd there) was a misreading of redbean's loading contract and only worked because builds were untested against fresh fetches. **When changing `.init.lua`:** re-run `build-usb.sh` or manually re-zip with `cd ai-kit/redbean && zip -q redbean.com .init.lua`.

---

## [v0.5] — 2026-05-07 to 2026-05-08

*Platform layer. DOOM. Interactive build wizard.*

### Added
- **redbean webserver foundation** — ~6 MB Cosmopolitan APE polyglot (Lua + SQLite). Listens on port 8768. Provides `/health` endpoint and 501 stubs for `/save`, `/load`, `/list`, `/tts`, `/rag` (queued for v0.8). Shared across all redbean-based customers (today: DOOM + saves; v0.7+: TTS; queued: RAG). Single instance per USB — `start-doom.sh` probes `/health` and reuses existing server if running.
- **DOOM (Dwasm/PrBoom+ via emscripten)** — Shareware DOOM1.WAD served by redbean at `/doom/`. Auto-loads in browser, hides file picker. PrBoom+ source compiled to WASM. Playable at port 8768 from any OS.
- **Interactive build wizard** — `build-usb.sh` (bash) and `build-usb.ps1` (PowerShell) now prompt for configuration instead of shipping only a hardcoded bundle. Four modes:
  - **Default (no flag)** — interactive wizard: choose bundle prelude (tiny/balanced/full/custom), then 6 per-knob prompts (models, Wikipedia ZIM, OSM region, Whisper variant, OCR languages, DevDocs toggle). Writes config to `<target>/build-usb-config.sh` for re-runs.
  - **`-y` / `--non-interactive`** — use baked defaults (E4B + 26B + Embed, Simple ZIM, Monaco PBF, base.en Whisper, eng OCR, all side-arms). Equivalent to `bundle=full`. For CI and scripted re-runs.
  - **`-c <config-path>`** — source a saved config; skip wizard.
  - **`-i`** — force wizard even if config exists (overwrite).
  - **`-n`** — dry-run: resolve config, print `DOOM_*` env state, exit before downloads.
- **Preset menu data** — Single source of truth in `presets/*.tsv`: `bundles.tsv` (tiny/balanced/full definitions), `zim.tsv` (Wikipedia options), `osm.tsv` (OSM regions), `whisper.tsv` (Whisper variants), `ocr.tsv` (Tesseract.js language packs). Both build scripts read these — add a row, both scripts pick it up.

### Changed
- **Bundle schema** — `presets/bundles.tsv` now drives both build scripts. The bash `apply_baked_defaults()` function must stay in lockstep with `bundle=full` definition — `-y` and menu `bundle=full` produce byte-identical `DOOM_*` state.

### Infrastructure
- **GPL-2.0 license boundary at `doom/`** — Kit is Apache-2.0 overall. The `doom/` subdirectory inherits GPL-2.0 from upstream Dwasm/PrBoom+. Keep modifications GPL-compatible; don't blur the boundary with Apache code. Attribution and license terms documented in `doom/NOTICE.md`.
- **Port allocation finalized** — 8765 (AI core / llamafile), 8766 (Whisperfile), 8767 (Kiwix), 8768 (redbean: DOOM + saves + TTS + RAG stubs). Each tool gets a distinct port to allow parallel operation.
- **Adopted Domdhi.Agents `.claude/` toolkit** — slash commands, hooks, and agent infrastructure from shared team toolkit.

---

## [v0.4] — 2026-05-07

*First side-arm batch. Audio, OCR, offline reference, maps.*

### Added
- **Whisperfile (audio-to-text)** — Speech recognition via OpenAI Whisper packaged as a Cosmopolitan APE polyglot (`whisper-base.en.llamafile`, ~148 MB including weights). Supports multiple language/size variants via the build wizard. Runs on port 8766; `--gui` mode serves a drop-an-audio-file UI.
- **Tesseract.js OCR** — Optical character recognition runs in browser at `file://ocr/index.html`, zero server overhead. ~15 MB English language pack included. User can swap language packs via `ocr/README.txt` walkthrough.
- **Kiwix + offline Wikipedia** — Serves pre-built Wikipedia ZIM archives (compressed, full-text-searchable offline). Deployed kiwix-serve binary per OS (identical cross-platform, same Cosmopolitan pattern). Listens on port 8767. Simple English Wikipedia (~395 MB) included by default. Users can swap Wikipedia language/edition via menu.
- **Offline DevDocs** — Documentation for 200+ developer libraries available for manual sideload at `docs-offline/`. No server required, runs as static HTML (`file://` in browser). Installation walkthrough at `docs-offline/README.txt`.
- **OSM Maps for mobile** — Monaco.pbf (OpenStreetMap vector tiles, ~700 KB) for sideloading to Organic Maps on phones. User guide at `maps/README.md`. Enables offline mapping alongside the USB kit.

### Infrastructure
- **Launcher per side-arm family** — One launcher per OS for each tool family (whisper, wiki, ocr, docs, doom). Each side-arm runs on its own port to avoid conflicts and allow parallel operation. Launchers handle per-tool process cleanup and startup.
- **Competitive research synthesis** — Comprehensive analysis of 12 competing projects documented at `docs/research/competition.md` with per-project writeups. Informs feature prioritization and UX decisions going forward.

---

## [v0.3] — 2026-05-05 to 2026-05-06

*Initial recipe. External-weights pattern. Three Gemma 4 models.*

### Added
- **Portable offline AI kit** — Two Gemma 4 chat models (5 GB daily-driver E4B + 17 GB Mixture-of-Experts 26B) + one embedding model (EmbeddingGemma 300M for future RAG) bundled as a USB build recipe.
- **External-weights architecture** — Runtime (`llamafile` 43 MB, Cosmopolitan APE) and GGUF model weights ship separately, not bundled. Windows PE loader cannot execute images larger than ~4 GB (32-bit-signed offset limitation), so bundling fails for 5+ GB models. Separate-weights pattern: launchers invoke `runtime/llamafile -m models/<file>.gguf` with server flags. Same layout works across Linux/macOS/Windows from one USB.
- **Unified launcher per OS** — One launcher script per OS (`start.{sh,bat,command}`) at USB root. Presents numbered menu of available models; user picks one; launcher kills any stray llamafile process; starts chosen model on port 8765. Prevents accidental "both models running, fighting over RAM" misuse. Keeps USB root visually clean.
- **Static dashboard** — `index.html` at USB root with kit overview and launcher links. Relies on `file://` local loading; no server required for initial orientation.
- **Cosmopolitan APE polyglots** — Binaries (llamafile, future whisperfile, future kiwix) are polyglot shell scripts + ELF + Mach-O + PE all in one 43 MB file. Byte-identical across OS boundaries. Run on any system without modification.
- **Prepper-themed presentation** — README framed around offline AI access during network outages, grid failures, restricted connectivity. Brand identity: "knowledge in a tin."

### Infrastructure
- **Apache-2.0 license** — Kit is open-source Apache; competitive research and private decision logs excluded from public release.
- **Git structure** — Commits track recipe inputs (launchers, scripts, args files, HTML, preset data). Build artifacts (`runtime/`, `models/`, compiled binaries) are gitignored. Only recipe — users fetch artifacts on demand.
- **Args files documentation** — `args/e4b.args`, `args/26b.args`, `args/whisper.args`, `args/kiwix.args` document the exact flags passed to each tool. Not runtime input; snapshot of launcher configuration for reference and repeatability. Update when launchers change.

---

## [v0.1 - v0.2]

*(No formal releases before v0.3. Early exploration phase.)*

