RECOVERY VAULT
==============

========================================================================
CRITICAL: IF YOU LOSE YOUR PASSPHRASE OR IDENTITY FILE, THIS VAULT IS
GONE FOREVER. THERE IS NO RECOVERY MECHANISM. THIS IS BY DESIGN.
========================================================================

age encrypts with scrypt (default N=2^18). That work factor makes
brute-force infeasible against a strong passphrase -- the same property
that protects you also means there is no back door, no key escrow, and
no one to call. Write your passphrase down before you encrypt anything.

Back up your passphrase now:
  Paper copy, two physical locations. Two is one, one is none.
  If using an identity file instead of a passphrase, keep the identity
  file on a SEPARATE drive -- never on this USB.


-------------------------------------------------------------------------
WHAT'S HERE
-------------------------------------------------------------------------

  vault/README.txt           This file. Read it before encrypting.

  vault/recovery.tar.age     Your encrypted recovery blob. You create
                             this -- it is not shipped with the kit.
                             See CREATE A VAULT below.

The kit does NOT ship an identity file. Either use the passphrase
ceremony (default, documented here) or bring your own identity file
from a separate drive. An identity file stored on the same USB as the
vault it decrypts defeats the purpose.


-------------------------------------------------------------------------
CREATE A VAULT
-------------------------------------------------------------------------

First, put the files you want to protect into a directory named
recovery/ inside vault/:

  vault/
    recovery/
      id_ed25519
      id_ed25519.pub
      recovery-codes.txt
      ...

Then encrypt everything into a single blob. Commands are run from the
vault/ directory.

On Linux:

  tar c recovery/ | ../ai-kit/age/linux/age -p > recovery.tar.age

On macOS:

  tar c recovery/ | ../ai-kit/age/mac/age -p > recovery.tar.age

On Windows (PowerShell):

  tar -c recovery | & ..\ai-kit\age\win\age.exe -p |
    Set-Content -Encoding Byte recovery.tar.age

age will prompt you twice for a passphrase. Choose something long --
four or five random words is better than a short complex password.
Write it down now. You will need it every time you open the vault.

After encrypting, delete the plaintext recovery/ directory:

  Linux/macOS:  rm -rf recovery/
  Windows:      Remove-Item -Recurse -Force recovery\

Verify the blob exists before deleting anything:

  Linux/macOS:  ls -lh recovery.tar.age
  Windows:      dir recovery.tar.age

The file should be non-zero. If it is 0 bytes or missing, the
encryption step failed -- do not delete recovery/ until you have a
valid recovery.tar.age.


-------------------------------------------------------------------------
OPEN A VAULT
-------------------------------------------------------------------------

Use the launcher for your OS. Run from the vault/ directory or
double-click from the USB root:

  start-vault.sh        on Linux
  start-vault.command   on macOS
  start-vault.bat       on Windows

The launcher decrypts recovery.tar.age to a temporary directory on the
host (not the USB). It prints the tmpdir path and a cleanup reminder
when done. Decrypted files land in the host's temp storage, where POSIX
permissions (0600 on SSH keys) are preserved. exFAT on the USB cannot
store those permissions -- this is why decryption targets the host.

Raw CLI fallback (run from vault/):

  Linux/macOS:  ../ai-kit/age/linux/age -d recovery.tar.age | tar x
  Windows:      ..\ai-kit\age\win\age.exe -d recovery.tar.age | tar x

The raw CLI extracts into the current directory (vault/). Use this only
if the launcher is unavailable. Clean up plaintext files when done.

If the launcher cannot find the age binary, it means build-usb has not
been run against this stick. Run build-usb.sh (Linux/macOS) or
build-usb.ps1 (Windows) against the USB first.


-------------------------------------------------------------------------
WHAT GOES IN THE VAULT
-------------------------------------------------------------------------

Good candidates -- the things you cannot easily regenerate after a
drive failure or a machine wipe:

  SSH private keys              (~/.ssh/id_ed25519, id_rsa, config)
  2FA seeds and TOTP backup files
  Service recovery codes        (GitHub, AWS root, Apple ID, etc.)
  Dotfiles with embedded tokens (.gitconfig, .aws/credentials, .npmrc)
  Scanned IDs and passport copies
  WireGuard and OpenVPN config files
  GPG private key exports

These are suggestions, not a fixed list. If losing something would cost
you hours to recover and it is not otherwise backed up, it belongs here.


-------------------------------------------------------------------------
WHAT DOES NOT GO IN THE VAULT
-------------------------------------------------------------------------

  App state files that need to be writable -- browser profiles, email
  databases, and similar. They break on every new decrypt cycle and are
  too large for a quick-recovery vault.

  The vault's own identity file -- storing the key inside the vault it
  unlocks is a chicken-and-egg problem. Keep the identity file on a
  separate drive.

  Anything over 100 MB -- decryption of large files is slow on age's
  scrypt work factor and defeats the "quick recovery" purpose. For large
  data, consider separate encryption outside the vault.

  Entire development environments or node_modules trees -- recreate
  those from source. Vault space is for secrets, not for convenience.


-------------------------------------------------------------------------
ADVANCED CEREMONIES
-------------------------------------------------------------------------

The passphrase ceremony above covers most cases. Two other patterns
exist for higher security requirements:

  Hardware-key ceremony -- use a YubiKey or FIDO2 key as the identity
  file (age-plugin-yubikey or age-plugin-fido2-hmac). The kit does not
  bundle these plugins; install them on the host first.

  Recipient + passphrase fallback -- encrypt to a hardware key as the
  primary recipient and to a passphrase-based recipient as fallback.
  Requires the multi-recipient feature of age (-r flag, multiple times).

Full ceremony walkthroughs for both patterns are in the repo at:
  docs/vault-guide.md

That file is not deployed to the USB; access it from a cloned copy of
the Doomstick repo or online at:
  https://github.com/Domdhi/Domdhi.Doomstick/blob/main/docs/vault-guide.md
