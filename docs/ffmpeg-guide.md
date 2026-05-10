# ffmpeg — Setup & Usage Guide

The kit ships ffmpeg n7.1 as a full-featured offline video and audio toolkit.
No installation required: the launcher adds the bundled binary to your PATH for
the session, then drops you into an interactive shell where `ffmpeg` and
`ffprobe` just work.

The ffmpeg side-arm pairs naturally with two other kit tools: **whisperfile**
(port 8766) transcribes audio that ffmpeg can extract or convert, and **sd-img**
(`start-img.*`) generates PNG sequences that ffmpeg can stitch into video.
See [`docs/img-guide.md`](img-guide.md) for the sd-img workflow and
[`docs/keepassxc-guide.md`](keepassxc-guide.md) for the sister side-arm
shipping alongside ffmpeg in v0.11. v0.11 entry in the roadmap:
[`docs/auxiliary-roadmap.md`](auxiliary-roadmap.md).

---

## Overview

**What ffmpeg is.** ffmpeg is the de-facto open-source media processing tool.
It decodes, encodes, demuxes, muxes, filters, and probes nearly every audio
and video format in practical use. The companion `ffprobe` tool reads metadata
from media files without processing them.

**Why GPL-3.0+.** The kit's cross-OS axiom (same binaries work on Linux, macOS,
and Windows) requires pre-built static ffmpeg builds that include H.264 and
H.265 encoding. No LGPL-licensed static ffmpeg for macOS Apple Silicon exists:
Martin-Riedl's macOS arm64 builds are GPL-3.0+. Adopting a single GPL-3.0+
boundary for the entire ffmpeg side-arm — the same pattern as `doom/`'s
GPL-2.0 boundary — keeps the license matrix simple across all three OSes.

The ffmpeg license file lives at `ai-kit/ffmpeg/LICENSE` on the USB.

**What the BtbN GPL variant includes.** The Linux and Windows builds come from
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (`gpl-shared`
variant, n7.1 branch). The macOS arm64 build comes from
[Martin-Riedl](https://github.com/Martin-Riedl/FFmpeg-Encode-Installer)
(GPL-3.0+ snapshot `1777624525_N-124279-g0f6ba39122`). All three include:

| Codec | Encode | Decode |
|---|:---:|:---:|
| H.264 (libx264) | yes | yes |
| H.265 / HEVC (libx265) | yes | yes |
| VP9 (libvpx) | yes | yes |
| AV1 encode (libsvtav1) | yes | — |
| AV1 decode (libdav1d) | — | yes |
| Opus audio (libopus) | yes | yes |
| Vorbis audio (libvorbis) | yes | yes |
| WebP / animated WebP (libwebp) | yes | yes |
| Theora video (libtheora) | yes | yes |
| MP3 audio (libmp3lame) | yes | yes |
| AOM AV1 (libaom) | yes | yes |

Run `ffmpeg -codecs` inside the session for the full list.

---

## Launcher behavior

The launcher (`start-ffmpeg.{sh,command,bat}` at the USB root) uses the
**PATH-primer shell pattern**: it prepends the bundled ffmpeg directory to your
PATH, then hands control to an interactive shell. It does **not** expose a
server port and leaves no background process running after you exit.

### On Linux / macOS

```bash
# Finder double-click (macOS), or:
open start-ffmpeg.command

# Terminal (Linux or macOS):
./start-ffmpeg.sh
```

What happens inside:
1. The script resolves `$ROOT/ai-kit/ffmpeg/linux/` (or `mac/`) and runs
   `export PATH="$FFMPEG_DIR:$PATH"`.
2. It prints the session banner and a few quick-reference examples.
3. It calls `exec "${SHELL:-/bin/bash}"` — replacing itself with your login
   shell. The exported PATH carries into that shell.
4. You now have a normal interactive terminal where `ffmpeg` and `ffprobe`
   resolve to the USB's copies.

**To exit:** type `exit` or press `Ctrl-D`. Because the launcher used `exec`,
closing the shell closes the terminal window (or returns to wherever you
launched from). The PATH change is gone — it lived only in the child process
tree and is not written to your `~/.bashrc` or `~/.zshrc`.

### On Windows

```powershell
# Explorer double-click, or:
.\start-ffmpeg.bat
```

What happens inside:
1. The script sets `PATH=%FFMPEG_DIR%;%PATH%` in a `cmd /k` environment.
2. `cmd /k` keeps the window open after the script body finishes, preserving
   the PATH change for the session.
3. You now have a standard `cmd.exe` window where `ffmpeg` and `ffprobe`
   resolve to the USB's copies.

**To exit:** type `exit` and press Enter, or close the window with the X
button. The PATH is not written to the system registry or the user environment;
it lives only in this `cmd /k` instance.

**PATH persistence note.** On Windows the expanded PATH persists through the
`cmd /k` session even if the script ends, but does NOT persist after the
window is closed. This is a deliberate feature: no cleanup needed, no
permanent modification to the host.

---

## Common workflows

### Quick-reference table

| Task | Command |
|---|---|
| Extract audio from video | `ffmpeg -i input.mp4 output.wav` |
| Resample for whisperfile | `ffmpeg -i input.wav -ar 16000 -ac 1 out.wav` |
| Trim a video clip (stream copy) | `ffmpeg -i input.mp4 -ss 00:00:30 -to 00:01:00 -c copy out.mp4` |
| PNG sequence to MP4 | `ffmpeg -framerate 4 -i frame_%04d.png -c:v libx264 -pix_fmt yuv420p out.mp4` |
| PNG sequence to animated WebP | `ffmpeg -framerate 4 -i frame_%04d.png -c:v libwebp -lossless 0 -compression_level 6 -loop 0 out.webp` |
| Probe file metadata | `ffprobe input.mp4` |

---

### Audio extraction from video

```bash
ffmpeg -i input.mp4 output.wav
```

Extracts the first audio stream from `input.mp4` and writes it as a PCM WAV
file. ffmpeg infers the output format from the `.wav` extension. If the video
has multiple audio streams, add `-map 0:a:1` (zero-indexed) to pick a specific
one.

---

### Audio resample for whisperfile input

Whisperfile (the kit's offline speech-to-text, port 8766) expects **16 kHz
mono WAV**. Most recordings come in at 44.1 kHz or 48 kHz stereo. This single
command resamples and downmixes:

```bash
ffmpeg -i input.wav -ar 16000 -ac 1 out.wav
```

- `-ar 16000` — set the output sample rate to 16,000 Hz.
- `-ac 1` — mix down to one channel (mono).

Works equally well on `.mp3`, `.m4a`, `.ogg`, or any format the kit's ffmpeg
can decode:

```bash
ffmpeg -i recording.m4a -ar 16000 -ac 1 whisper-ready.wav
```

After conversion, open `http://localhost:8766` in your browser (whisperfile
must be running via `start-whisper.*`) and upload `whisper-ready.wav`.

---

### Video trim (stream copy, no re-encode)

```bash
ffmpeg -i input.mp4 -ss 00:00:30 -to 00:01:00 -c copy out.mp4
```

Copies the video and audio streams byte-for-byte between the 30-second and
60-second marks — no re-encode, so it is nearly instant. `-c copy` is the
key flag.

**Note on keyframe alignment.** Stream copy trims to the nearest keyframe on
the left of `ss`. For clips that need frame-accurate start points, move `-ss`
before `-i` (seek before decoding) and drop `-c copy` to force a re-encode:

```bash
ffmpeg -ss 00:00:30 -to 00:01:00 -i input.mp4 -c:v libx264 -c:a copy out.mp4
```

This is slower but begins the output clip on the exact requested frame.

---

### PNG sequence to MP4 (for sd-img output)

sd-img saves each image as an individual PNG. If you run the image generator
repeatedly with a consistent subject, ffmpeg can stitch the PNGs into a video.
By convention sd-img names outputs `img-out-YYYYMMDD-HHMMSS.png`; rename them
or symlink them to `frame_0001.png`, `frame_0002.png`, etc. first.

```bash
ffmpeg -framerate 4 -i frame_%04d.png -c:v libx264 -pix_fmt yuv420p out.mp4
```

- `-framerate 4` — 4 frames per second (each image shown for 250 ms). Adjust
  to taste.
- `-i frame_%04d.png` — `%04d` matches four-digit zero-padded numbers:
  `frame_0001.png`, `frame_0002.png`, and so on.
- `-c:v libx264` — H.264 video, broadly compatible with all players and
  browsers.
- `-pix_fmt yuv420p` — required for H.264 files that will play in QuickTime
  and most mobile players. Without it, some decoders refuse the file.

---

### Animated WebP from PNG sequence

```bash
ffmpeg -framerate 4 -i frame_%04d.png -c:v libwebp -lossless 0 -compression_level 6 -loop 0 out.webp
```

- `-c:v libwebp` — animated WebP output (modern browsers, Discord, Slack).
- `-lossless 0` — lossy mode; produces much smaller files than lossless at
  acceptable quality for generated images.
- `-compression_level 6` — encoder effort (0 = fastest/largest, 6 = slower/
  smaller). 6 is a reasonable middle ground; go up to 9 for maximum
  compression.
- `-loop 0` — loop forever. Use `-loop 1` for play-once.

Animated WebP files often play in contexts where animated GIF would work but
at a fraction of the file size. The BtbN GPL build includes `libwebp` so this
works on all three OSes.

---

## Per-OS notes

### Linux — x64 vs arm64

The kit ships the architecture that matches the build host (`x64` by default).
If you built the USB on an arm64 Linux machine, the Linux ffmpeg binary will
be arm64. If you're building for an arm64 USB that will run on arm64 Linux
(e.g., Raspberry Pi 5), set the build environment variable before running the
wizard:

```bash
DOOM_FFMPEG_LINUX_ARCH=arm64 ./build-usb.sh /mnt/usb
```

An x64 ffmpeg binary will not run on arm64 Linux and will error with
`Exec format error`. Check your architecture with `uname -m`: `x86_64` is
x64, `aarch64` is arm64.

### macOS — quarantine clearance

The macOS build comes from Martin-Riedl's GPL-3.0+ release (Apple Silicon /
arm64). It is unsigned (no Apple Developer ID signature). On first run, macOS
Gatekeeper quarantines the binary and shows "cannot be opened because the
developer cannot be verified."

Clear quarantine once with:

```bash
xattr -dr com.apple.quarantine ai-kit/ffmpeg/mac/ffmpeg
xattr -dr com.apple.quarantine ai-kit/ffmpeg/mac/ffprobe
```

Run this from the USB root (the path `ai-kit/ffmpeg/mac/...` is relative to
wherever the USB is mounted). After clearing, the launcher works normally on
subsequent runs — quarantine attributes do not re-apply.

Alternatively, in **System Settings > Privacy & Security**, scroll to the
bottom of the Security section and click "Open Anyway" after the first blocked
launch attempt. This achieves the same result for that one binary only and
must be repeated for `ffprobe` separately.

### Windows — PATH persistence through cmd /k

The `start-ffmpeg.bat` launcher uses `cmd /k` to keep the window open. Unlike
`setlocal`/`endlocal` which confine changes to a script's scope, `cmd /k`
inherits the environment of the calling process and keeps it alive for manual
use after the script body finishes running. This is why `ffmpeg` stays
accessible for the lifetime of the window.

Closing the window (X button) or typing `exit` terminates the `cmd /k`
instance and the PATH change with it. No permanent modification is made to
the system PATH or `HKCU\Environment`.

If you want to use ffmpeg from an existing `cmd.exe` window (not the launcher),
set PATH manually for that session:

```bat
set "PATH=D:\ai-kit\ffmpeg\win;%PATH%"
ffmpeg -i input.mp4 output.wav
```

Replace `D:\` with your USB drive letter.

---

## Troubleshooting

**"ffmpeg: command not found" inside the launcher session.**
The launcher's `exec` call on Unix hands off to `$SHELL`. If your shell does
not inherit the exported PATH (rare, but possible with exotic shell configs),
run ffmpeg by full path instead:

```bash
# Linux
/path/to/usb/ai-kit/ffmpeg/linux/ffmpeg -i input.mp4 output.wav

# macOS
/Volumes/USBDRIVE/ai-kit/ffmpeg/mac/ffmpeg -i input.mp4 output.wav
```

**DLL errors on Windows ("The code execution cannot proceed").**
The kit ships the BtbN `gpl-shared` build, which links against bundled DLLs
that live in `ai-kit/ffmpeg/win/`. The launcher sets PATH to that directory,
making Windows resolve the DLLs from there automatically. DLL-not-found errors
mean PATH was not set correctly — use the launcher (`start-ffmpeg.bat`) rather
than calling `ffmpeg.exe` directly from a window where PATH hasn't been primed.

**"Encoder ... not found" or "Unknown encoder".**
The BtbN GPL variant includes H.264, H.265, VP9, AV1, Opus, MP3, WebP,
Vorbis, and Theora. If you're trying a codec outside that list, the kit's
ffmpeg will not have it. Run `ffmpeg -codecs` inside the session for a full
list of what is available. If you need a missing codec, you will need a
separately installed system ffmpeg — the kit's bundled copy is not a
replacement for a full system install.

**"Codec not found" / "Invalid encoder name" for libx265.**
Encoding with H.265 is slower than H.264 on CPU. If encoding speed matters
more than output size, swap `libx265` for `libx264`:

```bash
# Instead of:
ffmpeg -i input.mp4 -c:v libx265 out.mp4

# Use:
ffmpeg -i input.mp4 -c:v libx264 -pix_fmt yuv420p out.mp4
```

H.264 output is also more broadly compatible with older players and mobile
devices.

**Stream copy fails or produces unplayable output.**
`-c copy` skips re-encoding, which means ffmpeg cannot fix container/codec
mismatches. If the input is in a format the target container doesn't support
(e.g., copying AV1 into an MP4 container with a decoder that doesn't support
it), drop `-c copy` and specify an explicit encoder:

```bash
ffmpeg -i input.mkv -c:v libx264 -c:a libopus out.mp4
```

**License boundary if redistributing modified outputs.**
ffmpeg's GPL-3.0+ license applies to the ffmpeg tool itself, not to media
files that ffmpeg processes. If you use the kit's ffmpeg to convert your own
recordings, the output files (WAV, MP4, WebP, etc.) are yours under whatever
license you choose — the tool's license does not contaminate the processed
media.

If you **redistribute the ffmpeg binaries themselves** (or a modified build),
GPL-3.0 section 6 requires you to provide or offer the Corresponding Source.
The BtbN source is at
[github.com/BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds);
the Martin-Riedl macOS source is at
[github.com/Martin-Riedl/FFmpeg-Encode-Installer](https://github.com/Martin-Riedl/FFmpeg-Encode-Installer).
For personal offline use, no redistribution is involved and section 6 does
not apply.

---

*`docs/ffmpeg-guide.md` — GitHub-readable companion. Not deployed to USB. Accessed via GitHub or local clone.*
