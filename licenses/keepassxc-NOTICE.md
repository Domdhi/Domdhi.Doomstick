# licenses/keepassxc-NOTICE.md — third-party attribution & license boundary

Everything in `ai-kit/keepassxc/` is licensed differently from the rest of
the Doomstick repo. The repo as a whole is **Apache-2.0**; the KeePassXC
binaries shipped inside `ai-kit/keepassxc/` are **GPL-2.0-or-later**,
inherited from upstream KeePassXC. The boundary is the `ai-kit/keepassxc/`
directory on the deployed USB.

## What's here

| File / directory | Origin | License |
|-----------------|--------|---------|
| `ai-kit/keepassxc/linux/keepassxc` + `share/` (extracted from `KeePassXC-2.7.12-x86_64.AppImage` at build time on Linux/WSL hosts; the raw `.AppImage` ships when built from a Windows host and is extracted by the launcher on first run) | KeePassXC project — Linux AppImage | GPL-2.0-or-later |
| `ai-kit/keepassxc/mac/KeePassXC-2.7.12-arm64.dmg` (extracted to `KeePassXC.app` by the launcher on first run via `hdiutil`) | KeePassXC project — macOS arm64 application bundle | GPL-2.0-or-later |
| `ai-kit/keepassxc/win/KeePassXC.exe` + DLLs + `keepassxc.ini` (portable mode) | KeePassXC project — Windows x64 portable executable | GPL-2.0-or-later |

All three are pre-built official releases from
https://github.com/keepassxreboot/keepassxc/releases/tag/2.7.12, unmodified.

## Upstream

- **KeePassXC 2.7.12:** https://github.com/keepassxreboot/keepassxc
  - License: GPL-2.0-or-later (SPDX: `GPL-2.0-or-later`)
  - Per GPL-2.0 §3(b), the corresponding source code is available from the
    upstream repository above. KeePassXC publishes its complete source at
    https://github.com/keepassxreboot/keepassxc/releases/tag/2.7.12
    alongside every binary release. We distribute only unmodified official
    binary artifacts; no source modifications have been made.

## Modifying

If you modify any GPL-2.0-or-later file in `ai-kit/keepassxc/` and
redistribute the result, you must:

1. Comply with GPL-2.0 §1 and §2 (preserve license and copyright notices,
   mark your modifications prominently with the date of change, distribute
   any modified work under GPL-2.0 or later).
2. Make the complete corresponding machine-readable source available per
   GPL-2.0 §3 (either accompanying the distribution or via a written offer
   valid for at least three years).

The Apache-2.0 license that covers the rest of the Doomstick repo does
**not** extend into `ai-kit/keepassxc/`. The boundary is the
`ai-kit/keepassxc/` directory root on the deployed USB.

## Why ship pre-built binaries instead of building from source?

KeePassXC requires Qt5/Qt6 + libcrypto + zxcvbn + per-OS desktop
integration. ffmpeg requires libx264 + libx265 + libvpx + libsvtav1 +
libdav1d + libopus + libvorbis + libwebp + libtheora + libmp3lame + libaom
and a complete C/C++ toolchain. Asking the kit user to install all of those
just to use Doomstick defeats the "plug in a USB and go" premise. Vendoring
upstream releases is consistent with how llamafile, age, redbean, and
stable-diffusion.cpp ship in the kit.
