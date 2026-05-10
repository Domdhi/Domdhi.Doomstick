# Recovery Vault — Setup & Usage Guide

> [!WARNING]
> **If you lose your passphrase or identity file, the vault is gone forever.
> There is no recovery mechanism. This is by design.**
>
> `age`'s scrypt KDF uses N=2^18 (262,144 iterations) by default. That
> parameter makes brute-force search infeasible against a strong passphrase —
> if an attacker gets the encrypted blob, guessing costs real compute per
> attempt. The same protection is why there is no "forgot my passphrase" path.
> Write the passphrase down. Store copies in two physical locations. A USB
> drawer and a safe-deposit box is the minimum. A sticky note next to the
> USB is not a backup.

This guide covers the three vault ceremonies, from the default passphrase-only
path through hardware-key and multi-recipient patterns. The kit ships Ceremony 1
out of the box. Ceremonies 2 and 3 require plugins you install on your host —
`age-plugin-yubikey` or `age-plugin-fido2-hmac` — neither is bundled on the USB.

For the quick on-USB reference (offline-accessible, no internet required), see
`vault/README.txt` on the USB itself.

---

## Quick Start

Four steps to encrypt your first vault and verify you can get back in.

**1. Create the recovery directory and add your files:**

```plain
vault/
└── recovery/
    ├── id_ed25519          (SSH private key)
    ├── id_ed25519.pub
    ├── config              (SSH config)
    └── recovery-codes.txt  (2FA backup codes, etc.)
```

**2. Encrypt:**

```bash
# Linux
cd vault/
tar c recovery/ | ../ai-kit/age/linux/age -p > recovery.tar.age
```

```powershell
# Windows
cd vault\
tar.exe -c recovery | & ..\ai-kit\age\win\age.exe -p | Set-Content -Encoding Byte recovery.tar.age
```

`age` prompts for a passphrase twice. A four-word diceware phrase is harder
to crack than a twelve-character random string is to remember.

**3. Verify the round-trip immediately:**

```bash
# Linux / macOS
cd /tmp && mkdir vault-test && cd vault-test
age -d /path/to/USB/vault/recovery.tar.age | tar x
ls -la recovery/
```

```powershell
# Windows
cd $env:TEMP
New-Item -ItemType Directory -Name vault-test | Out-Null
cd vault-test
& D:\ai-kit\age\win\age.exe -d D:\vault\recovery.tar.age | tar.exe -x
dir recovery\
```

If decrypt fails here, fix it now before you delete the plaintext originals.

**4. Store the passphrase:**

Write it on paper. Keep one copy where you live, one copy off-site. Do not
store it in a password manager that's also on the USB — if the USB dies, you
lose both.

---

## Ceremony 1 — Passphrase-only (default)

The default for the kit. One passphrase, one encrypted blob. Recoverable on
any machine that has the kit's `age` binary and your passphrase.

### Encrypt

#### On Linux / macOS

```bash
cd vault/
tar c recovery/ | ../ai-kit/age/linux/age -p > recovery.tar.age
```

Use `mac` in the path instead of `linux` when running on macOS.

#### On Windows

```powershell
cd vault\
tar.exe -c recovery | & ..\ai-kit\age\win\age.exe -p | Set-Content -Encoding Byte recovery.tar.age
```

Windows 10+ ships `tar.exe` (bsdtar). If it's missing, install it via
`winget install GnuWin32.Tar` or encrypt from WSL instead.

### Decrypt

Use the launcher — it resolves the right binary per OS, decrypts to a
host-local tmpdir (not the USB), and prints the cleanup command when done:

- Windows: `start-vault.bat`
- macOS: `start-vault.command`
- Linux: `./start-vault.sh`

Or via raw CLI:

```bash
# Linux / macOS
cd /tmp && mkdir vault-out && cd vault-out
age -d /path/to/USB/vault/recovery.tar.age | tar x
```

```powershell
# Windows
cd $env:TEMP
New-Item -ItemType Directory -Name vault-out | Out-Null
cd vault-out
& D:\ai-kit\age\win\age.exe -d D:\vault\recovery.tar.age | tar.exe -x
```

To update the vault, decrypt to a workdir, edit the `recovery/` contents,
re-encrypt, and wipe the workdir. There is no patch/append mode in `age` —
every update is a full re-encrypt.

---

## Ceremony 2 — Hardware-key (advanced)

> [!NOTE]
> **The kit does NOT bundle `age-plugin-yubikey` or `age-plugin-fido2-hmac`.
> Install one of these plugins on your host before encrypting, or use
> Ceremony 1 instead.**

Hardware-key ceremonies tie decryption to physical hardware. Brute-force is
impossible because the decryption key lives on the device, not in any file or
passphrase.

### Option A — YubiKey via age-plugin-yubikey

Upstream: https://github.com/str4d/age-plugin-yubikey

```bash
# Install
brew install age-plugin-yubikey      # macOS
apt install age-plugin-yubikey       # Debian/Ubuntu
cargo install age-plugin-yubikey     # any OS (requires Rust)

# Generate an identity on the YubiKey
age-plugin-yubikey --generate
# → prints a recipient string: age1yubikey1...
# → prints an identity file path: ~/.config/age/yubikey-identity.txt

# Encrypt
tar c recovery/ | age -r age1yubikey1... > recovery.tar.age

# Decrypt (YubiKey must be plugged in; prompts for touch + PIN)
age -d -i ~/.config/age/yubikey-identity.txt recovery.tar.age | tar x
```

The identity file is a reference to a slot on the YubiKey, not the private
key itself. Losing the identity file: regenerate with `age-plugin-yubikey --list`.
Losing the YubiKey: the vault is gone.

### Option B — Any FIDO2 device via age-plugin-fido2-hmac

Upstream: https://github.com/Mearman/age-plugin-fido2-hmac

```bash
cargo install age-plugin-fido2-hmac
```

Works with YubiKey 5, SoloKey, Nitrokey 3, or any WebAuthn-capable key.
Threat model: protects against passphrase brute-force; does NOT protect
against device theft combined with PIN compromise. Usage pattern is the same
as Option A: generate a recipient, encrypt with `-r`, decrypt with `-i`.

---

## Ceremony 3 — Hardware-key + passphrase fallback (paranoid)

Two independent decryption paths: the YubiKey for daily use, a passphrase key
as a lifeline if the YubiKey is lost. `age` supports multiple recipients on a
single encrypted file — each can independently decrypt.

`age -p` generates a passphrase identity on the fly but can't be combined with
`-r` directly. The solution: pre-derive a key pair, encrypt to its public key.

### Setup

```bash
# Generate a passphrase-protected key pair (saves to a file)
age-keygen -p > ~/.config/age/passphrase-identity.txt

# Extract the public recipient from the file
grep "public key:" ~/.config/age/passphrase-identity.txt
# → # public key: age1abc123...
```

### Encrypt to both recipients

```bash
YUBI_RECIPIENT=$(age-plugin-yubikey --identity)
PASS_RECIPIENT="age1abc123..."   # from grep above

tar c recovery/ | age \
  -r "$YUBI_RECIPIENT" \
  -r "$PASS_RECIPIENT" \
  > recovery.tar.age
```

### Decrypt via either path

```bash
# Via YubiKey (key must be plugged in)
age -d -i ~/.config/age/yubikey-identity.txt recovery.tar.age | tar x

# Via passphrase (prompts for the passphrase that unlocks the identity file)
age -d -i ~/.config/age/passphrase-identity.txt recovery.tar.age | tar x
```

Store `recovery.tar.age` on the USB. Store `passphrase-identity.txt` off the
USB (print it, or put it in a password manager on a different device).
You can lose the YubiKey OR the passphrase identity (but not both) and still
decrypt. The two paths are independent.

---

## Master Key Backup

Write the passphrase on paper. Store copies in two physically separated
locations: one where you live (desk drawer, filing cabinet), one off-site
(safe-deposit box, trusted family member's safe, fire safe at a different
address). For machine-generated passphrases, the phonetic alphabet reduces
transcription errors: "alpha-hotel-charlie-7-delta-foxtrot" is easier to
copy precisely than "ahc7df" under pressure.

Do not store the passphrase, `passphrase-identity.txt`, or any YubiKey
identity reference on the same USB as `recovery.tar.age`. If someone steals
the USB they should get an opaque encrypted blob and nothing that helps them
open it.

**Cloud backup — double-encrypt for sync:**

```bash
# Keep a separate age key pair on your main machine (NOT on the USB)
# Wrap the existing vault blob with it
age -r age1yourcloudkey... vault/recovery.tar.age > recovery.tar.age.cloud.age
```

The cloud sees a doubly-wrapped blob. Cracking it requires your cloud recipient
key AND your vault passphrase. Retrieve to any machine, peel the outer layer
with your cloud key, open the inner vault with your passphrase.

---

## Why decrypt to host tmpdir, not back to USB?

SSH requires private keys to be mode `0600` (`-rw-------`). If the
permissions are broader, `ssh` refuses to use the key:

```plain
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions 0644 for '/path/to/id_ed25519' are too open.
```

USB drives are formatted exFAT for cross-OS portability. exFAT does not store
POSIX permission bits. When a native binary decrypts files onto exFAT, the OS
assigns whatever default mode it feels like — typically `0644` or `0755`.
`chmod 600 id_ed25519` on exFAT silently succeeds but sets nothing. SSH on
next use still sees `0644` and refuses.

Decrypting to `mktemp -d` on the host's native filesystem (`ext4`, `HFS+`,
`NTFS`) means the filesystem honors `chmod`. The launcher does this:

```bash
TMPDIR=$(mktemp -d -t doomstick-vault-XXXXXX)
age -d vault/recovery.tar.age | tar x -C "$TMPDIR"
chmod 600 "$TMPDIR"/recovery/id_ed25519 2>/dev/null
```

When you're done, delete the tmpdir manually. The launcher prints the exact
`rm -rf` command.

---

## Why no auto-cleanup or auto-re-encrypt?

**Auto-cleanup on launcher exit** would destroy your decrypted files if you
close the terminal before you finish copying what you needed. Terminal-close
looks identical to normal exit from inside a shell script. The kit never
auto-deletes anything you didn't explicitly tell it to delete.

**Auto-re-encrypt on cleanup** would encrypt whatever is in the tmpdir with
whatever credentials are available at cleanup time — potentially a different
passphrase or an unexpected identity from `~/.config/age/`. You close the
vault, and later discover the new blob was produced with the wrong key.

The cleanup flow is explicit. The launcher prints it; you run it when ready:

```bash
# Linux / macOS
rm -rf /tmp/doomstick-vault-XXXXXX
```

```powershell
# Windows
Remove-Item -Recurse -Force "$env:TEMP\doomstick-vault-XXXX"
```

No magic. No timers. You see the command, you run it.

---

## Cross-OS path reference

When restoring credentials on a new host, copy from `recovery/` to the
canonical path for your OS:

| Resource | Linux / macOS | Windows |
|---|---|---|
| SSH private keys | `~/.ssh/id_ed25519` | `%USERPROFILE%\.ssh\id_ed25519` |
| SSH public key | `~/.ssh/id_ed25519.pub` | `%USERPROFILE%\.ssh\id_ed25519.pub` |
| SSH config | `~/.ssh/config` | `%USERPROFILE%\.ssh\config` |
| AWS credentials | `~/.aws/credentials` | `%USERPROFILE%\.aws\credentials` |
| AWS config | `~/.aws/config` | `%USERPROFILE%\.aws\config` |
| GitHub CLI auth | `~/.config/gh/hosts.yml` | `%APPDATA%\GitHub CLI\hosts.yml` |
| WireGuard configs | `/etc/wireguard/*.conf` | `C:\Program Files\WireGuard\Data\Configurations\*.conf` |
| GPG keyring | `~/.gnupg/` | `%APPDATA%\gnupg\` |
| 1Password CLI | `~/.config/op/` | `%LOCALAPPDATA%\1Password\op\` |
| age identity files | `~/.config/age/` | `%APPDATA%\age\` |

**Set permissions on Linux / macOS after copying:**

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/config
chmod 600 /etc/wireguard/*.conf   # if restoring WireGuard
```

`ssh`, `gpg`, and `wg-quick` all check permissions before they run. Get these
right on first copy — a "permission denied" error later is almost always this.

**SSH key permissions on Windows:**

Windows `ssh.exe` (OpenSSH) rejects keys readable by accounts other than your
user and `SYSTEM`. Remove inherited permissions after copying:

```powershell
$key = "$env:USERPROFILE\.ssh\id_ed25519"
icacls $key /inheritance:r
icacls $key /grant:r "${env:USERNAME}:R"
icacls $key /remove "NT AUTHORITY\Authenticated Users"
```

---

*`docs/vault-guide.md` — GitHub-readable companion to `vault/README.txt`.
Not deployed to USB. Accessed via GitHub or local clone.*
