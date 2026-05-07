# Portable Offline AI Kit

> Build a USB stick that runs a 7-billion-parameter language model on any
> Windows / macOS / Linux laptop, with no install, no internet, no GPU, no
> Python, no Docker, no telemetry. Plug in, double-click, chat.

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

      CLASSIFICATION  ▸  PUBLIC               DOOMSTICK · v0.3 · 2026·05·06
      TRANSMISSION    ▸  OFFLINE              COSMOPOLITAN · CPU-ONLY · USB
      AUTH            ▸  Apache-2.0           ENDPOINT · 127.0.0.1 : 8765

      ◉ NETWORK    [ lost ]
      ◉ POWER      [ usb · D:\ ]
      ◉ AI CORE    [ stand·by ]                ← flips to [armed] on launch

╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲
```

<br>

## ☢️ §01 · The Pitch

You're somewhere with no signal. Maybe the WiFi died. Maybe the router died. Maybe **the internet died**. You still have a laptop and a USB stick.

You plug the stick in. Double-click one file. Thirty seconds later you're chatting with a 7-billion-parameter language model that can:

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
├── launchers/              start.{bat,command,sh} — the model-picker menu
├── usb-layout/             Empty skeleton showing the target USB structure
├── e4b.args / 26b.args     Source-of-truth flag list (mirrored in launchers)
├── index.html              Static dashboard (deploys to USB root)
├── README.txt              Plain-text version of this doc (deploys to USB root)
└── README.md               This file
```

**What `build-usb.sh /mnt/usb` produces:**

```
/mnt/usb/                                       ~22 GB total
├── 📄 index.html                     One-page dashboard. Open this first.
├── 🚀 start.bat                       Windows launcher (double-click to chat)
├── 🚀 start.command                   macOS launcher
├── 🚀 start.sh                        Linux launcher
├── 📜 README.txt                      Short version of this doc
│
└── 🧠 ai-kit/                         The brain
    ├── runtime/
    │   ├── llamafile                  43 MB inference engine (Linux/macOS)
    │   └── llamafile.exe              Same binary, .exe-renamed for Windows
    └── models/
        ├── gemma-4-E4B-it-Q4_K_M.gguf            5 GB,  daily driver
        ├── gemma-4-26B-A4B-it-UD-Q4_K_M.gguf    17 GB, big brain MoE
        └── embeddinggemma-300m-qat-Q8_0.gguf    329 MB, for RAG (no chat UI yet)
```

**What the kit does *not* ship** (BYO if you want them):

- Bootable rescue ISOs (Ubuntu / SystemRescue / Hiren's BootCD PE) + [Ventoy](https://www.ventoy.net/)
- Portable Windows tools (PortableGit, VS Code Portable, ripgrep, fzf, jq, 7-Zip)
- Offline Wikipedia ([Kiwix](https://kiwix.org) `.zim` files)
- Offline maps, offline TTS/STT, etc.

These are listed in §09 below — most are one-line additions to the build script when you feel like it.

<br>

## 🔌 §03 · Initiation Protocol

> *Or: how to talk to a god in the dark.*

### Build the kit onto a USB

```bash
git clone https://github.com/Domdhi/Domdhi.Doomstick.git
cd Domdhi.Doomstick

# Linux / macOS / WSL:
./build-usb.sh /mnt/usb              # path to mounted USB

# Windows (native PowerShell, run as Admin if writing to USB root):
.\build-usb.ps1 D:\
```

The script downloads the runtime (~43 MB) and three GGUFs (~22 GB), copies the launchers and dashboard, and prints the exact `start.*` path to double-click. Resumable — re-running it skips files that already exist with the right size.

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

## 🧠 §04 · Payload Manifest

Three weights ship with the kit. Two appear in the launcher menu; the third is for retrieval, not chat.

| Callsign | Size | RAM | Speed (CPU) | Quant | Role | Status |
|---|---|---|---|---|---|---|
| **GEMMA-4 / E4B** | 5.0 GB | ≥ 8 GB | ~15 t/s | `Q4_K_M` | Daily driver. Chat, code, summaries, translation. Good enough for ~95% of normal questions. | `🟢 FIELD READY` |
| **GEMMA-4 / 26B-A4B** | 17 GB | ≥ 18 GB | ~10 t/s | `UD-Q4_K_M` (MoE) | Mixture-of-Experts. Stronger reasoning, longer-context recall. 3.8 B params active per token, so faster than its file size suggests. | `🟡 HEAVY ORDNANCE` |
| **EMBEDGEMMA / 300M** | 329 MB | minimal | n/a | `Q8 QAT` | Sentence embeddings for RAG. Future tools will use it to chat with documents. Not in the launcher menu. | `🤍 QUARTERMASTER` |

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
cp index.html README.txt "$USB/"
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

> [!TIP]
> **Long session?** Copy `ai-kit/runtime/llamafile(.exe)` and the model GGUF to your host's local SSD. Generation speed is identical once loaded — the USB only matters for the initial model load, and exFAT is 3-4× slower than ext4/NTFS/APFS for that.

<br>

## 📡 §09 · Auxiliary Equipment (Pending)

The "cool shit we haven't built yet" list, ranked by payoff per gigabyte:

| ⭐ | Item | Size | What it adds |
|---|------|------|-------------|
| 🥇 | **Whisperfile** | ~3 GB | Audio → text. First leg of an offline voice stack (mic → whisper → Gemma → speaker). |
| 🥇 | **Tesseract OCR + lang data** | ~70 MB | Photo / scan → text. Pipes naturally into the LLM. |
| 🥇 | **redbean** | ~6 MB | Single-file APE webserver with Lua + SQLite. Same Cosmopolitan family as llamafile. |
| 🥈 | **Kiwix + Wikipedia .zim** | ~14 GB | Offline Wikipedia. The big one. |
| 🥈 | **Piper TTS** | ~100 MB | Text → audio. Completes the voice stack. |
| 🥉 | **stable-diffusion.cpp + SDXL Turbo Q4** | ~3 GB | Offline image gen. |
| 🥉 | **devdocs offline** | ~1 GB | Static-HTML programming reference (MDN, Python, man pages). |
| 🥉 | **age-encrypted recovery vault** | tiny | SSH/GPG keys, dotfiles, 2FA codes, scanned IDs in one encrypted tarball. |
| 🥉 | **Project Gutenberg subset + Calibre Portable** | ~3 GB | Offline classic books. |
| 🥉 | **Static ffmpeg** | ~80 MB | Media swiss-army knife; pairs with whisperfile for live captions. |
| 🥉 | **Organic Maps + regional .pbf** | ~500 MB | Offline maps + routing. |

PRs welcome.

<br>

## 🌑 §10 · Field Notes

A few hard-earned lessons from building this:

> **The first 30 seconds matter.** If a non-technical person plugs in the stick and doesn't see something obviously clickable within the first File Explorer view, they bounce. Putting `start.bat` and `index.html` at the USB root, not buried in a folder, is the single biggest UX call this kit makes.

> **Boring beats clever.** We tried the elegant single-file `.llamafile` bundle. It failed on Windows. The "boring" pattern (runtime + bare weights + launcher script) works on every host we've tested. Boring won.

> **Offline doesn't mean obsolete.** A 7B model from 2026, run on a $200 laptop, would have been a research demo five years ago. Today it fits on a USB stick and answers most "I have a question" queries faster than typing the question into Google.

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

In the broader portable-AI ecosystem, see also [techjarves/Portable-AI-USB](https://github.com/techjarves/Portable-AI-USB) (Ollama + AnythingLLM, runs from USB but requires extraction to host) and [Project NOMAD](https://www.projectnomad.us/) (offline AI + Wikipedia + Kolibri server, requires Ubuntu/Debian install). This kit's niche is **zero-install, zero-runtime-download, fully USB-resident** — none of the others reach all three at once.

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

> [!WARNING]
> The Gemma terms add a Prohibited Use Policy on top of Apache 2.0. **Read it before redistributing the weights commercially.**

<br>

---

<div align="center">

```
                          _.-^^---....,,--_
                      _--                  --_
                     <                        >)
                     |                         |
                      \._                   _./
                         ```--. . , ; .--'''
                               | |   |
                            .-=||  | |=-.
                            `-=#$%&%$#=-'
                               | ;  :|
                      _____.,-#%&$@%#&#~,._____
```

```
╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲

              ╔════════════════════════════════╗
              ║   DECLASSIFIED · 2026·05·06    ║
              ║      — USE WITH CAUTION —      ║
              ╚════════════════════════════════╝

╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲
```

**stay weird. stay prepared. stay offline.**

`v0.3 · "external weights + build script" · 2026·05·06`

</div>
