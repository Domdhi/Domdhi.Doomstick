# Setup: DevDocs Offline

`build-usb.{sh,ps1}` does **not** auto-fetch DevDocs. There is no
canonical first-party "downloadable static export" for DevDocs — the
project (https://devdocs.io) is designed to run as a Ruby/Node web app
and stash docsets in your browser's localStorage.

Two reasonable paths to put a portable, fully offline programming
reference on the kit:

## Option A — Use DevDocs's built-in offline mode (recommended)

This is the easiest path and uses the official site, no setup.

1. **Online, on your build machine,** open https://devdocs.io.
2. Click **Preferences** (gear icon) → enable the docsets you want
   (MDN, Python, Bash, Git, HTML, CSS, JS, Linux man, etc.). Each
   docset is 5–50 MB.
3. Click **Offline data** → **Install** for each enabled docset.
4. Devdocs serializes them into IndexedDB.
5. **Disconnect from the internet.** Reload the page. It still works.

This works on the host, but doesn't ride the USB unless step 6 below.

6. (Optional, to ride the USB) Use a portable browser (Firefox Portable,
   Chromium Portable) on the USB. Repeat steps 1–5 in the portable
   browser. The IndexedDB lives inside the portable profile, which is
   on the USB. Now opening that browser from the USB gives you the
   docs offline on any host.

## Option B — Vendor a static snapshot into `docs-offline/`

If you don't want to run a portable browser, the alternative is to
self-host a static snapshot of the DevDocs site + your chosen docsets.

1. `git clone https://github.com/freeCodeCamp/devdocs.git`
2. `cd devdocs && bundle install`
3. `thor docs:download <docset>` (e.g. `thor docs:download mdn-html`)
   for each docset you want.
4. `thor assets:compile` to build static assets.
5. `bundle exec rackup -p 9292` to serve, OR pull the generated
   `public/` and `docs/` directories.
6. Copy the static output to `docs-offline/` on the USB:
   ```
   docs-offline/
     index.html
     public/...
     docs/...
   ```
7. The kit's `start-docs.{bat,sh,command}` launcher will open
   `docs-offline/index.html` directly via `file://`.

This is more work (and the static export isn't a first-class DevDocs
feature, so it can break between releases), but the result rides the
USB without needing a portable browser.

## Why isn't this in `build-usb`?

Both paths require either an interactive step (Option A) or a Ruby
toolchain + per-docset `thor` invocations (Option B). Neither fits
the "one curl + go" pattern the rest of `build-usb` is built around.

If you find a robust upstream source of pre-built DevDocs static
exports (a CI job that publishes a tarball), edit `build-usb.{sh,ps1}`
to fetch it under `# ---------- devdocs ---------------------------`
and we'll add it to the resumable downloads. Until then, this manual
walkthrough is the path.

## Alternatives we considered and rejected

- **Zeal docsets** (https://zealdocs.org). Reads Dash docsets. Excellent
  content, but Zeal itself is a desktop app — not portable, and per-OS
  installation would defeat the kit. The docsets are usable from the
  USB if a host already has Zeal installed; not the kit's UX.
- **devdocs-desktop** (Electron wrapper). Rejected for the same Electron
  size + portability reasons we avoid Cherry Studio as the default.
- **Pre-rendered MDN dump** (https://developer.mozilla.org/en-US/docs/MDN/Tools/Document_dump).
  Tempting but MDN is just one of the docsets DevDocs covers. Single-source
  is a worse experience than DevDocs's unified search.
