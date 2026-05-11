PORTABLE OFFLINE AI KIT
=======================

Self-contained AI on a USB stick. No install, no internet, no GPU.
Two language models you can run on Windows, macOS, or Linux from the
same files.

Plug it in. Open the USB and double-click:

  start.bat       on Windows
  start.command   on macOS
  start.sh        on Linux

A model menu appears. Pick one. Wait 15-90 seconds. Your browser opens
at http://127.0.0.1:8765 with a chat UI. That's the whole UX.

For a one-page dashboard, double-click index.html.


-------------------------------------------------------------------------
LAYOUT
-------------------------------------------------------------------------

USB root
+-- index.html                       One-page dashboard for everything
+-- start.bat / .command / .sh       AI launcher (Gemma 4 + Qwen3 picker)
+-- start-whisper.{bat,command,sh}   Whisperfile (audio -> text, port 8766)
+-- start-wiki.{bat,command,sh}      Kiwix (offline Wikipedia, port 8767)
+-- start-ocr.{bat,command,sh}       OCR (image -> text, browser only)
+-- start-docs.{bat,command,sh}      DevDocs (programming reference; manual setup)
+-- README.txt                       This file
|
+-- start-embed.{bat,command,sh}     Embedding side-arm (port 8769; for RAG)
+-- start-vault.{bat,command,sh}     Recovery vault decrypt (port-free)
+-- start-img.{bat,command,sh}       Field sketch generator (sd.cpp + FLUX)
+-- chat\                            Hollama chat tab (file://, AI + RAG + journal)
+-- workspace\                       Per-workspace docs/ + journal/ folders (RAG corpus)
|
+-- ai-kit\                          AI runtime + models + side-arm binaries
|   +-- runtime\
|   |   +-- llamafile               43 MB inference engine (Linux/macOS)
|   |   +-- llamafile.exe           Same engine, named for Windows
|   +-- models\
|   |   +-- gemma-4-E4B-it-Q4_K_M.gguf            Daily driver  (~5 GB)
|   |   +-- gemma-4-26B-A4B-it-UD-Q4_K_M.gguf     Big brain MoE (~17 GB)
|   |   +-- Qwen3-4B-Q4_K_M.gguf                  Lightest LLM + FLUX.2 encoder (~2.33 GB)
|   |   +-- embeddinggemma-300m-qat-Q8_0.gguf     Embeddings (RAG/search)
|   +-- whisper\
|   |   +-- whisper-base.en.llamafile             Whisperfile (~148 MB)
|   +-- kiwix\
|   |   +-- linux\, mac\, win\                    kiwix-serve binaries per OS
|   +-- redbean\
|   |   +-- redbean.com                            Local platform layer (port 8768)
|   |   +-- saves.db                               DOOM saves + chat sessions + RAG chunks
|   +-- sherpa-tts\
|   |   +-- linux\, mac\, win\                     sherpa-onnx-offline-tts per OS
|   |   +-- models\supertonic\                     Supertonic int8 ONNX (~120 MB)
|   +-- age\
|   |   +-- linux\, mac\, win\                     age binary per OS (~9 MB each)
|   +-- sd-img\                             stable-diffusion.cpp + FLUX.2 klein
|   |   +-- linux\, mac\, win\              sd-cli + libstable-diffusion per OS (~30-50 MB each)
|   |   +-- models\flux-2-klein-4b-Q4_K_M.gguf            FLUX.2 klein transformer (~2.43 GB)
|   |   +-- models\full_encoder_small_decoder.safetensors FLUX.2 small-decoder VAE (~238 MB)
|   +-- *.log                       Created on first run of each tool
|
+-- zim\                             Wikipedia ZIM file(s) for kiwix-serve
+-- ocr\                             tesseract.js static page + lang packs
+-- maps\                            OSM regional .pbf (sideload to phone)
+-- docs-offline\                    DevDocs (manual setup)
+-- vault\                           age-encrypted recovery vault
|   +-- README.txt                   Ceremony + key-loss warning
|   +-- recovery.tar.age             User-created encrypted blob (not in kit)


-------------------------------------------------------------------------
QUICK START - RUN THE AI
-------------------------------------------------------------------------

Windows:    Double-click  start.bat
macOS:      Double-click  start.command
Linux:      chmod +x start.sh && ./start.sh

A menu appears:

  [1]  Gemma 4 E4B   --   5 GB    needs 8+ GB RAM
  [2]  Gemma 4 26B   --  17 GB   needs 18+ GB RAM (MoE, surprisingly fast)
  [3]  Qwen3 4B      --  2.3 GB  needs 4+ GB RAM  (lightest, only if image gen built)

Pick a number. The model loads in ~15-30 s (E4B/Qwen3) or ~45-90 s (26B). A
browser tab opens at http://127.0.0.1:8765 with the chat UI. Press any
key in the launcher window to stop the model.

Only one model runs at a time. To switch models, stop the current one
and run start.bat / .command / .sh again.


-------------------------------------------------------------------------
NOTES
-------------------------------------------------------------------------

USB exFAT is slow. If you'll use the AI for more than a few minutes on
a host, copy ai-kit/runtime/llamafile(.exe) and the model GGUF you want
to the host's Desktop first and run from there - much faster. Once the
model is loaded into RAM, generation speed is identical to a local SSD;
the USB only matters for the initial model load.

The 26B model is a Mixture-of-Experts. Its 17 GB file is misleading:
only ~4 GB of weights are active per token, so once loaded it runs at
speeds closer to a 4 GB model.

Why a separate runtime + .gguf instead of one bundled .exe? Windows
can't run .exe files larger than 4 GB. Both Gemma 4 models are well
above that, so we ship the 43 MB runtime separately from the bare
weights.


-------------------------------------------------------------------------
WINDOWS DEFENDER FALSE-POSITIVE ON FIRST RUN
-------------------------------------------------------------------------

Some Windows hosts will quarantine llamafile.exe and/or redbean.com.exe
on first launch with a generic verdict (e.g. "Trojan:Win32/ClickFix.CCJ!MTB").
This is a known false-positive against Cosmopolitan APE polyglot binaries
- the same single file boots on Windows, Linux, and macOS, which trips
heuristic detection that's tuned for normal single-OS PE32 executables.

The binaries are unmodified upstream releases:
  - llamafile.exe = Mozilla-Ocho llamafile 0.10.1 (Apache 2.0)
  - redbean.com.exe = redbean 3.0.0 from redbean.dev (ISC)

Both are published with their own SHA-256 checksums on their respective
release pages; you can verify either before allowing.

To proceed: open Windows Security -> Protection history -> Allow on the
quarantined item, OR add the USB drive letter to Defender exclusions
(Settings -> Virus & threat protection -> Manage settings -> Exclusions).

We've reported the false-positive to Microsoft. Once their MAPS
classifier picks up the cleaner sample, the warning will stop appearing.


-------------------------------------------------------------------------
FIRST-RUN CHAT TAB ONBOARDING (v0.8+)
-------------------------------------------------------------------------

The chat tab at chat/index.html is a vendored Hollama 0.35.4 frontend
seeded with three local servers (E4B at :8765, 26B at :8765, embeddings
at :8769). On first boot a toast confirms the seed.

For the model picker to populate, open Settings (the gear icon in the
sidebar) and click "Re-verify" next to each server you want to use.
That kicks Hollama's connection check, which lists the local model
behind that endpoint. The Send button stays disabled until at least one
verified server has a selected model.

You only do this once per browser profile per USB. The seed and verify
state both live in localStorage, so re-opening the tab on the same host
remembers everything. A different host or a private window starts fresh.


-------------------------------------------------------------------------
SIDE ARMS (shipped with the kit)
-------------------------------------------------------------------------

  start-whisper.{bat,command,sh}    Whisperfile audio-to-text (Whisper
                                    base.en, ~148 MB). GUI on port 8766.

  start-wiki.{bat,command,sh}       Kiwix-serve. Default ZIM is Simple
                                    English Wikipedia (~395 MB). To swap
                                    in a bigger ZIM, drop another .zim
                                    into zim/ and re-run; kiwix-serve
                                    serves them all.

  start-ocr.{bat,command,sh}        Tesseract.js OCR static page. English
                                    by default; drop more .traineddata
                                    files into ocr/lang-data/ for other
                                    languages.

  start-docs.{bat,command,sh}       DevDocs offline. Not auto-fetched
                                    by build-usb -- see docs-offline/
                                    README.txt for the manual setup.

  maps/<region>.osm.pbf             OSM regional data. Mobile-only --
                                    sideload to Organic Maps on Android
                                    or iOS. See maps/README.md.

  POST :8768/tts                    Sherpa-ONNX + Supertonic int8 TTS,
                                    rides on redbean (no extra launcher).
                                    Plain-text body in, audio/wav out.
                                    Native C++ binaries per OS, no
                                    Python on host.

  start-embed.{bat,command,sh}      Embedding side-arm for RAG. Boots
                                    EmbeddingGemma-300M Q8 on port 8769.
                                    Required when using the chat tab's
                                    document-aware features (#filename
                                    autocomplete, journal, /rag/query).

  start-vault.{bat,command,sh}      age vault decrypt. Decrypts
                                    vault/recovery.tar.age to a
                                    host tmpdir. See vault/README.txt
                                    for the creation ceremony.

  start-img.{bat,command,sh}        Offline image gen. Type a prompt,
                                    get a 1024x1024 PNG. ~1-3 min on
                                    CPU; stops nothing automatically
                                    but needs ~8-10 GB working RAM
                                    (loads transformer + Qwen3-4B
                                    text encoder + VAE all together).
                                    See docs/img-guide.md.

  start-passwords.{bat,command,sh}  KeePassXC GUI password manager.
                                    Opens your vault.kdbx in
                                    passwords/ (create it on first
                                    run). Native per-OS binaries,
                                    no network. GPL-2.0+. ~250 MB
                                    cross-OS.

  start-ffmpeg.{bat,command,sh}     Sets PATH to ai-kit/ffmpeg/<os>/
                                    then drops into a shell with
                                    ffmpeg + ffprobe available. Pairs
                                    with start-whisper (pre-process
                                    audio) and start-img (post-process
                                    frames). No port, no server.
                                    GPL-3.0+. ~210 MB cross-OS.

  start-devtools.{bat,command,sh}   Adds ripgrep, fzf, jq, 7-Zip, and
                                    VSCodium to PATH then drops into an
                                    interactive shell. Type rg, fzf, jq,
                                    7zzs/7zz/7za, or codium directly. No
                                    port. Mixed licenses (MIT for rg/fzf/
                                    jq/VSCodium; LGPL-2.1 for 7-Zip).
                                    PortableGit deferred to v0.12.1.
                                    ~280 MB cross-OS. ai-kit/devtools/.

  field-manual/index.html           Public-domain offline reference
                                    library: survival basics (FM 21-76),
                                    FEMA CERT first aid, edible plants,
                                    FCC Part 97 amateur radio, EPA well
                                    water, pre-1928 knots. Open in any
                                    browser via file://. Add your own .md
                                    files to field-manual/ to extend it.
                                    All US Government works (PD per
                                    17 U.S.C. § 105) + pre-1928 sources.

  ai-kit/certs/cacert.pem           Mozilla CA certificate bundle
                                    (~226 KB, MPL-2.0). Always-on (no
                                    toggle). Use with:
                                      curl --cacert ./cacert.pem https://...
                                    or REQUESTS_CA_BUNDLE=./cacert.pem

  chat\index.html                   Vendored Hollama 0.35.4 chat UI with
                                    workspace/RAG/journal/session adapters.
                                    Open as a file:// in any modern
                                    browser. Talks to redbean on :8768
                                    for persistence and to the AI cores.

  workspace\<name>\docs\            Per-workspace document corpus for RAG.
                                    Drop .md/.txt/.pdf-extracted text in;
                                    use the chat tab's #filename
                                    autocomplete or POST /rag/ingest to
                                    add chunks to the index.


-------------------------------------------------------------------------
ADD-ONS YOU CAN BRING YOURSELF (BYO)
-------------------------------------------------------------------------

If you want to turn the same USB into a full survival/dev stick, drop
the following alongside ai-kit/ -- nothing in the launchers cares about
siblings:

  *.iso       Bootable rescue media (Ubuntu, SystemRescue, Hiren's BootCD).
              Add Ventoy (https://www.ventoy.net/) to make the stick
              boot-menu its own ISO collection.

See README.md in the source repo and docs/auxiliary-roadmap.md for the
full pending menu and per-item rationale.


-------------------------------------------------------------------------
FROM A PHONE
-------------------------------------------------------------------------

Plug the USB into your phone via USB-OTG (Android) or Lightning/USB-C
(iOS via the Files app). Open mobile.html in your phone browser -- it
redirects to the dashboard's Mobile Field Kit, which points at the
right consumer app for each capability.

What works on a phone today:

  Wikipedia ZIM     -> Kiwix app          (F-Droid / Play / App Store)
  OSM regional PBF  -> Organic Maps app   (F-Droid / Play / App Store)
  GGUF models       -> PocketPal AI app   (Play / App Store)
                       (slow on phones; usable for short turns)
  ocr/index.html    -> mobile browser     (no app, take a photo)
  doom/index.html   -> mobile browser     (no app, touch controls)
  docs-offline/     -> mobile browser     (no app, responsive)

What does NOT work on a phone:

  start.bat / .command / .sh   -- desktop launchers, irrelevant on phone
  llamafile (the AI core)      -- different ABI; phone can't execute it
  Whisperfile, kiwix-serve     -- same family
  redbean's /save and /tts     -- redbean isn't running on the phone

DOOM saves only persist on desktop (saves bridge to redbean). DOOM on
mobile is a fresh playthrough each session.

Install the apps once over a connection, then unplug. The kit's data
files travel with the stick across hosts. Internet is optional after
first install.


-------------------------------------------------------------------------
LICENSE
-------------------------------------------------------------------------

Recipe: Apache 2.0 (see source repo for LICENSE).
Embedded artifacts:
  - llamafile runtime    -> Apache 2.0
  - Whisperfile          -> Apache 2.0
  - Gemma 4 weights      -> Apache 2.0 + Google Gemma terms
  - EmbeddingGemma       -> Apache 2.0 + Google Gemma terms
  - unsloth quants       -> Apache 2.0
  - kiwix-tools          -> GPL-3.0
  - tesseract.js         -> Apache 2.0
  - tessdata_fast (eng)  -> Apache 2.0
  - OSM .pbf data        -> ODbL (attribute "(c) OpenStreetMap contributors")

Built with: Mozilla llamafile 0.10.1, Mozilla whisperfile, Gemma 4
GGUFs from unsloth, EmbeddingGemma-300M Q8 QAT from Google (via
ggml-org), kiwix-tools (kiwix.org), tesseract.js (Naptha), Geofabrik
.pbf extracts.
