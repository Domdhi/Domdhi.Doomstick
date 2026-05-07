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
+-- start.bat / .command / .sh       Launcher (model-picker menu)
+-- README.txt                       This file
|
+-- ai-kit\                          The portable AI runtime + models
    +-- runtime\
    |   +-- llamafile               43 MB inference engine (Linux/macOS)
    |   +-- llamafile.exe           Same engine, named for Windows
    +-- models\
    |   +-- gemma-4-E4B-it-Q4_K_M.gguf            Daily driver  (~5 GB)
    |   +-- gemma-4-26B-A4B-it-UD-Q4_K_M.gguf     Big brain MoE (~17 GB)
    |   +-- embeddinggemma-300m-qat-Q8_0.gguf     Embeddings (RAG/search)
    +-- llamafile-{e4b,26b}.log     Created on first run (full server log)


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
ADD-ONS YOU CAN BRING YOURSELF (BYO)
-------------------------------------------------------------------------

This kit is just the AI runtime + weights + launchers. If you want to
turn the same USB into a full survival/dev stick, drop the following
on alongside ai-kit/ -- nothing in the launcher cares about siblings:

  *.iso       Bootable rescue media (Ubuntu, SystemRescue, Hiren's BootCD).
              Add Ventoy (https://www.ventoy.net/) to make the stick
              boot-menu its own ISO collection.
  tools\      Portable Windows utilities (PortableGit, VS Code Portable,
              ripgrep, fzf, jq, 7-Zip).
  zim\        Offline Wikipedia / medical references via Kiwix
              (https://kiwix.org).
  vault\      An age-encrypted tarball of dotfiles, SSH keys, 2FA codes.

See README.md in the source repo for the full pending menu and
per-item rationale.


-------------------------------------------------------------------------
LICENSE
-------------------------------------------------------------------------

Recipe: Apache 2.0 (see source repo for LICENSE).
Embedded artifacts:
  - llamafile runtime  -> Apache 2.0
  - Gemma 4 weights    -> Apache 2.0 + Google Gemma terms
  - EmbeddingGemma     -> Apache 2.0 + Google Gemma terms
  - unsloth quants     -> Apache 2.0

Built with: Mozilla llamafile 0.10.1, Gemma 4 GGUFs from unsloth,
EmbeddingGemma-300M Q8 QAT from Google (via ggml-org).
