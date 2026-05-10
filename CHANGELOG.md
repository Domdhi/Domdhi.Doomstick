# Changelog

All notable changes to the Doomstick kit are documented here. See [README.md](../README.md) for project overview.

Format based on [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased]

*No queued items. v0.10 epic selection is open — candidates include offline image generation, expanded YubiKey/FIDO2 vault ceremony tooling, and the Pip-Boy v2 handheld hardware spin-off.*

---

## [0.9.0] — 2026-05-09

*"the vault" — age-encrypted recovery vault customer for SSH keys, AWS credentials, GitHub CLI tokens, WireGuard configs, and any other secrets you want to carry on the kit without storing them in cleartext.*

### Added

- **age v1.3.1 binaries** at `ai-kit/age/{linux,mac,win}/` (~6-7 MB per OS,
  BSD-3 native Go from FiloSottile/age — NOT a Cosmopolitan APE polyglot,
  so no Defender false-positive risk). Per-OS layout mirrors sherpa-tts.
- **Per-OS vault launchers** — `start-vault.{sh,command,bat}` decrypt
  `vault/recovery.tar.age` to a host tmpdir (`mktemp -d` on Unix,
  `%TEMP%\doomstick-vault-…` on Windows). Decryption goes to host tmpdir
  by design, NOT back to the USB — exFAT strips POSIX `0600` permissions
  and would break SSH key usage. Two-stage error handling: missing-age =
  exit 1 (fatal); missing-vault = exit 0 + creation hint (user guidance,
  not error).
- **`vault/README.txt`** — on-USB plain-text README (174 lines) opening
  with a `===`-weighted CRITICAL key-loss warning, ceremonies for
  passphrase / YubiKey / multi-recipient setup, and what-to-vault /
  what-not-to-vault guidance.
- **`docs/vault-guide.md`** — GitHub-only ceremony walkthrough (375
  lines): Quick Start, Ceremony 1 (passphrase, default), Ceremony 2
  (YubiKey + FIDO2), Ceremony 3 (multi-recipient paranoid), Master Key
  Backup, cross-OS path table for SSH/AWS/GH/WireGuard/GPG/1Password.
- **Dashboard §07 Recovery Vault** card pair (decrypt + setup),
  desktop-only. Ebs-meta version bumped to `v0·9·0 / 2026·05·09`.
- **`build-usb.{sh,ps1}` vault block** — always-on (no bundle column);
  fetches three per-OS age archives, extracts to `ai-kit/age/<os>/`,
  copies launcher trio to USB root. Override via `DOOM_INCLUDE_VAULT=0`
  env var. PowerShell mirror uses `Expand-Archive` for Windows .zip and
  `tar.exe` shellout for Linux/macOS .tar.gz.

### Verified

- **Cross-OS verification GREEN** — full PRE.A..E + T1..T14 + UX1..UX4
  suite ran clean on real Windows hardware (5 PRE PASS, 14 T PASS, 1 UX
  PASS, 3 UX SKIPPED-as-designed, 0 FAIL, 0 BLOCKED). 25/25 WSL static
  checks PASS. v0.8.1 CORS v3 fix verified non-regressed via T7 quad
  headers and T3 single-header invariant.
- **age cryptographic round-trip** — magic bytes (`age-encryption.org/`)
  intact; SHA256 byte-equal decrypt. T14b/c executed via PTY-driven
  Linux-age substitute against the kit's own Linux binary (same upstream
  FiloSottile v1.3.1 release as `age.exe`) because age v1.3.1 cannot be
  passphrase-tested non-interactively on either platform — mainline
  design constraint, not a v0.9 bug. `start-vault.bat`'s interactive
  contract is verified separately in T14a.

### Documentation

- **`README.md` v0.9 manifest sync** — banners ×2 bumped to
  `v0.9.0 · "the vault" · 2026·05·09`. §02 manifest adds `vault/`,
  `start-vault.{bat,command,sh}`, `ai-kit/age/`. §08 Casualty Report
  gains two `<details>` blocks (vault-not-found friendly exit-0,
  decryption failed). §09 shipped table adds the v0.9 row; pending row
  removed.
- **`auxiliary-roadmap.md`** — v0.9 shipped entry under "Shipped"
  (table + key decisions block), pending entry removed.

---

## [0.8.1] — 2026-05-09

*Follow-up patch closing a load-bearing cross-origin bug found during v0.8.0 verification, plus a doc/cosmetic punch list.*

### Fixed

- **Chat tab cross-origin fetch failure** — Hollama is served from `file://` and fetches redbean on `127.0.0.1:8768`. Browsers treat that as cross-origin AND require `Access-Control-Allow-Private-Network: true` (Chrome 117+) on top of standard CORS for any `file://` → `127.0.0.1` fetch. Without both, the chat-tab adapters silently failed: no `#filename` autocomplete results, no journal append, no chat session persistence. The fix calls the CORS helper **after** `SetStatus()` in every handler, never at top-level — top-level pre-calls survive on 200 responses and get re-applied by the handler helper, producing duplicate `Access-Control-Allow-Origin` headers that Chrome rejects per RFC 7230. Pattern now applied across 7 manual handlers, the `json` / `json_err` helpers, and the OPTIONS preflight handler. `Allow-Origin: *` is acceptable because redbean only binds `127.0.0.1`; remote origins cannot reach the listener.
- **Journal append hollow heading** — `JournalAppendHandler` now skips the auto `## HH:MM` line when the user's request body already starts with its own markdown heading, preventing a hollow heading immediately followed by another. Behavior unchanged for plain-text bodies.

### Documentation

- **`docs/testing/windows-verification.md` path corrections** — chat tab verified at `USB\chat\` (build flattens `dashboard/*` to USB root, not `USB\dashboard\chat\`). Workspace README at `USB\workspace\README.md` (top-level, not per-default). T11 OCR threshold logic rewritten: `tesseract.min.js` is the ~10 KB v5 loader shim (no size threshold), `worker.min.js` is the >100 KB worker payload after the v5 split, traineddata threshold lowered from >5 MB to >3 MB to fit `tessdata_fast`'s ~4 MB `eng` pack. Removed rejected `--nobrowser` flag from the T8 llamafile invocation example (rejected as "unknown argument" by llamafile 0.10.1).
- **Windows Defender APE false-positive note** — some Windows hosts quarantine `llamafile.exe` and `redbean.com.exe` under `Trojan:Win32/ClickFix.CCJ!MTB`, a known FP against Cosmopolitan polyglots. Added the unblock path (Windows Security → Protection history → Allow, or USB-letter exclusion) to both `dashboard/README.txt` and `README.md`. Both binaries are unmodified upstream releases (Mozilla-Ocho llamafile 0.10.1, redbean 3.0.0 from redbean.dev) with their own published checksums.
- **Hollama first-boot onboarding** — clarified the Re-verify step in the `_extras-providers.js` toast and `dashboard/README.txt`: after provider seeding, the model picker stays empty until the user opens Settings and clicks Re-verify on each enabled server (Hollama keeps `isVerified: null` until user-initiated). Auto-firing the internal verify path is too coupled to Hollama bundle internals to do safely from an adapter; documenting the one-click step is the right answer until Hollama exposes a hook.
- **README v0.8.0 manifest sync** — banner bumped to `v0.8.0 / 2026-05-09`; codename changed from `"phone home"` to `"the wedge"`; DECLASSIFIED date updated. §02 manifest now includes `redbean/`, `presets/`, `doom/`, `dashboard/chat/`, `start-embed.*`, `chat/`, `workspace/`. §04 EMBEDGEMMA row marked `🟢 FIELD READY` (no longer pending) with the v0.8 RAG role. §09 demotes EmbeddingGemma RAG out of "Still pending" (it shipped) and adds a unified ✅ row covering RAG + chat tab + journal + workspace primitive.

---

## [0.8.0] — 2026-05-09

### Added

- **RAG layer over redbean** — new endpoints `/rag/_loadtest`,
  `/rag/ingest`, `/rag/query`, `/rag/list-docs`, `/rag/list-workspaces`
  on port 8768. Pure-Lua cosine over `embedding BLOB` columns; ~500 ms
  round-trip on 1000-chunk corpus.
- **Embedding side-arm** — `start-embed.{bat,sh,command}` runs llamafile
  `--embedding` on port 8769 with EmbeddingGemma-300M Q8 (already shipped
  since v0.3, no extra fetch).
- **Vendored Hollama 0.35.4 chat tab** at `dashboard/chat/` (MIT-licensed,
  served via `file://`). 5 adapter files inject `#filename` autocomplete,
  workspace dropdown, server-backed session persistence, 3-server provider
  seed (E4B + 26B + embed), and journal sidebar.
- **Chat persistence on the USB** — `/chat/save`, `/chat/list`, `/chat/load`
  redbean handlers (UPSERT on UUID). Sessions survive host changes.
- **Daily journal** — `/journal/append` and `/journal/today` write to
  `workspace/<name>/journal/YYYY-MM-DD.md` and auto-ingest into RAG.
- **Workspace primitive** — folder convention at `workspace/<name>/docs/`.
  Per-workspace scoping at every RAG and chat endpoint.
- **New launcher** — `start.{bat,command,sh}` opens chat tab.

### Changed

- **Architecture pivot at Wave 0 D4** — sqlite-vec dropped in favor of
  pure-Lua cosine over `embedding BLOB` columns, because redbean's
  lsqlite3 has no FTS5 and no `load_extension`. Saves cross-OS binary
  procurement; trades vec0 query speed for in-Lua full-scan top-K
  (acceptable at v0.8 corpus sizes).
- **Dashboard `§02 Initiation Devices`** gains a 4th card — chat tab.

### Fixed

- **`SaveHandler` BLOB truncation** (latent since v0.6) — `lsqlite3`
  `bind_values()` infers Lua-string → TEXT, which truncates binary
  data containing null bytes or invalid UTF-8. DOOM saves with real
  binary content would have corrupted; just hadn't been smoked. Both
  RAG ingestion and DOOM saves now use explicit `stmt:bind_blob(idx, str)`.

### Documentation

- New gotchas in `CLAUDE.md` covering: lsqlite3 no-FTS5/no-load_extension,
  redbean Fetch() multivalue signature, lsqlite3 bind_values BLOB
  truncation, WSL2 silently dropping outbound TCP to unbound localhost,
  EmbeddingGemma EMBED_DIM=768 pin, Hollama vendor adapter pattern,
  SvelteKit absolute-path sed post-process, `.lua/` require path in
  zip-bake, and redbean handler dispatch ordering.
- New verification tests in `docs/testing/windows-verification.md`:
  T13 (RAG round-trip), PRE.D (RAG pre-suite guard), UX5 (chat tab
  on phone).
- Hollama vendor pin documented at `dashboard/chat/PINNED.md` with
  full DOM contract table.
- Architectural design doc at `docs/research/rag-architecture-2026-05-09.md`.

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

