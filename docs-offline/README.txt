DevDocs Offline (manual setup)
==============================

This folder is a placeholder. build-usb does NOT auto-fetch DevDocs.

Two options to populate it:

  Option A: portable browser with DevDocs's built-in offline cache
            (see docs/setup-devdocs.md, recommended)

  Option B: vendor a static snapshot of devdocs into this folder
            (see docs/setup-devdocs.md, more work but no portable
            browser needed)

Once populated, the start-docs.{bat,command,sh} launcher at the USB
root will open docs-offline/index.html in your default browser.

Until then, start-docs prints this README's path and exits.
