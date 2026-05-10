# Portable Offline AI Kit

> Build a USB stick that runs a real Gemma 4 LLM on any Windows / macOS /
> Linux laptop, with no install, no internet, no GPU, no Python, no Docker,
> no telemetry. Plug in, double-click, chat.

Two Gemma 4 models (a 5 GB daily-driver and a 17 GB Mixture-of-Experts), a
43 MB [llamafile](https://github.com/Mozilla-Ocho/llamafile) runtime, three
launcher scripts, and a static-HTML dashboard. The same files boot on all
three OSes from the same USB stick — llamafile is a [Cosmopolitan APE
polyglot](https://github.com/jart/cosmopolitan), simultaneously a valid
Windows `.exe`, Linux ELF, macOS Mach-O, and POSIX shell script.

This repo is the **build recipe**, not the kit itself. Cloning gives you the
launcher scripts, the dashboard, args files, and a `build-usb.sh` /
`build-usb.ps1` that downloads the runtime and weights from upstream and
assembles the full USB layout for you. You supply the USB and the bandwidth
(~22 GB of downloads); the script does the rest.

<p>
<img alt="License" src="https://img.shields.io/badge/license-Apache_2.0-fcd000?style=for-the-badge&labelColor=0a0a08" />
<img alt="Status" src="https://img.shields.io/badge/status-plug_%26_pray-c63d2f?style=for-the-badge&labelColor=0a0a08" />
<img alt="Internet" src="https://img.shields.io/badge/internet-optional-6df54a?style=for-the-badge&labelColor=0a0a08" />
<img alt="Grid" src="https://img.shields.io/badge/grid-down-c63d2f?style=for-the-badge&labelColor=0a0a08" />
<img alt="Models" src="https://img.shields.io/badge/Gemma_4-E4B_%2B_26B-fcd000?style=for-the-badge&labelColor=0a0a08" />
<img alt="Runtime" src="https://img.shields.io/badge/runtime-llamafile_0.10.1-c8bea2?style=for-the-badge&labelColor=0a0a08" />
</p>

---

<div align="center">

# 🪦 DOOMSTICK

### *The pocket-sized AI that survives the internet.*

```
██████╗  ██████╗  ██████╗ ███╗   ███╗███████╗████████╗██╗ ██████╗██╗  ██╗
██╔══██╗██╔═══██╗██╔═══██╗████╗ ████║██╔════╝╚══██╔══╝██║██╔════╝██║ ██╔╝
██║  ██║██║   ██║██║   ██║██╔████╔██║███████╗   ██║   ██║██║     █████╔╝
██║  ██║██║   ██║██║   ██║██║╚██╔╝██║╚════██║   ██║   ██║██║     ██╔═██╗
██████╔╝╚██████╔╝╚██████╔╝██║ ╚═╝ ██║███████║   ██║   ██║╚██████╗██║  ██╗
╚═════╝  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝

                  ░ ░  k n o w l e d g e   i n   a   t i n  ░ ░
```

> *"When the cell towers go quiet and the cloud forgets your name,*
> *the bunker still has answers."*
>
> <sub>— anonymous · 2 a.m. · three-day blackout</sub>

</div>

```
╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲

  ☢  EMERGENCY BROADCAST · OFFLINE EMERGENCY ASSISTANCE NETWORK  ☣

      CLASSIFICATION  ▸  PUBLIC               DOOMSTICK · v0.9.0 · 2026·05·09
      TRANSMISSION    ▸  OFFLINE              COSMOPOLITAN · CPU-ONLY · USB
      AUTH            ▸  Apache-2.0 + GPL     ENDPOINT · 127.0.0.1 : 8765

      ◉ NETWORK    [ lost ]
      ◉ POWER      [ usb · D:\ ]
      ◉ AI CORE    [ stand·by ]                ← flips to [armed] on launch

╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲
```

<br>

## ☢️ §01 · The Pitch

You're somewhere with no signal. Maybe the WiFi died. Maybe the router died. Maybe **the internet died**. You still have a laptop and a USB stick.

You plug the stick in. Double-click one file. Thirty seconds later you're chatting with a Gemma 4 language model — 4.5 B parameters in the daily-driver, or 26 B (3.8 B active) in the Mixture-of-Experts — that can:

- 🩹 Talk you through a wound dressing
- 🔧 Walk you through fixing a generator
- ☣️ Identify the mushroom you're holding
- 📜 Explain a legal document
- 🧪 Convert units, do math, write code, summarize a book
- 🗺️ Translate between dozens of languages
- 🎙️ ...and just keep you company in the dark

No telemetry. No accounts. No "please connect to the internet to verify." No subscription. No degradation when the API changes overnight. **It just works. Forever.**

<br>

## 🧰 §02 · Manifest — Repo vs USB

This is a recipe — large binary artifacts (model weights, ISOs) live upstream and are fetched by the build script.

**What `git clone` gives you:**

```
.
├── build-usb.sh / .ps1     One-shot script: fetch + assemble USB layout
├── presets/                TSV menu data (bundles, ZIM, OSM, Whisper, OCR)
├── launchers/              start.{bat,command,sh} for AI core + 6 side arms
├── dashboard/              Web assets that deploy to USB root
│   ├── index.html              Static dashboard
│   ├── chat/                   Vendored Hollama 0.35.4 chat tab (v0.8+)
│   └── README.txt              Plain-text version of this doc
├── redbean/                Local platform layer — `.init.lua` route handlers
├── args/                   Flag reference (mirrored into launchers; doesn't deploy)
├── ocr/                    Tesseract.js OCR static page (deploys as-is)
├── maps/                   OSM .pbf landing zone + sideload README
├── vault/                  vault/README.txt (ceremony doc; recovery.tar.age gitignored)
├── doom/                   Dwasm bundle + DOOM1.WAD wrapper (GPL-2.0 subdir)
├── docs-offline/           DevDocs landing zone (manual setup)
├── docs/
│   ├── auxiliary-roadmap.md     What's shipped, what's pending
│   └── setup-devdocs.md         Manual DevDocs walkthrough
├── usb-layout/             Empty skeleton showing the target USB structure
├── LICENSE                 Apache-2.0
└── README.md               This file
```

**What `build-usb.sh /mnt/usb` produces:**

```
/mnt/usb/                                       ~22.7 GB total
├── 📄 index.html                     One-page dashboard. Open this first.
├── 🚀 start.bat                       Windows AI launcher (model picker + chat tab)
├── 🚀 start.command                   macOS AI launcher
├── 🚀 start.sh                        Linux AI launcher
├── 🚀 start-whisper.{bat,command,sh}  Audio → text  (port 8766)
├── 🚀 start-wiki.{bat,command,sh}     Offline Wikipedia (port 8767)
├── 🚀 start-ocr.{bat,command,sh}      Image → text   (browser only)
├── 🚀 start-docs.{bat,command,sh}     DevDocs       (manual setup)
├── 🚀 start-doom.{bat,command,sh}     DOOM via redbean (port 8768)
├── 🚀 start-embed.{bat,command,sh}    Embedding side-arm for RAG (port 8769, v0.8+)
├── 🚀 start-vault.{bat,command,sh}    Vault decrypt (age, prints cleanup reminder)
├── 📜 README.txt                      Short version of this doc
├── 💬 chat/                           Vendored Hollama chat tab (file://, v0.8+)
├── 📓 workspace/<name>/docs/, journal/  Per-workspace RAG corpus (v0.8+)
│
├── 🧠 ai-kit/                         AI core + side-arm binaries
│   ├── runtime/
│   │   ├── llamafile                       43 MB inference engine (Linux/macOS)
│   │   └── llamafile.exe                   Same binary, .exe-renamed for Windows
│   ├── models/
│   │   ├── gemma-4-E4B-it-Q4_K_M.gguf            5 GB,  daily driver
│   │   ├── gemma-4-26B-A4B-it-UD-Q4_K_M.gguf    17 GB, big brain MoE
│   │   └── embeddinggemma-300m-qat-Q8_0.gguf    329 MB, powers v0.8 RAG (live)
│   ├── whisper/
│   │   └── whisper-small.en.llamafile           497 MB, audio → text
│   ├── kiwix/
│   │   ├── linux/, mac/, win/                    kiwix-serve binaries (~6 MB each)
│   ├── redbean/
│   │   ├── redbean.com                            5.5 MB local platform layer (port 8768)
│   │   ├── saves.db                               DOOM saves + chat sessions + RAG chunks (SQLite)
│   │   └── .init.lua                              route handlers (/health, /save, /load, /list,
│   │                                              /tts, /rag/*, /chat/*, /journal/*)
│   ├── sherpa-tts/
│   │   ├── linux/, mac/, win/                     sherpa-onnx-offline-tts per OS (~30 MB each)
│   │   └── models/supertonic/                     Supertonic int8 ONNX bundle (~120 MB)
│   └── age/
│       ├── linux/, mac/, win/         age binary per OS (~9 MB each)
│
├── 📚 zim/wikipedia_en_simple_all_nopic_2024-06.zim   ~395 MB (default)
├── 🔤 ocr/                            tesseract.js + eng pack    ~15 MB
├── 🗺  maps/<region>.osm.pbf          OSM regional data           ~700 KB+ (Monaco default)
├── 📖 docs-offline/                   DevDocs (manual setup, not auto-fetched)
├── 🪦 doom/                           Dwasm + shareware DOOM1.WAD  ~7.4 MB (GPL-2.0)
└── 🔐 vault/                          Recovery vault directory
    ├── README.txt                     Ceremony + key-loss warning
    └── recovery.tar.age               User-created encrypted blob (not shipped)
```

**What the kit does *not* ship** (BYO if you want them):

- Bootable rescue ISOs (Ubuntu / SystemRescue / Hiren's BootCD PE) + [Ventoy](https://www.ventoy.net/)
- Portable Windows tools (PortableGit, VS Code Portable, ripgrep, fzf, jq, 7-Zip)
- Piper TTS (text → audio, completes the voice stack with whisperfile)
- stable-diffusion.cpp (offline image generation), ffmpeg, …

These and more are tracked in [`docs/auxiliary-roadmap.md`](docs/auxiliary-roadmap.md) — most are one-line additions to the build script when you feel like it.

<br>

## 🔌 §03 · Initiation Protocol

> *Or: how to talk to a god in the dark.*

### Build the kit onto a USB

```bash
git clone https://github.com/Domdhi/Domdhi.Doomstick.git
cd Domdhi.Doomstick

# Linux / macOS / WSL:
./build-usb.sh /mnt/usb              # opens the build wizard

# Windows (native PowerShell, run as Admin if writing to USB root):
.\build-usb.ps1 D:\
```

The first run opens an **interactive wizard**: pick a bundle (`tiny / balanced / full`) for one-keystroke first-time UX, or `custom` to choose models, Wikipedia language, OSM region, Whisper voice variant, OCR languages, and side-arm toggles individually. Settings save to `<USB>/build-usb-config.sh` so re-running on the same stick skips the wizard.

| Bundle      | Size     | What you get                                                                              |
|-------------|----------|-------------------------------------------------------------------------------------------|
| `tiny`      | ~5.4 GB  | E4B model + Simple-English Wikipedia. No maps, no voice, no DOOM, no TTS. Smallest useful. |
| `balanced`  | ~6.1 GB  | E4B + Embedding + Simple Wikipedia + Monaco maps + all side-arms + redbean + DOOM + TTS.   |
| `full`      | ~22.9 GB | Everything (3 models + side-arms + redbean + DOOM + TTS). Matches `-y` non-interactive defaults. |

**Modes:**

```bash
./build-usb.sh /mnt/usb                       # wizard (or sources existing config)
./build-usb.sh -y /mnt/usb                    # non-interactive — all defaults (full bundle)
./build-usb.sh -i /mnt/usb                    # force wizard even if config exists
./build-usb.sh -c saved-config.sh /mnt/usb    # source a named config
./build-usb.sh -n /mnt/usb                    # dry-run: print resolved config, don't fetch
./build-usb.sh -h                             # full help
```

The script downloads the runtime (~43 MB) plus whatever models / side arms you picked. Resumable — re-running skips files that already exist with the right size.

### Use the kit

```
  1. Plug in USB.
  2. Double-click  start.bat  /  start.command  /  start.sh
  3. Pick a model:    [1] E4B   (5 GB,  needs 8+ GB RAM)
                      [2] 26B  (17 GB, needs 18+ GB RAM)
  4. Wait 15-90 seconds.
  5. Browser opens. You're chatting.
```

To stop: press any key in the launcher window. To switch models: stop, run again, pick the other.

That's the whole UX.

> [!IMPORTANT]
> **Only one model runs at a time.** The launcher kills any orphan llamafile process on each start, so you can't accidentally have both models fighting over RAM.

<br>

## 📱 §M · From a Phone

> *Plug the same stick into a phone via USB-OTG. Half the kit was already designed for this.*

Llamafile, redbean, and whisperfile are APE polyglots — they execute on x86_64 + ARM64 desktop OSes only. iOS and Android use different ABIs and sandboxed app models, so the AI core itself doesn't run on a phone (that's a separate project). **But every shipped data asset has a first-class consumer on Android and iOS:**

| Capability | Path on USB | Android | iOS |
|---|---|---|---|
| Wikipedia (ZIM) | `zim/*.zim` | [Kiwix (F-Droid)](https://f-droid.org/packages/org.kiwix.kiwixmobile/) · [Play](https://play.google.com/store/apps/details?id=org.kiwix.kiwixmobile) | [Kiwix Reader](https://apps.apple.com/app/kiwix/id997079563) |
| Maps (OSM) | `maps/<region>.osm.pbf` | [Organic Maps (F-Droid)](https://f-droid.org/packages/app.organicmaps/) · [Play](https://play.google.com/store/apps/details?id=app.organicmaps) | [Organic Maps](https://apps.apple.com/app/id1565437007) |
| LLM chat | `ai-kit/models/*.gguf` | [PocketPal AI](https://play.google.com/store/apps/details?id=com.pocketpalai) | [PocketPal AI](https://apps.apple.com/app/pocketpal-ai/id6502579498) |
| OCR | `ocr/index.html` | mobile Chrome (capture rear camera + paste) | mobile Safari |
| DOOM | `doom/index.html` | mobile Chrome (touch controls included) | mobile Safari |
| DevDocs | `docs-offline/index.html` | mobile Chrome | mobile Safari |

**Discoverability:** the build copies `mobile.html` to the USB root next to `index.html`. Tapping `mobile.html` from your phone's file manager redirects to the dashboard's Mobile Field Kit — UA-detection swaps the desktop launcher cards for app-store buttons and offline-page links.

**Install once, offline forever.** Get the apps over a connection one time, then unplug. The data files travel with the stick across every host you plug into.

**Caveats:**
- DOOM saves don't persist on mobile — they bridge to redbean's `/save` endpoint, and redbean isn't running on the phone. Same engine and WAD; just no save state.
- USB-OTG reads are slower than internal storage. For Wikipedia or maps you'll use daily, copy the relevant file off the stick into your phone's internal storage once.
- Lightning ports may need an Apple-branded adapter to deliver enough power to a USB stick.
- iOS occasionally needs an unplug/replug to recognize a new drive.

<br>

## 🧠 §04 · Payload Manifest

Three weights ship with the kit. Two appear in the launcher menu; the third powers the v0.8 RAG layer behind the chat tab.

| Callsign | Size | RAM | Speed (CPU) | Quant | Role | Status |
|---|---|---|---|---|---|---|
| **GEMMA-4 / E4B** | 5.0 GB | ≥ 8 GB | ~15 t/s | `Q4_K_M` | Daily driver — **4.5 B effective parameters** (8 B with embeddings). Chat, code, summaries, translation. Good enough for ~95% of normal questions. | `🟢 FIELD READY` |
| **GEMMA-4 / 26B-A4B** | 17 GB | ≥ 18 GB | ~10 t/s | `UD-Q4_K_M` (MoE) | Mixture-of-Experts — **26 B total / 3.8 B active per token**. Stronger reasoning and longer-context recall, faster than its file size suggests. | `🟡 HEAVY ORDNANCE` |
| **EMBEDGEMMA / 300M** | 329 MB | minimal | n/a | `Q8 QAT` | Sentence embeddings powering the v0.8 RAG layer — `#filename` autocomplete in the chat tab, journal auto-ingest, document Q&A via `/rag/query`. Booted on demand by `start-embed.*` on port 8769. | `🟢 FIELD READY` |

All weights are quantized via [unsloth](https://huggingface.co/unsloth) (Apache 2.0). The runtime is [llamafile 0.10.1](https://github.com/Mozilla-Ocho/llamafile) (Mozilla, Apache 2.0). The base Gemma 4 weights are subject to [Google's Gemma terms](https://ai.google.dev/gemma/terms).

<br>

## 🗺️ §05 · Schematic

> *How the corpse runs.*

```
   ┌─────────────────────────────────────────┐
   │                  USB                    │
   │                                         │
   │     start.bat ───┐                      │
   │                  │  invokes             │
   │                  ▼                      │
   │          ai-kit/runtime/llamafile.exe   │
   │                  │                      │
   │                  │  loads               │
   │                  ▼                      │
   │      ai-kit/models/gemma-4-*.gguf       │
   │                  │                      │
   └──────────────────│──────────────────────┘
                      │
                      │  serves HTTP API
                      ▼
            http://127.0.0.1:8765
                      │
                      │
                      ▼
            ┌─────────────────┐
            │   your browser   │
            │   chat UI        │
            └─────────────────┘
```

Inference happens **entirely on your CPU and RAM**. The USB only matters for the initial model load (~15 s for E4B, ~45 s for 26B). Once the model is in RAM, the USB could be unplugged and inference would still run at full speed. (Don't actually unplug it; that's just to illustrate where the work happens.)

No GPU required. No driver install. No Python. No Docker. No `npm install`. Nothing to download after the build.

<br>

## 🔥 §06 · Tech Note — The 4 GB Windows Trap

> *Optional reading. Skip if you just want to use the thing.*

Llamafile is a Cosmopolitan APE polyglot — a single file that's simultaneously a valid Windows `.exe`, Linux ELF, macOS Mach-O, and POSIX shell script. You can append a `.gguf` model to it via `zipalign` and end up with one double-clickable file that contains the runtime, the model, and an args file.

Beautiful. Elegant.

> [!CAUTION]
> **Doesn't work on Windows for any model larger than 4 GB.**
> The Windows PE loader uses 32-bit-signed offsets in its image headers. Past ~2 GB you're already on borrowed time, and past ~4 GB the loader rejects the file outright with the world's least helpful error: *"This app can't run on your PC."* Both Gemma 4 models are well over 4 GB, so the elegant single-file path is closed to us.

The fix (which is the [official llamafile recommendation](https://docs.mozilla.ai/llamafile/reference/troubleshooting) for >4 GB models): ship the 43 MB runtime separately from the bare `.gguf`s and invoke them together. That's what this kit does.

The legacy `zipalign` bundled-build recipe still works for sub-4-GB models if you ever want to ship one as a single double-clickable file (Linux/macOS don't have the limit, but consistency wins). Open an issue if you need that path documented in detail.

<br>

## 🛠️ §07 · Manual Build

If you'd rather not run the build script, here's what it does:

```bash
# 1. fetch the runtime (one-time)
mkdir -p runtime
curl -L -o runtime/llamafile \
  https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.1/llamafile-0.10.1-thin
cp runtime/llamafile runtime/llamafile.exe
chmod +x runtime/llamafile runtime/llamafile.exe

# 2. fetch the weights (~22 GB total — make a coffee)
mkdir -p models
curl -L -o models/gemma-4-E4B-it-Q4_K_M.gguf \
  "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true"
curl -L -o models/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf \
  "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf?download=true"
curl -L -o models/embeddinggemma-300m-qat-Q8_0.gguf \
  "https://huggingface.co/ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/resolve/main/embeddinggemma-300m-qat-Q8_0.gguf?download=true"

# 3. deploy to USB (substitute your USB mount point)
USB=/mnt/usb
mkdir -p "$USB/ai-kit"
cp -r runtime models "$USB/ai-kit/"
cp launchers/start.bat launchers/start.command launchers/start.sh "$USB/"
cp dashboard/index.html dashboard/README.txt "$USB/"
```

For smoke tests, the WSL `sh ./runtime/llamafile` quirk, and other operational notes, see §08 (Casualty Report) below.

<br>

## ⚰️ §08 · Casualty Report (Troubleshooting)

<details>
<summary><b>"This app can't run on your PC" / "not a valid application for this OS platform"</b></summary>
<br>
You're trying to run an old <code>gemma-4-*.llamafile.exe</code> bundle that's larger than 4 GB. Windows refuses. This kit no longer ships those — use the launcher (<code>start.bat</code>) instead, which uses external-weights mode.
</details>

<details>
<summary><b>"Port 8765 is being held by PID X"</b></summary>
<br>
Something else on your machine grabbed the port. Either close that app, or edit <code>start.bat</code> and change <code>set "PORT=8765"</code> to a free port. The dashboard's chat link is hardcoded to 8765, so you'll also need to manually go to <code>http://127.0.0.1:&lt;your-port&gt;</code>.
</details>

<details>
<summary><b>Model loads but generation is slow as molasses</b></summary>
<br>
Your CPU is the bottleneck. This kit is CPU-only by design (works on any host, including hosts with no GPU). For a long session, copy <code>ai-kit/runtime/llamafile.exe</code> and the model <code>.gguf</code> to your local SSD and run from there — exFAT on USB is slower than local disk for the initial load (though once loaded into RAM, generation speed is identical).
</details>

<details>
<summary><b>"APE is running on WIN32 inside WSL"</b></summary>
<br>
You're trying to run llamafile or zipalign directly inside WSL. Prefix with <code>sh</code>: <code>sh ./runtime/llamafile -m models/...</code>. The binaries are polyglot shell scripts; the <code>sh</code> prefix bypasses WSL's APE interception.
</details>

<details>
<summary><b>Browser opens but chat UI is empty / spinning forever</b></summary>
<br>
Model is still loading from USB. Wait 30-60 more seconds and refresh. Or open <code>D:\ai-kit\llamafile-e4b.log</code> to see live progress (look for <code>server is listening on http://127.0.0.1:8765</code>).
</details>

<details>
<summary><b>I want to use this from a different host. Can I just copy <code>ai-kit/</code> to my Desktop?</b></summary>
<br>
Yes — and you should, for any session longer than a few minutes. Local SSD loads ~3-4× faster than USB. Just keep the directory structure: <code>runtime/</code> next to <code>models/</code>, with the launcher one level above. Or invoke <code>runtime/llamafile -m models/&lt;file&gt;.gguf --server --host 127.0.0.1 --port 8765 -c 8192</code> directly.
</details>

<details>
<summary><b>start-vault: "vault/recovery.tar.age not found"</b></summary>
<br>
You haven't created a vault yet — the launcher's job is to decrypt an existing blob, not to bootstrap one. The launcher prints the create-vault one-liner and exits 0 (intentional — this is guidance, not an error). To create one, see <a href="docs/vault-guide.md">docs/vault-guide.md</a> Quick Start, or run from the USB:
<pre><code>cd vault/
tar c recovery/ | ../ai-kit/age/linux/age -p &gt; recovery.tar.age</code></pre>
(Use <code>mac</code> or <code>win</code> in the path on those OSes; <code>tar.exe</code> + redirect-to-Set-Content on Windows PowerShell.)
</details>

<details>
<summary><b>start-vault: "Decryption failed. Check your passphrase."</b></summary>
<br>
Either the passphrase was wrong, or the vault was encrypted to an identity file that's not on the decrypt host (Ceremony 2/3 in <a href="docs/vault-guide.md">docs/vault-guide.md</a>). Check: did you encrypt with <code>age -p</code> (passphrase) or <code>age -r</code> (recipient)? The default ceremony is <code>-p</code> — if you used <code>-r</code>, you need <code>age -d -i &lt;identity-file&gt;</code> instead of the launcher's pure-passphrase prompt. The tmpdir is auto-cleaned on decrypt failure (no partial extracts).
</details>

> [!TIP]
> **Long session?** Copy `ai-kit/runtime/llamafile(.exe)` and the model GGUF to your host's local SSD. Generation speed is identical once loaded — the USB only matters for the initial model load, and exFAT is 3-4× slower than ext4/NTFS/APFS for that.

> [!WARNING]
> **Windows Defender false-positive on first run.** Some Windows hosts will quarantine `llamafile.exe` and/or `redbean.com.exe` with a generic verdict (e.g. `Trojan:Win32/ClickFix.CCJ!MTB`). This is a known false-positive against [Cosmopolitan](https://github.com/jart/cosmopolitan) APE polyglots — the same single binary boots on Windows, Linux, and macOS, which trips heuristics tuned for normal single-OS PE32 executables. Both binaries are unmodified upstream releases (Mozilla-Ocho llamafile 0.10.1, redbean 3.0.0 from redbean.dev) with their own published SHA-256 checksums. To proceed: open **Windows Security → Protection history → Allow** on the quarantined item, or add the USB drive letter to Defender exclusions. See [`dashboard/README.txt`](dashboard/README.txt) on the USB for the full walkthrough.

<br>

## 📡 §09 · Auxiliary Equipment

Eight tools shipped from v0.4 through v0.8 — see [`docs/auxiliary-roadmap.md`](docs/auxiliary-roadmap.md) for the full living menu.

**Now in the kit:**

| Status | Item | Default size | What it adds |
|---|------|------|-------------|
| ✅ | **Whisperfile** (small.en) | ~497 MB | Audio → text via OpenAI Whisper. APE polyglot, port 8766. |
| ✅ | **Tesseract OCR** (tesseract.js) | ~15 MB | Image → text. Pure browser, no server, runs from `file://`. |
| ✅ | **Kiwix + Wikipedia** | ~395 MB (Simple EN) | Offline Wikipedia. Drop bigger ZIMs into `zim/`; kiwix-serve picks them up. Port 8767. |
| ⚠ | **DevDocs offline** | varies | Programming reference. Manual setup — see [`docs/setup-devdocs.md`](docs/setup-devdocs.md). |
| ✅ | **Organic Maps + .pbf** | ~700 KB (Monaco) | OSM regional data; sideload to phone. See [`maps/README.md`](maps/README.md) to swap region. |
| ✅ | **redbean** (3.0.0) | ~5.5 MB | Single-file APE webserver, port 8768. Local platform layer for tools that need real HTTP. Cosmopolitan family, same as llamafile. |
| ✅ | **DOOM** (Dwasm + shareware WAD) | ~7.4 MB | Browser DOOM via emscripten/PrBoom+, served by redbean. Plug-and-play; no host install. |
| ✅ | **USB-resident DOOM saves** (v0.6) | tiny | Saves persist to `ai-kit/redbean/saves.db` via redbean's `/save /load /list`. Pre-fetched on boot, hooks `FS.trackingDelegate.onCloseFile` to capture in-game saves. Travel across hosts. |
| ✅ | **TTS via Sherpa-ONNX + Supertonic** (v0.7) | ~210 MB | Text → audio. POST `text/plain` to `:8768/tts`, get `audio/wav` back. Sherpa-ONNX v1.13.1 native C++ runtime per OS (no Python on host) + Supertonic int8 (~99M params, ranks high on CPU TTS — RTF 0.3 on a literal e-reader). Pivoted away from Kokoro to avoid a Python-on-host dependency. Full research: [`docs/research/tts-rag-2026-05-08.md`](docs/research/tts-rag-2026-05-08.md). |
| ✅ | **EmbeddingGemma RAG + chat tab + journal** (v0.8) | shared with EmbedGemma + ~3.5 MB Hollama vendor | Vector index over `workspace/<name>/docs/` via redbean's `/rag/ingest` + `/rag/query` endpoints. Pure-Lua cosine over `embedding BLOB` columns (FTS5 isn't available in redbean's bundled lsqlite3 — see architecture doc for the pivot rationale). Vendored Hollama 0.35.4 chat tab at `chat/index.html` with five `_extras-*.js` adapters (`#filename` autocomplete, workspace dropdown, server-backed session persistence via `/chat/save`, three-server provider seed, daily-journal sidebar via `/journal/append`). Embedding side-arm `start-embed.*` boots EmbeddingGemma-300M on port 8769 on demand. Full design: [`docs/research/rag-architecture-2026-05-09.md`](docs/research/rag-architecture-2026-05-09.md). |
| ✅ | **age-encrypted recovery vault** (v0.9) | ~25 MB | Per-OS `age` v1.3.1 binaries at `ai-kit/age/{linux,mac,win}/`. `vault/recovery.tar.age` is the encrypted blob (user-created). Default ceremony: `tar c recovery/ \| age -p > vault/recovery.tar.age`. Launcher `start-vault.*` decrypts to host tmpdir (preserves POSIX 0600 on SSH keys). Air-gapped from redbean — no HTTP route. BSD-3, native Go binary, no APE polyglot, no Defender FP. Full guide: [`docs/vault-guide.md`](docs/vault-guide.md). |

**Still pending** (ranked by payoff):

| ⭐ | Item | Size | What it adds |
|---|------|------|-------------|
| 🥇 | **stable-diffusion.cpp + SDXL Turbo Q4** | ~3 GB | Offline image gen. |
| 🥉 | **Project Gutenberg subset + Calibre Portable** | ~3 GB | Offline classic books. |
| 🥉 | **Static ffmpeg** | ~80 MB | Media swiss-army knife; pairs with whisperfile for live captions. |
| 🥉 | **Bigger Wikipedia ZIMs** | up to ~50 GB | `wikipedia_en_top_nopic` (~6 GB) is the sweet spot. |

PRs welcome.

<br>

## 🌑 §10 · Field Notes

A few hard-earned lessons from building this:

> **The first 30 seconds matter.** If a non-technical person plugs in the stick and doesn't see something obviously clickable within the first File Explorer view, they bounce. Putting `start.bat` and `index.html` at the USB root, not buried in a folder, is the single biggest UX call this kit makes.

> **Boring beats clever.** We tried the elegant single-file `.llamafile` bundle. It failed on Windows. The "boring" pattern (runtime + bare weights + launcher script) works on every host we've tested. Boring won.

> **Offline doesn't mean obsolete.** A multi-billion-parameter open-weight model from 2026, run on a $200 laptop, would have been a research demo five years ago. Today it fits on a USB stick and answers most "I have a question" queries faster than typing the question into Google.

> **Plan for the cache miss.** USB is 3-4× slower than local SSD for model loading. Build the launcher to be polite about that ("Loading the E4B model from USB. About 15-30 seconds.") instead of leaving the user staring at a black window.

<br>

## 🤝 §11 · Enlist

This is a recipe project — the most useful contributions are:

- **New tools for the pending menu** (Whisperfile, Tesseract, Kiwix, etc.) — add a fetch step to `build-usb.{sh,ps1}` and a card to `index.html`.
- **Cross-platform launcher fixes** — anything that improves first-run reliability on a fresh host.
- **Smaller, faster, or newer models** — particularly anything ≤4 GB that could revive the legacy single-file bundled path.
- **Bug reports from real USB sticks on real hosts** — especially weird BIOS / PE loader / antivirus interactions.

Open an issue or PR. For substantial changes, please open an issue first to discuss.

<br>

## 🪦 §12 · Acknowledgments

Built on the shoulders of giants who decided portability mattered:

- **[Mozilla-Ocho/llamafile](https://github.com/Mozilla-Ocho/llamafile)** — the polyglot APE runtime that makes everything possible.
- **[Cosmopolitan Libc](https://github.com/jart/cosmopolitan)** by Justine Tunney — the underlying "build once, run anywhere" magic.
- **[unsloth](https://huggingface.co/unsloth)** — Gemma 4 GGUF quantizations (Apache 2.0).
- **[Google](https://ai.google.dev/gemma)** — Gemma 4 weights and EmbeddingGemma (Apache 2.0, plus [Gemma terms](https://ai.google.dev/gemma/terms)).
- **[Kiwix](https://kiwix.org)** & **[Ventoy](https://www.ventoy.net/)** — the offline-knowledge and bootable-USB stack we crib from.

<br>

## 📜 §13 · Legal

This recipe (everything in this repo) is licensed under the **Apache License, Version 2.0** — see [`LICENSE`](LICENSE).

Embedded artifacts retain their upstream licenses:

| Artifact | License |
|---|---|
| llamafile runtime | Apache 2.0 ([Mozilla-Ocho/llamafile](https://github.com/Mozilla-Ocho/llamafile/blob/main/LICENSE)) |
| Gemma 4 weights | Apache 2.0 + [Google's Gemma terms](https://ai.google.dev/gemma/terms) |
| EmbeddingGemma | Apache 2.0 + [Google's Gemma terms](https://ai.google.dev/gemma/terms) |
| unsloth quantizations | Apache 2.0 |
| redbean | ISC ([jart/cosmopolitan](https://github.com/jart/cosmopolitan)) |
| Dwasm bundle (`doom/index.{js,data,wasm}` + our wrapper) | **GPL-2.0** ([GMH-Code/Dwasm](https://github.com/GMH-Code/Dwasm)) |
| Shareware DOOM1.WAD | Freely redistributable per id Software (Episode 1 only) |

> [!IMPORTANT]
> **License boundary — `doom/` is GPL-2.0.** The kit as a whole is Apache-2.0
> but the `doom/` subdirectory inherits GPL-2.0 from upstream Dwasm. See
> [`doom/NOTICE.md`](doom/NOTICE.md) for the full attribution and the
> rules for modifying or redistributing files in that directory.

> [!WARNING]
> The Gemma terms add a Prohibited Use Policy on top of Apache 2.0. **Read it before redistributing the weights commercially.**

<br>

---

<div align="center">

```
                      _ ._  _ , _ ._
                    (_ ' ( `  )_  .__)
                  ( (  (    )   `)  ) _)
                 (__ (_   (_ . _) _) ,__)
                     `~~`\ ' . /`~~`
                          ;   ;
                          /   \
_________________________/_ __ \_____________
```

```
╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲

              ╔════════════════════════════════╗
              ║   DECLASSIFIED · 2026·05·09    ║
              ║      — USE WITH CAUTION —      ║
              ╚════════════════════════════════╝

╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲
```

**stay weird. stay prepared. stay offline.**

`v0.9.0 · "the vault" · 2026·05·09`

</div>
