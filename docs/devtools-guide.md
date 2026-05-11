# Dev Tools — Setup & Usage Guide

The kit ships a portable developer tools bundle in v0.12: ripgrep, fzf, jq,
7-Zip, and VSCodium. The launcher primes PATH so all tools resolve in one
interactive shell session — no installation, no network access required.

---

## Overview

| Tool | Version | License | Role |
|---|---|---|---|
| ripgrep (`rg`) | 14.1.1 | MIT | Fast recursive search |
| fzf | 0.61.3 | MIT | Interactive fuzzy finder |
| jq | 1.7.1 | MIT | JSON query and transform |
| 7-Zip | 2409 | LGPL-2.1 | Archive create/extract/list |
| VSCodium | 1.99.3 | MIT | Open-source code editor |

License files live at `ai-kit/devtools/LICENSE-*` on the USB.

**What is deferred.** PortableGit is planned for v0.12.1 — not in v0.12.
**Fully offline.** All five tools run without network access. VSCodium's Open
VSX marketplace requires a connection for new installs; the editor itself does
not.

---

## Launching

| OS | Launcher |
|---|---|
| Windows | `start-devtools.bat` (double-click or run in cmd) |
| macOS | `start-devtools.command` (double-click from Finder) |
| Linux | `./start-devtools.sh` (in a terminal) |

All launchers are at the USB root. See dashboard section 11 for launch instructions.

**What happens.** The launcher prepends the OS-appropriate
`ai-kit/devtools/{linux,mac,win}/` directory to PATH, prints a tool reference
banner, then opens an interactive shell (`exec $SHELL` on Unix; `cmd /k` on
Windows). On macOS the `codium` symlink is created automatically on first run.

**Sentinel check.** If `ai-kit/devtools/` is absent the launcher prints
`devtools bundle not found — re-run build-usb.sh with devtools enabled` and
exits without opening a shell.

**To exit.** Type `exit` or press `Ctrl-D`. PATH is not modified permanently.

---

## ripgrep (`rg`)

Recursive search; respects `.gitignore` and skips binary files by default.

```bash
# Recursive search in current directory
rg 'pattern' .

# Case-insensitive search in a directory
rg -i 'error' logs/

# Search only Markdown files
rg --type md 'TODO' field-manual/

# List filenames containing the pattern (not matched lines)
rg -l 'function' src/

# Preview substitutions without modifying files
rg -o --passthru -r 'new_name' 'old_name' src/
```

`--type-list` shows built-in type names. `-r` outputs substituted text to
stdout only — no file is modified.

---

## fzf

Reads lines from stdin, filters as you type, prints the selection to stdout.

```bash
# Find files interactively (reads from find by default)
fzf

# Pipe from ripgrep (respects .gitignore) and open selection in VSCodium
rg --files | fzf | xargs codium

# Recent shell history search (newest first)
history | fzf --tac --no-sort
```

Pass `--history <file>` to persist fzf's own search history across sessions.

---

## jq

JSON query and transform. Reads from stdin or a file; outputs to stdout.

```bash
# Extract a field
echo '{"name": "dom"}' | jq '.name'

# Iterate an array
echo '[1,2,3]' | jq '.[]'

# Filter array elements by condition
cat data.json | jq '.items[] | select(.active == true)'

# Raw output (no surrounding quotes) — useful for piping
jq -r '.name' data.json

# Reshape: keep only specific fields
jq '{name: .name, id: .id}' data.json
```

Chain filters with `|`. Use `-r` when the result feeds a command that does not
expect JSON-quoted strings.

---

## 7-Zip

Archive tool. Binary name differs per OS (upstream naming inconsistency):

| OS | Binary |
|---|---|
| Linux | `7zzs` |
| macOS | `7zz` (no trailing `s`) |
| Windows | `7za` |

LGPL-2.1, no unrar code (existing `.rar` extraction works; creation does not).

```bash
# Extract (Linux example — swap binary name for macOS/Windows)
7zzs x archive.7z

# Create
7zzs a archive.7z files/

# List contents without extracting
7zzs l archive.7z
```

Format is inferred from the file extension (`.7z`, `.zip`, `.tar`, etc.).
`x` preserves directory structure; `e` flattens.

---

## VSCodium

Open-source VS Code build: MIT license, no Microsoft telemetry, Open VSX
extension registry instead of the Microsoft Marketplace.

Microsoft VS Code is not shipped — its binary license creates redistribution
ambiguity for offline USB kits. VSCodium's MIT license does not.

**Open a directory or file.**

```bash
codium .
codium field-manual/index.md
```

**Portable mode.** VSCodium's data directory lives at
`ai-kit/devtools/<os>/vscode/data/` on the USB. Settings and extensions travel
with the stick, not the host's `~/.config/VSCodium/` or `%APPDATA%\VSCodium\`.

**Extensions.** Use the Extensions panel (`Ctrl-Shift-X`) and search Open VSX.
If an extension is only on the Microsoft Marketplace, download the `.vsix`
manually and install via `Extensions > ... > Install from VSIX`.

---

*`docs/devtools-guide.md` — GitHub-readable companion. Not deployed to USB.*
