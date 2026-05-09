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
+-- start.bat / .command / .sh       AI launcher (Gemma 4 model-picker)
+-- start-whisper.{bat,command,sh}   Whisperfile (audio -> text, port 8766)
+-- start-wiki.{bat,command,sh}      Kiwix (offline Wikipedia, port 8767)
+-- start-ocr.{bat,command,sh}       OCR (image -> text, browser only)
+-- start-docs.{bat,command,sh}      DevDocs (programming reference; manual setup)
+-- README.txt                       This file
|
+-- ai-kit\                          AI runtime + models + side-arm binaries
|   +-- runtime\
|   |   +-- llamafile               43 MB inference engine (Linux/macOS)
|   |   +-- llamafile.exe           Same engine, named for Windows
|   +-- models\
|   |   +-- gemma-4-E4B-it-Q4_K_M.gguf            Daily driver  (~5 GB)
|   |   +-- gemma-4-26B-A4B-it-UD-Q4_K_M.gguf     Big brain MoE (~17 GB)
|   |   +-- embeddinggemma-300m-qat-Q8_0.gguf     Embeddings (RAG/search)
|   +-- whisper\
|   |   +-- whisper-base.en.llamafile             Whisperfile (~148 MB)
|   +-- kiwix\
|   |   +-- linux\, mac\, win\                    kiwix-serve binaries per OS
|   +-- redbean\
|   |   +-- redbean.com                            Local platform layer (port 8768)
|   |   +-- saves.db                               DOOM save slots (created on first save)
|   +-- sherpa-tts\
|   |   +-- linux\, mac\, win\                     sherpa-onnx-offline-tts per OS
|   |   +-- models\supertonic\                     Supertonic int8 ONNX (~120 MB)
|   +-- *.log                       Created on first run of each tool
|
+-- zim\                             Wikipedia ZIM file(s) for kiwix-serve
+-- ocr\                             tesseract.js static page + lang packs
+-- maps\                            OSM regional .pbf (sideload to phone)
+-- docs-offline\                    DevDocs (manual setup)


-------------------------------------------------------------------------
QUICK START - RUN THE AI
-------------------------------------------------------------------------

Windows:    Double-click  start.bat
macOS:      Double-click  start.command
Linux:      chmod +x start.sh && ./start.sh

A menu appears:

  [1]  Gemma 4 E4B   --   5 GB    needs 8+ GB RAM
  [2]  Gemma 4 26B   --  17 GB   needs 18+ GB RAM (MoE, surprisingly fast)

Pick a number. The model loads in ~15-30 s (E4B) or ~45-90 s (26B). A
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


-------------------------------------------------------------------------
ADD-ONS YOU CAN BRING YOURSELF (BYO)
-------------------------------------------------------------------------

If you want to turn the same USB into a full survival/dev stick, drop
the following alongside ai-kit/ -- nothing in the launchers cares about
siblings:

  *.iso       Bootable rescue media (Ubuntu, SystemRescue, Hiren's BootCD).
              Add Ventoy (https://www.ventoy.net/) to make the stick
              boot-menu its own ISO collection.
  tools\      Portable Windows utilities (PortableGit, VS Code Portable,
              ripgrep, fzf, jq, 7-Zip).
  vault\      An age-encrypted tarball of dotfiles, SSH keys, 2FA codes.

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
