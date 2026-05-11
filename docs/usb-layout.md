# USB layout — what your USB looks like after building

This is the file tree the assembled kit produces on a target USB stick. The
build script (`build-usb.sh` / `build-usb.ps1`) creates everything below from
upstream releases. None of the binary artifacts are committed to this repo —
they're fetched on demand because GitHub blocks single files >100 MB and the
full kit weighs ~28 GB.

```
USB root (D:\, /mnt/usb, /Volumes/USB, …)
├── index.html                            kit dashboard (file://)
├── mobile.html                           phone-friendly entry shim
├── README.txt                            plain-text overview
├── start.bat / .command / .sh            AI core launcher (E4B / 26B / Qwen3-4B picker)
├── start-doom.bat / .command / .sh       redbean + DOOM (port 8768) — also serves /tts, /rag, /chat
├── start-whisper.bat / .command / .sh    Whisperfile audio→text (port 8766)
├── start-wiki.bat / .command / .sh       Kiwix-serve offline Wikipedia (port 8767)
├── start-ocr.bat / .command / .sh        Opens ocr/index.html (Tesseract.js, browser only)
├── start-docs.bat / .command / .sh       Opens docs-offline/index.html (manual setup)
├── start-embed.bat / .command / .sh      EmbeddingGemma side-arm for RAG (port 8769)
├── start-vault.bat / .command / .sh      age-decrypt vault to host tmpdir
├── start-img.bat / .command / .sh        sd-cli image gen (FLUX.2 klein, no port)
├── start-passwords.bat / .command / .sh  KeePassXC GUI password manager
├── start-ffmpeg.bat / .command / .sh     ffmpeg + ffprobe PATH-primer shell, no port
├── start-devtools.bat / .command / .sh   dev tools PATH-primer shell (ripgrep / fzf / jq / 7-Zip / VSCodium)
├── ai-kit/
│   ├── runtime/                          llamafile 0.10.1 (43 MB APE polyglot, byte-identical
│   │                                     across OSes; .exe-renamed copy for Windows double-click)
│   ├── models/                           GGUF weights (Apache 2.0 + Gemma terms)
│   │   ├── gemma-4-E4B-it-Q4_K_M.gguf            5.0 GB · daily driver · 8 GB RAM host
│   │   ├── gemma-4-26B-A4B-it-UD-Q4_K_M.gguf    17 GB · MoE big brain · 18 GB RAM host
│   │   ├── Qwen3-4B-Q4_K_M.gguf                  2.33 GB · 3rd AI core option (v0.10+)
│   │   │                                         · ALSO FLUX.2's text encoder
│   │   └── embeddinggemma-300m-qat-Q8_0.gguf    329 MB · powers v0.8+ RAG
│   ├── whisper/                          Whisperfile (default: small.en, ~497 MB)
│   ├── kiwix/{linux,mac,win}/            kiwix-serve binaries per OS
│   ├── redbean/                          shared platform layer (v0.5+)
│   │   ├── redbean.com                   ~8.8 MB APE polyglot, port 8768 (.init.lua baked in)
│   │   ├── .init.lua                     route handlers (inspection copy; runtime reads
│   │   │                                 the version inside redbean.com's appended zip)
│   │   ├── webroot/                      empty docroot — see CLAUDE.md "exFAT-on-Windows" gotcha
│   │   └── saves.db                      SQLite — DOOM saves + RAG chunks (created on first use)
│   ├── sherpa-tts/                       v0.7+ — TTS runtime + Supertonic int8 model
│   │   ├── linux/                        sherpa-onnx-offline-tts + .so deps (~30 MB)
│   │   ├── mac/                          sherpa-onnx-offline-tts + .dylib deps (arm64, ~30 MB)
│   │   ├── win/                          sherpa-onnx-offline-tts.exe + onnxruntime*.dll (~50 MB)
│   │   └── models/supertonic/            Supertonic int8 ONNX bundle (~120 MB shared)
│   ├── age/{linux,mac,win}/              v0.9+ — age v1.3.1 vault binaries (~6-7 MB per OS,
│   │                                     BSD-3 native Go from FiloSottile/age, NOT a polyglot)
│   ├── sd-img/                           v0.10+ — sd-cpp + FLUX.2 klein companion files
│   │   ├── linux/                        sd-cli + libstable-diffusion.so
│   │   ├── mac/                          sd-cli + libstable-diffusion.dylib (arm64)
│   │   ├── win/                          sd-cli.exe + stable-diffusion.dll
│   │   └── models/
│   │       ├── flux-2-klein-4b-Q4_K_M.gguf            ~2.43 GB · transformer · Apache-2.0
│   │       └── full_encoder_small_decoder.safetensors ~238 MB · VAE · Apache-2.0
│   ├── keepassxc/                        v0.11+ — KeePassXC per-OS binaries (GPL-2.0+)
│   │   ├── linux/
│   │   ├── mac/
│   │   └── win/
│   ├── ffmpeg/                           v0.11+ — ffmpeg + ffprobe per-OS (GPL-3.0+)
│   │   ├── linux/
│   │   ├── mac/
│   │   └── win/
│   ├── devtools/                         v0.12+ — portable dev tools per-OS (MIT + LGPL-2.1)
│   │   ├── linux/                        rg, fzf, jq, 7zzs (static), vscode/codium
│   │   ├── mac/                          rg, fzf, jq, 7zz (static, no trailing s), vscode/VSCodium.app
│   │   └── win/                          rg.exe, fzf.exe, jq.exe, 7za.exe, vscode/VSCodium.exe
│   └── certs/                            v0.12+ — Mozilla CA bundle (MPL-2.0, always-on)
│       └── cacert.pem                    ~226 KB · TLS root bundle · re-fetched on each build
├── chat/                                 v0.8+ — Vendored Hollama 0.35.4 SPA + 5 adapter files
├── doom/                                 v0.5+ — Dwasm bundle + shareware DOOM1.WAD (GPL-2.0)
├── workspace/                            v0.8+ — RAG corpus root
│   └── <name>/
│       ├── docs/                         drop documents here for `/rag/ingest`
│       ├── journal/                      daily journal entries (auto-ingested)
│       ├── _inbox/                       loose-file capture
│       └── system.md                     per-workspace system prompt for chat
├── vault/                                v0.9+ — encrypted recovery blob (user-created)
│   └── recovery.tar.age                  age-encrypted tarball; decrypt with start-vault
├── passwords/                            v0.11+ — KeePassXC database root
│   ├── README.txt                        setup guide + creation ceremony
│   └── vault.kdbx                        (user-created on first run)
├── field-manual/                         v0.12+ — public-domain offline reference corpus
│   ├── index.html                        browseable index (file://, mobile-friendly)
│   ├── *.md                              six topic files (survival, first-aid, plants, radio, water, knots)
│   └── NOTICE.md                         PD attribution + excluded sources list
├── zim/                                  Wikipedia archives (default: Simple English ~921 MB)
├── ocr/                                  v0.4+ — Tesseract.js bundle + lang-data (English ~4 MB)
├── maps/                                 OSM .pbf files (default: Monaco; sideload to phone app)
└── docs-offline/                         DevDocs payload (manual setup; see README.txt inside)
```

## Bundle sizes

The build wizard offers three preset bundles before falling back to the
custom path:

| Bundle      | Size     | Contents                                                                                   |
|-------------|----------|--------------------------------------------------------------------------------------------|
| `tiny`      | ~5.4 GB  | E4B + Simple Wikipedia. No maps, no voice, no DOOM, no TTS, no image gen.                  |
| `balanced`  | ~7.03 GB | E4B + Embed + Simple Wikipedia + Monaco maps + all side-arms + redbean + DOOM + TTS + KeePassXC password manager + DevTools (5 tools) + Field manual. |
| `full`      | ~29.4 GB | Everything — all four models + all side-arms + redbean + DOOM + TTS + vault + image gen + KeePassXC + ffmpeg + DevTools (5 tools) + Field manual.     |

`bundle=full` and `-y` (non-interactive) produce byte-identical state — keep
`presets/bundles.tsv`'s `full` row in lockstep with bash `apply_baked_defaults()`.

## Why not commit the binaries?

GitHub blocks single files >100 MB and the full kit is ~28 GB of weights +
runtimes. Even if Git LFS were free, vendoring third-party releases in this
repo would create a maintenance smell — every llamafile / redbean / sd-cpp
release would force a commit here. The build script downloads the right
versions on demand from authoritative upstreams (Mozilla-Ocho, redbean.dev,
HuggingFace, FiloSottile/age, leejet/stable-diffusion.cpp).

For a fully air-gapped build flow, mirror the upstream releases locally and
edit the URL constants in `build-usb.{sh,ps1}` to point at your mirror.

## Cross-references

- **CLAUDE.md** has the canonical "USB layout after deploy" block and the
  full set of gotchas around exFAT, APE polyglots, and per-OS binary
  patterns. (Inner repo only.)
- **README.md** §02 USB tree shows the same structure with launcher-icon
  decoration for the dashboard narrative.
- **`presets/bundles.tsv`** is the single source of truth for what each
  bundle includes; both build scripts read it.
