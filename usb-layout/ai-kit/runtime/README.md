# ai-kit/runtime/ — llamafile binary lives here

After running `build-usb.sh` you'll have:

| File | Size | Source |
|------|------|--------|
| `llamafile`     | 43 MB | [Mozilla-Ocho/llamafile 0.10.1](https://github.com/Mozilla-Ocho/llamafile/releases/tag/0.10.1) (`llamafile-0.10.1-thin`) |
| `llamafile.exe` | 43 MB | byte-identical copy of `llamafile`, renamed so Windows double-click works |

The binary is a [Cosmopolitan APE](https://github.com/jart/cosmopolitan)
polyglot: simultaneously a valid Windows PE, Linux ELF, macOS Mach-O, and
POSIX shell script. The same bytes run on all three OSes.

## Why two copies?

Windows refuses to launch a file via Explorer double-click unless it ends
in `.exe`. Linux/macOS look at the executable bit, not the extension.
We could symlink, but exFAT (the only filesystem all three OSes can read
+ write) doesn't support symlinks reliably. Two physical copies, 43 MB each
— a rounding error against the 22 GB of model weights.

## Why not commit the binary?

We could (it's only 43 MB, well under GitHub's 100 MB per-file limit) but:

- It would diverge from upstream when llamafile cuts a new release.
- Vendoring third-party binaries in a repo is a maintenance smell.
- The build script downloads it in a few seconds; that's fine.

If you want a fully air-gapped build flow, keep a local mirror of the
llamafile release tarball and edit `build-usb.{sh,ps1}` to point at it.
