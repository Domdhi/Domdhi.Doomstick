# KeePassXC — Setup & Usage Guide

KeePassXC is the Doomstick's bundled password manager. It ships as a
native per-OS binary at `ai-kit/keepassxc/` and stores all entries in a
single encrypted file (`passwords/vault.kdbx`) that travels with the USB
to any host.

For the quick on-USB reference (offline-accessible, no internet required),
see `passwords/README.txt` on the USB itself.

---

## Overview

**What KeePassXC is.** KeePassXC is a desktop password manager that stores
credentials (usernames, passwords, URLs, notes, TOTP codes, file
attachments) in an AES-256 encrypted local file. No cloud account, no sync
service, no subscription. The database file is yours: copy it anywhere,
open it with any compatible KDBX application.

**Why per-OS binaries, not an APE polyglot.** Llamafile, age, and the
Whisperfile runtime are Cosmopolitan APE polyglots — single binaries that
run on Linux, macOS, and Windows without recompilation. KeePassXC is a
Qt-based GUI application with platform-native rendering, menu integration,
and font stack. Cosmopolitan does not support Qt. Each OS ships a separate
binary at `ai-kit/keepassxc/<os>/`.

**Why GPL-2.0+.** KeePassXC is free software released under the GNU General
Public License version 2 or later. The Doomstick kit is Apache-2.0, but the
GPL applies to the KeePassXC binary and does not propagate to the kit's
other components or to your password data. The license boundary is
documented in `ai-kit/keepassxc/NOTICE.md`.

**KDBX 4 format.** vault.kdbx is written in KDBX 4 (KeePass database
format version 4). This is the current standard. It is readable by
KeePassXC 2.x and KeePass 2.x. It is not readable by KeePass 1.x or
third-party tools that support only KDBX 3.1.

---

## First-Use Ceremony

Run these steps once the first time you use KeePassXC from this USB.
Screenshots are not required but the in-app wizard labels match the
descriptions below.

### Step 1 — Launch KeePassXC

Run the launcher from the USB root (not from inside a subdirectory):

| OS      | Launcher                      |
|---------|-------------------------------|
| Windows | `start-passwords.bat`         |
| macOS   | `start-passwords.command`     |
| Linux   | `./start-passwords.sh`        |

The launcher detects your OS, resolves the binary under
`ai-kit/keepassxc/`, and spawns KeePassXC. Because `passwords/vault.kdbx`
does not exist yet, KeePassXC opens its welcome dialog rather than your
database.

### Step 2 — Create a New Database

In KeePassXC, choose **Create new database** (or **File > New Database**).
The creation wizard has three screens:

**General information.** Set a database name (anything you like) and an
optional description. These are metadata only — they do not affect
encryption.

**Encryption settings.** Accept the defaults:
- Algorithm: AES-256-CBC
- Key derivation: Argon2id (memory-hard, resist GPU acceleration)
- Memory: 64 MB, Iterations: 2, Parallelism: 2

These defaults are strong. Changing them is not necessary unless you have
a specific policy reason. The iteration parameters are stored inside the
database so KeePassXC reads them automatically on open.

**Master password.** Choose a master password. Recommendations:
- Four or five random words (diceware) is harder to crack than a
  short complex string and easier to remember.
- Avoid dictionary phrases or song lyrics.
- Avoid passwords you use anywhere else.

KeePassXC uses Argon2id as its key derivation function. Argon2id is
memory-hard and makes brute-force search impractical against a strong
master password. **If you forget your master password, the database is
unrecoverable by design.** There is no "forgot password" path and no
key escrow. Write it down before you close the wizard.

### Step 3 — Save to the Right Location

When KeePassXC asks where to save the file, navigate to the `passwords/`
folder on this USB and name the file `vault.kdbx`.

The launcher expects the database at this exact path: `passwords/vault.kdbx`
relative to the USB root. Saving it elsewhere will work in KeePassXC but
the launcher will not autoload it on subsequent runs — you would need to
use File > Open Database each time.

### Step 4 — Verify the Round-Trip

Close and reopen the database before you rely on it:

1. File > Close Database.
2. Run the launcher again (or File > Open Database and navigate to
   `passwords/vault.kdbx`).
3. Enter your master password.
4. Confirm your entries are visible.

If this fails now, fix it now. A database you cannot open is not a backup.

### Step 5 — Store Your Master Password

Write it on paper. Keep one copy physically separate from the USB:

- One copy at home (desk drawer, filing cabinet).
- One copy off-site (safe-deposit box, trusted location).

Do not store the master password in a digital note on the same USB or on
a machine that shares the USB's attack surface.

---

## Database File Management

### Where vault.kdbx Lives

The kit expects the database at the USB root: `passwords/vault.kdbx`
(e.g., `D:\passwords\vault.kdbx` on Windows, `/mnt/usb/passwords/vault.kdbx`
on Linux). The `passwords/` directory is created by `build-usb.sh` and
`build-usb.ps1`; `vault.kdbx` is created by you during first use.

### Why the USB Root, Not `ai-kit/`

`ai-kit/` holds runtime binaries that are refetched on every `build-usb`
run. Placing `vault.kdbx` outside that tree means build scripts never
accidentally overwrite or delete your database. `passwords/` is a
user-data directory, not a binary cache.

### Moving or Renaming the Database

If you ever rename or move `vault.kdbx`, the launcher will not find it
automatically and will open KeePassXC's open-file dialog instead of
autoloading. Navigate to the file manually, or move it back to
`passwords/vault.kdbx`.

### Opening the Database Without the Launcher

If the launcher fails or you prefer to launch KeePassXC directly:

```
# Windows
ai-kit\keepassxc\win\KeePassXC.exe passwords\vault.kdbx

# macOS (after first-run extraction)
ai-kit/keepassxc/mac/KeePassXC.app/Contents/MacOS/KeePassXC passwords/vault.kdbx

# Linux (after first-run extraction)
ai-kit/keepassxc/linux/keepassxc passwords/vault.kdbx
```

### KDBX Compatibility

`vault.kdbx` is readable by:
- KeePassXC 2.6+
- KeePass 2.51+ (Windows, Mono)
- Strongbox (iOS), KeePassium (iOS), KeePassDX (Android)

It is not readable by KeePass 1.x.

---

## Pairing with the v0.9 Age Vault

The kit also ships an `age`-based recovery vault at `vault/`. That vault
is designed for credentials that cannot be typed into a GUI (SSH private
keys, 2FA seeds, recovery codes). KeePassXC's `vault.kdbx` and the age
vault serve different purposes but complement each other.

**Recommended workflow for "lost USB" recovery:**

Include `vault.kdbx` inside the age recovery archive so you have a single
encrypted blob containing all your credentials. If the USB is lost or
destroyed, decrypt the age blob on any machine, recover `vault.kdbx`, and
open it with KeePassXC.

**Step-by-step:**

1. Close KeePassXC and lock the database (File > Lock Database or Ctrl+L)
   before copying, so the file is not mid-write.

2. Copy `vault.kdbx` into the age recovery staging area:

   ```bash
   # Linux / macOS (run from USB root)
   cp passwords/vault.kdbx vault/recovery/
   ```

   ```powershell
   # Windows (run from USB root)
   Copy-Item passwords\vault.kdbx vault\recovery\
   ```

3. Add any other credentials to `vault/recovery/` (SSH keys, TOTP seeds,
   etc.) per the instructions in `vault/README.txt`.

4. Encrypt the entire `recovery/` directory with `age`:

   ```bash
   # Linux (run from vault/ directory)
   tar c recovery/ | ../ai-kit/age/linux/age -p > recovery.tar.age
   ```

   ```powershell
   # Windows (run from vault\ directory)
   tar.exe -c recovery | & ..\ai-kit\age\win\age.exe -p |
     Set-Content -Encoding Byte recovery.tar.age
   ```

5. Verify the archive is non-zero before deleting the plaintext:

   ```bash
   ls -lh vault/recovery.tar.age     # Linux / macOS
   dir vault\recovery.tar.age         # Windows
   ```

6. Delete the plaintext staging directory:

   ```bash
   rm -rf vault/recovery/             # Linux / macOS
   Remove-Item -Recurse -Force vault\recovery\  # Windows
   ```

For the full age ceremony — including hardware-key variants and cloud
backup patterns — see `docs/vault-guide.md` (repo) or `vault/README.txt`
(on-USB quick reference).

**Important:** `vault.kdbx` is already encrypted with your KeePassXC
master password. The age envelope is a second layer of encryption for
the "USB is physically lost" scenario. Both layers are independent;
cracking one does not give access to the other.

---

## Per-OS Quirks

### Windows — Portable Mode

KeePassXC on Windows reads settings from `keepassxc.ini` in the same
directory as `KeePassXC.exe` (`ai-kit\keepassxc\win\keepassxc.ini`). This
is KeePassXC's portable mode: settings travel with the USB and do not
touch the host's registry or `%APPDATA%`.

Consequences:
- The recent-files list is stored in `keepassxc.ini`. On a fresh host,
  the launcher bypasses this by passing `passwords\vault.kdbx` as an
  argument, so the recent-files state does not matter for normal use.
- If you configure browser integration, the pairing state is stored in
  the host's native browser profile, not in `keepassxc.ini`. Re-pair on
  each new host.

### macOS — Quarantine and First-Run Extraction

macOS Gatekeeper quarantines applications downloaded from the internet.
The `start-passwords.command` launcher clears the quarantine flag
automatically on first run using `xattr -dr com.apple.quarantine`.

On the first launch, if `ai-kit/keepassxc/mac/KeePassXC.app` does not yet
exist, the launcher mounts `ai-kit/keepassxc/mac/KeePassXC-2.7.12-arm64.dmg`
via `hdiutil`, copies `KeePassXC.app` out of the mounted volume, clears
the quarantine attribute, and ejects the disk image. Subsequent launches
skip this step and open the already-extracted `.app` directly.

If macOS shows "KeePassXC cannot be opened because the developer cannot be
verified" despite the quarantine clear, open **System Settings > Privacy &
Security** and click **Open Anyway** next to the KeePassXC entry. This is
a one-time approval per host.

Settings on macOS are written to `~/Library/Preferences/KeePassXC/` on the
host — not on the USB. They are per-host and will be empty on a new Mac.

### Linux — AppImage and FUSE

KeePassXC ships to Linux as an AppImage. AppImages normally require FUSE
(Filesystem in Userspace) to mount and run themselves. Some environments
(WSL, locked-down containers, certain cloud VMs) do not have FUSE
available.

The `start-passwords.sh` launcher handles this with a first-run extraction
fallback:

1. If `ai-kit/keepassxc/linux/keepassxc` exists (a plain binary, present
   after extraction or on USB sticks built on Linux/WSL), the launcher uses
   it directly. No FUSE needed.

2. If only the raw AppImage is present (USB built on Windows), the launcher
   runs `chmod +x KeePassXC*.AppImage && ./KeePassXC*.AppImage
   --appimage-extract` to extract the squashfs contents to a local
   directory, moves the binary to `ai-kit/keepassxc/linux/keepassxc`, and
   removes the AppImage. All subsequent launches use the extracted binary.

If the launcher fails with "FUSE not available" before extraction completes,
run the extraction manually:

```bash
cd /path/to/usb/ai-kit/keepassxc/linux
chmod +x KeePassXC-*.AppImage
./KeePassXC-*.AppImage --appimage-extract
mv squashfs-root/usr/bin/keepassxc .
mv squashfs-root/usr/share ./share   # optional: icons, translations
rm -rf squashfs-root KeePassXC-*.AppImage
```

Then re-run `./start-passwords.sh` from the USB root.

Settings on Linux are written to `~/.config/KeePassXC/` on the host — not
on the USB. They are per-host and will be empty on a new machine.

---

## Troubleshooting

### Binary not found — launcher exits with "ai-kit/keepassxc/... not found"

The build scripts fetch KeePassXC at build time. If `build-usb.sh` or
`build-usb.ps1` has not been run against this USB (or was interrupted),
the binary is absent.

Fix: run `build-usb.sh /path/to/usb` (Linux/macOS) or `build-usb.ps1 D:\`
(Windows) against the USB root. The build script fetches the correct
binary for each OS.

### Wrong OS binary picked

The launcher detects the OS via `uname -s` (Linux/macOS) or environment
variables (Windows). If the wrong binary runs, the most likely cause is
running `start-passwords.sh` under a cross-OS emulation layer (e.g.,
MSYS2 or Cygwin on Windows) that reports a non-Windows `uname`. In that
case, invoke `ai-kit\keepassxc\win\KeePassXC.exe` directly from a native
Windows terminal.

### Database opens but shows "The database was opened in read-only mode"

This happens when `passwords/vault.kdbx` is on a filesystem that reports
the file as read-only. Common cause: the USB is mounted read-only, or
the exFAT driver has not granted write access.

Fix on Linux: remount the USB with write access:
```bash
sudo mount -o remount,rw /mnt/usb
```

Fix on macOS: verify the USB is not physically write-protected (some
drives have a hardware lock switch).

### Database file is corrupt — KeePassXC shows a parse error on open

A corrupt `.kdbx` file is not recoverable unless you have a backup.
KeePassXC's backup option (Database > Database Settings > Backup) can
keep a rolling copy; enable it and point it at a host-local directory
(not the USB) so the backup survives USB failure.

If you followed the age vault pairing steps above and have
`vault/recovery.tar.age`, decrypt it to recover the copy of `vault.kdbx`
that was archived at that point. Entries added after the last archive
snapshot will be lost.

### "I forgot my master password"

Unrecoverable. KeePassXC's Argon2id KDF is designed so that even the
application cannot derive the key without the correct passphrase. There is
no key escrow, no recovery email, and no way to reset. If you have a copy
of `vault.kdbx` from a time when you knew the password, that copy is also
unrecoverable without the password.

Prevention is the only remedy: write the master password on paper and keep
it in two physical locations, as described in the first-use ceremony above.

### Launcher opens KeePassXC but does not autoload vault.kdbx

The launcher passes `passwords/vault.kdbx` as an argument only if the file
exists. If the file is absent (first use, or if you moved it), KeePassXC
opens its welcome screen. Navigate to File > Open Database and locate
`passwords/vault.kdbx` manually.

If the file exists but the launcher still does not autoload it, verify:
1. The file is named exactly `vault.kdbx` (lowercase, no spaces).
2. The file is directly inside `passwords/` at the USB root, not in a
   subdirectory.
3. The launcher is run from the USB root (not from inside `passwords/`).

---

*`docs/keepassxc-guide.md` — GitHub-readable companion to `passwords/README.txt`.
Not deployed to USB. Accessed via GitHub or local clone.*
