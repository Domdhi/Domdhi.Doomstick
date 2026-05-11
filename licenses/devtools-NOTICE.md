# licenses/devtools-NOTICE.md — third-party attribution & license boundary

Everything in `ai-kit/devtools/` is licensed differently from the rest of
the Doomstick repo. The repo as a whole is **Apache-2.0**; the binaries
shipped inside `ai-kit/devtools/` carry a mix of **MIT** (ripgrep, fzf, jq,
VSCodium) and **LGPL-2.1-or-later** (7-Zip) licenses. This is the first
composite-license boundary in the kit. Both license texts are included in
`licenses/devtools-LICENSES/`. The boundary is the `ai-kit/devtools/`
directory on the deployed USB.

## What's here

| Tool | File / directory | Approx. size | License |
|------|-----------------|--------------|---------|
| ripgrep | `ai-kit/devtools/linux/rg` | ~3 MB | MIT |
| ripgrep | `ai-kit/devtools/mac/rg` | ~3 MB | MIT |
| ripgrep | `ai-kit/devtools/win/rg.exe` | ~4 MB | MIT |
| fzf | `ai-kit/devtools/linux/fzf` | ~4 MB | MIT |
| fzf | `ai-kit/devtools/mac/fzf` | ~4 MB | MIT |
| fzf | `ai-kit/devtools/win/fzf.exe` | ~5 MB | MIT |
| jq | `ai-kit/devtools/linux/jq` | ~3 MB | MIT |
| jq | `ai-kit/devtools/mac/jq` | ~4 MB | MIT |
| jq | `ai-kit/devtools/win/jq.exe` | ~4 MB | MIT |
| 7-Zip | `ai-kit/devtools/linux/7zzs` | ~2 MB | LGPL-2.1-or-later |
| 7-Zip | `ai-kit/devtools/mac/7zz` | ~2 MB | LGPL-2.1-or-later |
| 7-Zip | `ai-kit/devtools/win/7za.exe` | ~1 MB | LGPL-2.1-or-later |
| VSCodium | `ai-kit/devtools/linux/vscode/` subtree | ~80 MB | MIT |
| VSCodium | `ai-kit/devtools/mac/vscode/` subtree | ~80 MB | MIT |
| VSCodium | `ai-kit/devtools/win/vscode/` subtree | ~80 MB | MIT |

Note on 7-Zip naming inconsistency: upstream ships `7zzs` (static) on Linux,
`7zz` (static) on macOS, and `7za.exe` (console-only build) on Windows. The
macOS binary is named `7zz`, not `7zzs` — this is deliberate upstream
behaviour, not a build error.

All binaries are unmodified official releases from their respective upstreams.

### Deferred: PortableGit

PortableGit (Git for Windows portable) was evaluated for v0.12 but is
**deferred to v0.12.1** (or later). The official release ships as a self-
extracting `.7z.exe` archive (Git-<ver>-64-bit.exe). On the Linux/WSL build
pipeline, running a `.exe` self-extractor to unpack the portable tree requires
Wine or a Windows host; neither is available in the standard CI environment
used for `build-usb.sh`. A cross-platform extraction recipe (e.g., bsdtar
over the embedded 7-Zip data stream) is feasible but needs dedicated testing
before it can be considered stable. When PortableGit ships it will carry an
MIT license and will be documented in a new row in this table.

## Composite-license rationale

This is the first boundary in the kit that combines two distinct open-source
licenses in a single side-arm directory:

- **MIT** (ripgrep, fzf, jq, VSCodium) — permissive; no copyleft obligations
  on distribution.
- **LGPL-2.1-or-later** (7-Zip) — weak copyleft; obligations apply when
  modifying 7-Zip itself (see Modifying section below), but NOT when merely
  using `7zzs`/`7zz`/`7za.exe` as a tool in a script or pipeline.

Both license texts are in `licenses/devtools-LICENSES/` (MIT and LGPL-2.1).
The Apache-2.0 license that covers the rest of the Doomstick repo does
**not** extend into `ai-kit/devtools/`. The boundary is the `ai-kit/devtools/`
directory root on the deployed USB.

## Upstream

- **ripgrep 14.1.1:** https://github.com/BurntSushi/ripgrep/releases/tag/14.1.1
  - License: MIT (SPDX: `MIT`)
  - Single-binary static releases for Linux x64, macOS arm64, Windows x64.
    We distribute only unmodified official binary artifacts.

- **fzf 0.61.3:** https://github.com/junegunn/fzf/releases/tag/0.61.3
  - License: MIT (SPDX: `MIT`)
  - Single-binary static releases for Linux x64, macOS arm64, Windows x64.
    We distribute only unmodified official binary artifacts.

- **jq 1.7.1:** https://github.com/jqlang/jq/releases/tag/jq-1.7.1
  - License: MIT (SPDX: `MIT`)
  - Single-binary static releases for Linux x64, macOS arm64, Windows x64.
    We distribute only unmodified official binary artifacts.

- **7-Zip 2409:** https://www.7-zip.org/download.html
  - License: LGPL-2.1-or-later (SPDX: `LGPL-2.1-or-later`)
  - Ships `7zzs` (Linux static), `7zz` (macOS static), and `7za.exe`
    (Windows console). These builds exclude the unrar module — the unrar
    code is proprietary and its absence keeps this an entirely clean LGPL
    boundary. We distribute only unmodified official binary artifacts.
  - Per LGPL-2.1 §6, the corresponding source is available from the
    upstream 7-Zip project at https://www.7-zip.org/sdk.html and
    https://sourceforge.net/projects/sevenzip/. We distribute only
    unmodified binary artifacts; no source modifications have been made.

- **VSCodium 1.99.3:** https://github.com/VSCodium/vscodium/releases/tag/1.99.3
  - License: MIT (SPDX: `MIT`)
  - VSCodium is a community build of VS Code with Microsoft branding and
    telemetry removed. It is licensed MIT, unlike Microsoft's official
    VS Code releases which carry a non-EULA-free license that prohibits
    redistribution in this context. We distribute only unmodified official
    VSCodium binary artifacts.

## Modifying

LGPL-2.1-or-later applies to 7-Zip. MIT applies to ripgrep, fzf, jq, and
VSCodium. The obligations differ:

**For MIT tools (ripgrep, fzf, jq, VSCodium):** If you distribute modified
versions, preserve the copyright notice and permission notice in each file
or in your accompanying documentation. No source publication requirement.

**For LGPL-2.1-or-later tools (7-Zip):** If you modify any LGPL-2.1-or-later
file inside `ai-kit/devtools/{linux,mac,win}/7zzs`, `7zz`, or `7za.exe` and
redistribute the result, you must:

1. Comply with LGPL-2.1 §2 and §3 (preserve copyright and license notices,
   mark your modifications prominently with the date of change, distribute
   any modified work under LGPL-2.1 or later, and provide corresponding
   source or a written offer valid for at least three years).
2. If you combine 7-Zip with proprietary code in a way that goes beyond
   dynamic linking, consult LGPL-2.1 §6 for the applicable requirements
   regarding "Application" vs. "Library" linkage.

Mere use of `7zzs`/`7zz`/`7za.exe` as a subprocess (e.g., calling it from a
shell script) does NOT trigger LGPL redistribution obligations on the calling
code. Only modification and redistribution of 7-Zip itself triggers them.

## Why ship pre-built binaries instead of building from source?

ripgrep requires Rust + cargo. fzf requires Go. jq requires C + oniguruma.
7-Zip requires C++ + NASM. VSCodium requires Node.js + Electron build
toolchain and per-OS signing infrastructure. Asking the kit user to install
all of those just to use Doomstick defeats the "plug in a USB and go"
premise. Vendoring upstream releases is consistent with how llamafile, age,
redbean, and stable-diffusion.cpp ship in the kit.
