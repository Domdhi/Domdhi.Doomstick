# doom/ — third-party attribution & license boundary

Everything in this `doom/` subdirectory is licensed differently from the rest
of the Doomstick repo. The repo as a whole is **Apache-2.0**; the `doom/`
subdirectory is **GPL-2.0**, inherited from upstream Dwasm.

## What's here

| File | Origin | License |
|------|--------|---------|
| `index.html` | Doomstick wrapper (derivative of Dwasm's `index.html`) | GPL-2.0 |
| `index.js`   | Dwasm — emscripten loader, unmodified | GPL-2.0 |
| `index.data` | Dwasm — emscripten preload data, unmodified | GPL-2.0 |
| `index.wasm` | Dwasm — compiled PrBoom+ engine, unmodified | GPL-2.0 |
| `doom1.wad`  | id Software — shareware DOOM1.WAD, fetched at build time | Shareware (free redistribution) |
| `LICENSE-GPL-2.0` | GNU General Public License, version 2 | — |
| `NOTICE.md`  | This file | Apache-2.0 |

## Upstream

- **Dwasm:** https://github.com/GMH-Code/Dwasm
  - Author: Gregory Maynard-Hoare
  - This is a derivative of [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom)
    via [PrBoom+](https://github.com/coelckers/prboom-plus) and
    [PrBoomX](https://github.com/cs-rkroll/PrBoomX), compiled to WebAssembly
    via Emscripten.
  - Per GPL-2.0 §3(b), the corresponding source is available from the
    upstream repository above. We're distributing unmodified binary
    artifacts (`index.js`, `index.data`, `index.wasm`) plus a
    derivative-work HTML wrapper.

- **Shareware DOOM1.WAD:** id Software, 1993.
  - id Software has long permitted free redistribution of the shareware
    Episode 1 ("Knee-Deep in the Dead") IWAD. It is included here at build
    time, fetched from a public mirror.
  - Episodes 2 ("The Shores of Hell") and 3 ("Inferno"), the registered/
    full-version IWADs, plus DOOM II's IWAD are NOT shareware and are NOT
    redistributed by Doomstick. If you own them, you can drop them into
    `doom/` on the USB and rename one of the supported port options in the
    Dwasm UI to load them — though Doomstick's wrapper currently
    auto-loads `doom1.wad` only.

## Modifying

If you modify any GPL-2.0 file in this directory and redistribute the
result, you must:
1. Comply with GPL-2.0 §1 and §2 (preserve license/copyright, mark
   modifications, distribute under GPL-2.0).
2. Make corresponding source available per GPL-2.0 §3.

The Apache-2.0 license that covers the rest of the Doomstick repo does
NOT extend into this directory. The boundary is the `doom/` directory
root.

## Why ship pre-built binaries instead of building from source?

The Doomstick repo is a build recipe: the user runs `build-usb.sh` and
gets a USB. Asking them to install Emscripten + a C toolchain + Python
just to build DOOM defeats that simplicity. Vendoring the pre-built
artifacts (~3.2 MB) is consistent with how we ship llamafile (also a
prebuilt binary blob fetched at build time).

The exact upstream commit / build date used for the vendored
`index.js` / `index.data` / `index.wasm` is recorded in this repo's git
history at the time those files were committed.
