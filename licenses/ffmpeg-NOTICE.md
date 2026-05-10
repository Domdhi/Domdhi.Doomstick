# licenses/ffmpeg-NOTICE.md — third-party attribution & license boundary

Everything in `ai-kit/ffmpeg/` is licensed differently from the rest of
the Doomstick repo. The repo as a whole is **Apache-2.0**; the ffmpeg
binaries shipped inside `ai-kit/ffmpeg/` are **GPL-3.0-or-later**, because
they are built with `--enable-gpl --enable-version3` which combines GPL-2.0+
components (libx264, libx265, etc.) with LGPL-2.1+ ffmpeg core to produce a
combined work licensed under GPL-3.0+. The boundary is the `ai-kit/ffmpeg/`
directory on the deployed USB.

## What's here

| File / directory | Source | Archive fetched | License |
|-----------------|--------|-----------------|---------|
| `ai-kit/ffmpeg/linux/ffmpeg` + `ffprobe` | BtbN/FFmpeg-Builds — Linux GPL build (host arch only — x64 by default, arm64 via `DOOM_FFMPEG_LINUX_ARCH=arm64`) | `ffmpeg-n7.1-latest-linux64-gpl-7.1.tar.xz` (or `-linuxarm64-gpl-7.1.tar.xz`) | GPL-3.0-or-later |
| `ai-kit/ffmpeg/mac/ffmpeg` + `ffprobe` | Martin-Riedl macOS builds — arm64 GPL build (snapshot `1777624525_N-124279-g0f6ba39122`, captured 2026-05-10) | `ffmpeg.zip` from https://ffmpeg.martin-riedl.de/download/macos/arm64/1777624525_N-124279-g0f6ba39122/ffmpeg.zip | GPL-3.0-or-later |
| `ai-kit/ffmpeg/win/ffmpeg.exe` + `ffprobe.exe` | BtbN/FFmpeg-Builds — Windows x64 GPL build | `ffmpeg-n7.1-latest-win64-gpl-7.1.zip` | GPL-3.0-or-later |

All binaries are unmodified official releases from their respective upstreams,
pinned at the n7.1 stable branch. The Linux directory ships the host-arch
binaries only (one architecture per USB, not both).

## Upstream

- **BtbN/FFmpeg-Builds** (Linux x64, Linux arm64, Windows x64):
  https://github.com/BtbN/FFmpeg-Builds
  - Provides automated GPL-variant builds of ffmpeg from the n7.1 stable
    branch. Built with `--enable-gpl --enable-version3`; the combined work
    is GPL-3.0-or-later.
  - Per GPL-3.0 §6, corresponding source is available from the upstream
    ffmpeg project at https://ffmpeg.org/download.html (n7.1 branch) and
    from BtbN's build scripts at https://github.com/BtbN/FFmpeg-Builds.
    We distribute only unmodified binary artifacts.

- **Martin-Riedl ffmpeg macOS builds** (macOS arm64):
  https://ffmpeg.martin-riedl.de/
  - Provides GPL-variant static builds for macOS arm64. Snapshot
    `1777624525_N-124279-g0f6ba39122` captured 2026-05-10.
  - Per GPL-3.0 §6, corresponding source is available from the upstream
    ffmpeg project at https://ffmpeg.org/download.html (n7.1 branch).
    We distribute only unmodified binary artifacts.

## Modifying

If you modify any GPL-3.0-or-later file in `ai-kit/ffmpeg/` and redistribute
the result, you must:

1. Comply with GPL-3.0 §4 and §5 (preserve license and copyright notices,
   mark your modifications with date, distribute any modified work under
   GPL-3.0 or later).
2. Make the complete corresponding source available per GPL-3.0 §6 (either
   accompanying the distribution, providing a written network source offer,
   or relying on a peer-to-peer distribution that informs recipients where
   the source is available).

The Apache-2.0 license that covers the rest of the Doomstick repo does
**not** extend into `ai-kit/ffmpeg/`. The boundary is the `ai-kit/ffmpeg/`
directory root on the deployed USB.

## Why ship pre-built binaries instead of building from source?

ffmpeg requires libx264 + libx265 + libvpx + libsvtav1 + libdav1d + libopus +
libvorbis + libwebp + libtheora + libmp3lame + libaom and a complete C/C++
toolchain plus per-OS build environments (e.g., yasm/nasm assemblers, kernel
headers, macOS SDK). Asking the kit user to install all of those just to use
Doomstick defeats the "plug in a USB and go" premise. Vendoring upstream
releases is consistent with how llamafile, age, redbean, and stable-
diffusion.cpp ship in the kit.
