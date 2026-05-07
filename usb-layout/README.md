# usb-layout/ — what your USB should look like after building

This directory is an **empty skeleton** showing the file tree the assembled
kit produces on a target USB stick. It's checked into the repo so contributors
can see the deployment shape at a glance without running the build script.

```
usb-layout/                       ← this directory == USB root after build
├── README.md                     ← (this file; not deployed)
├── start.bat                     ← (placeholder; real file copied from launchers/)
├── start.command                 ← (placeholder; real file copied from launchers/)
├── start.sh                      ← (placeholder; real file copied from launchers/)
├── index.html                    ← (placeholder; real file copied from repo root)
├── README.txt                    ← (placeholder; real file copied from repo root)
└── ai-kit/
    ├── runtime/
    │   ├── llamafile             ← (43 MB; fetched from Mozilla-Ocho/llamafile releases)
    │   └── llamafile.exe         ← (byte-identical copy renamed for Windows)
    └── models/
        ├── gemma-4-E4B-it-Q4_K_M.gguf            ← (5 GB; fetched from huggingface.co/unsloth)
        ├── gemma-4-26B-A4B-it-UD-Q4_K_M.gguf    ← (17 GB; fetched from huggingface.co/unsloth)
        └── embeddinggemma-300m-qat-Q8_0.gguf    ← (329 MB; fetched from huggingface.co/ggml-org)
```

## What you actually see in this directory of the repo

Each subdirectory has a `.gitkeep` and a small `README.md` describing what
file lives there on the real USB. The large binary artifacts (runtime + 3
GGUFs, totalling ~22 GB) are **not** committed — that would blow past
GitHub's 100 MB per-file limit and bloat the repo to absurdity.

To populate this skeleton with the real artifacts, run the build script
from the repo root and point it at this directory:

```bash
./build-usb.sh ./usb-layout      # fills in runtime/ and models/ in place
```

…or point it at a real USB mount point (`/mnt/usb`, `D:\`, `/Volumes/USB`)
to get a working stick directly.

## Why ship this skeleton at all?

Three reasons:

1. **Documentation that can't drift from reality.** A tree diagram in a
   README rots; an actual directory layout doesn't. If the build script
   creates a new path, the skeleton is updated in the same commit.
2. **`build-usb.{sh,ps1}` can mirror it.** The scripts know exactly which
   paths to create and where to drop each file because the skeleton names
   them.
3. **Contributors can preview placement.** When adding a new tool (Whisperfile,
   Tesseract, etc.) to the kit, you mock up its USB-side path here first,
   then teach the build script to populate it.
