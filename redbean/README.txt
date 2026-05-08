redbean — Doomstick local platform layer
=========================================

What is this?

  redbean is a single-file webserver built on Cosmopolitan Libc by Justine
  Tunney. Same APE polyglot trick as llamafile: one binary that's
  simultaneously a Windows .exe, Linux ELF, macOS Mach-O, and POSIX shell
  script. Runs on six OSes, AMD64 + ARM64, no install.

  We ship redbean as the kit's HTTP platform layer. Today it serves the
  DOOM static page (doom/), /health, the USB-resident DOOM save handlers
  (/save /load /list), and TTS via /tts (Sherpa-ONNX + Supertonic int8).
  Tomorrow it'll host the EmbeddingGemma RAG layer — same instance.

Files in this directory after build:

  redbean.com       The APE binary. Same file boots on Win/Mac/Linux/BSD.
                    Fetched by build-usb.sh from https://redbean.dev/ .
                    .init.lua is BAKED IN at build time (zip-appended);
                    the .init.lua file alongside is for inspection only.

  .init.lua         Reference copy of the route script. The version
                    redbean actually runs lives inside redbean.com's
                    appended zip. Edits here do nothing until you re-run
                    build-usb.sh (or manually re-bake with
                    `cd ai-kit/redbean && zip redbean.com .init.lua`).
                    Routes today: /health, /save /load /list (DOOM
                    saves — SQLite-backed), /tts (Sherpa-ONNX +
                    Supertonic int8 → audio/wav), /rag (501 stub).

  saves.db          SQLite. Schema: saves(slot INTEGER PRIMARY KEY,
                    name TEXT, data BLOB, updated_at TEXT). Created on
                    first save. Slots 0..5 (DOOM exposes 6).

  redbean.log       (Created on first launch.) stdout+stderr from the most
                    recent redbean run. Inspect after a launcher failure.

How it gets started:

  Tools start redbean as needed via their launcher. start-doom.sh / .bat /
  .command does this today:

      sh ai-kit/redbean/redbean.com -p 8768 -D <USB-root> -L redbean.log

  On Windows, the same binary is invoked as:

      ai-kit\redbean\redbean.com -p 8768 -D %~dp0 -L %~dp0ai-kit\redbean.log

  -p   port (8765 = AI core, 8766 = whisper, 8767 = kiwix, 8768 = us)
  -D   docroot — files served from here when no registered route matches.
       Note: -D does NOT expose .init.lua as an asset (only static
       files), so .init.lua MUST be inside redbean.com's appended zip.
  -L   log file — redbean writes structured logs of every request

Multiple tools share one redbean instance:

  Each customer (DOOM, future saves, Piper, RAG) registers its routes in
  .init.lua. Customers don't spin up their own instance — they all share
  the redbean started by whichever launcher fired first. Subsequent
  launchers detect redbean is already up and just open the browser.

  The pkill-then-restart pattern in the existing whisper/kiwix launchers
  is RELAXED here: start-doom.sh checks /health and skips the start step
  if redbean already answers. This avoids tearing down an active session.

Adding a new route:

  1. Add a handler function in .init.lua.
  2. Wire it into OnHttpRequest()'s if/elseif chain.
  3. Update the SetHeader content-type for the response shape.
  4. Re-bake the binary so the new script ships:
        cd ai-kit/redbean && zip -q redbean.com .init.lua
     (build-usb.sh does this automatically on next run.)
  5. Document the route here in README.txt.

  Pattern reference: the live SaveHandler / LoadHandler / ListHandler in
  .init.lua are working SQLite-backed examples — copy their lsqlite3
  open/prepare/bind/step/finalize/close pattern when adding stateful
  routes (e.g. future RAG).

  TtsHandler is the working subprocess example — fork + execve to a
  per-OS native binary under ai-kit/<tool>/<linux|mac|win>/, slurp its
  output file, return as the response body. argv-based exec (not shell)
  means user-supplied bytes in the body can't inject. Future native-
  binary customers (sherpa speech recognition, etc.) follow this shape.

Cosmopolitan / APE gotchas:

  * On WSL, the binary triggers the Windows-interop loader (APE polyglot
    detection). Prefix with `sh` to bypass: `sh redbean.com ...`. Same trick
    as llamafile. The bash launcher does this automatically; the .bat
    launcher uses the .exe-renamed copy on Windows native.

  * On macOS, you may need to clear Gatekeeper quarantine on first run:
    `xattr -d com.apple.quarantine ai-kit/redbean/redbean.com`. Future
    launcher-side fix planned; for now an OS dialog is the gating event.

License:

  redbean is ISC-licensed. https://github.com/jart/cosmopolitan
