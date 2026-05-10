PASSWORDS
=========

This directory holds your KeePassXC password database. The file
(vault.kdbx) is not shipped with the kit -- you create it here on
first use. The KeePassXC application is bundled at ai-kit/keepassxc/
and launched from the USB root via start-passwords.


------------------------------------------------------------------------
WHAT THIS DIR IS
------------------------------------------------------------------------

  passwords/README.txt    This file.

  passwords/vault.kdbx   Your password database. You create this on
                         first use -- it is not shipped with the kit.
                         KeePassXC reads and writes it in place on the
                         USB. Because it is self-contained, it travels
                         with the drive to any host.

The vault.kdbx file is a standalone encrypted binary. Every entry
(username, password, URL, notes) is encrypted inside it using the
master password you choose during the first-use ceremony below.
KeePassXC uses Argon2id as its default key derivation function, which
makes brute-force search impractical against a strong master password.
If you forget your master password, the database is unrecoverable by
design. There is no back door.


------------------------------------------------------------------------
FIRST-USE CEREMONY
------------------------------------------------------------------------

Run these steps once, the first time you launch KeePassXC from this USB.

  Step 1 -- Launch KeePassXC.

     Windows:  double-click start-passwords.bat at the USB root
     macOS:    double-click start-passwords.command at the USB root
     Linux:    run ./start-passwords.sh from a terminal at the USB root

     On first launch, the launcher opens the KeePassXC GUI. Because
     passwords/vault.kdbx does not exist yet, KeePassXC shows its
     open-database dialog (not your database).

  Step 2 -- Create a new database.

     In the KeePassXC dialog, choose "Create new database" (or File >
     New Database). Follow the wizard:

       - Name the database anything you like.
       - Accept the default encryption settings (AES-256, Argon2id).
       - Choose a master password. Pick something long -- four or five
         random words is harder to crack than a short complex string.

     When KeePassXC asks where to save the file, navigate to the
     passwords/ folder on this USB and save it as vault.kdbx.

  Step 3 -- Verify the file exists.

     After saving, confirm passwords/vault.kdbx is present on the USB.
     Close and reopen the database to verify your master password works
     before you rely on this database for anything important.

  Step 4 -- Write your master password down.

     Store it somewhere physically separate from this USB. Two copies,
     two locations. If you lose the master password and the database is
     your only copy of a credential, the credential is gone forever.


------------------------------------------------------------------------
DAY-TO-DAY USE
------------------------------------------------------------------------

To open your password database on any host, run the launcher from the
USB root:

  Windows:  start-passwords.bat
  macOS:    start-passwords.command
  Linux:    ./start-passwords.sh

The launcher detects your OS, finds the right KeePassXC binary under
ai-kit/keepassxc/, and opens passwords/vault.kdbx automatically.
KeePassXC prompts for your master password, then shows your entries.

The launcher window can be closed after KeePassXC opens -- KeePassXC
runs independently and does not need the terminal to stay open.

To add, edit, or delete entries, use KeePassXC's built-in interface.
Changes are saved back to passwords/vault.kdbx on the USB.


------------------------------------------------------------------------
MULTI-HOST PORTABILITY
------------------------------------------------------------------------

vault.kdbx is fully self-contained. It travels with the USB and can be
opened on any host that has KeePassXC (the kit bundles KeePassXC for
Windows, macOS arm64, and Linux x86_64).

What IS portable (travels on the USB):
  - passwords/vault.kdbx and all the entries inside it.
  - The KeePassXC application under ai-kit/keepassxc/.

What is NOT portable (stays on each host):
  - KeePassXC's recent-files list. On a new host, the "recently opened"
    list is empty. The launcher bypasses this by passing the database
    path directly, so day-to-day use is unaffected.
  - KeePassXC settings. Windows reads keepassxc.ini from the same
    folder as the binary (portable mode). Linux and macOS write their
    settings to ~/.config/KeePassXC/ and
    ~/Library/Preferences/KeePassXC/ on the host. Settings are per-
    host by design -- the database itself does not depend on them.
  - Browser integration plugins. If you use the KeePassXC browser
    extension on a host, configure it on that host separately.


------------------------------------------------------------------------
BACKUP RECOMMENDATION
------------------------------------------------------------------------

The USB drive is a single point of failure. Back up vault.kdbx before
the drive fails, not after.

Option A -- Copy to a second USB:

  Copy passwords/vault.kdbx to another USB drive or a secure offline
  location. Even a plain copy is protected by the master password.

Option B -- Encrypted backup via the age vault (recommended):

  This USB also ships a separate age-based recovery vault (vault/).
  Include vault.kdbx in your recovery archive alongside SSH keys and
  other credentials:

    Linux/macOS:
      cp passwords/vault.kdbx vault/recovery/
      tar c vault/recovery/ | ai-kit/age/linux/age -p > vault/recovery.tar.age

    Then delete vault/recovery/ (see vault/README.txt for the full
    ceremony). This pairs vault.kdbx with the rest of your recovery
    material and gives you a single encrypted blob that survives a
    "lost USB" scenario.

  For the complete age vault workflow, see vault/README.txt on this USB.

Sync frequency: back up vault.kdbx whenever you add or change important
entries. Stale backups are better than no backup, but not by much.


------------------------------------------------------------------------
LICENSE
------------------------------------------------------------------------

KeePassXC is free software licensed under the GNU General Public
License version 2 or later (GPL-2.0+). The license text and attribution
notices for the bundled binary are in:

  ai-kit/keepassxc/NOTICE.md
  ai-kit/keepassxc/LICENSE-GPL-2.0

Your password data (vault.kdbx) is yours. The GPL applies to the
KeePassXC application, not to the databases it manages.
