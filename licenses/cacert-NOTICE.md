# licenses/cacert-NOTICE.md — third-party attribution & license boundary

Everything in `ai-kit/certs/` is licensed differently from the rest of the
Doomstick repo. The repo as a whole is **Apache-2.0**; `cacert.pem` is
distributed under the **Mozilla Public License 2.0 (MPL-2.0)**.

## What's here

| File | Size | Origin | License |
|------|------|--------|---------|
| `ai-kit/certs/cacert.pem` | ~226 KB | curl.se (repackaged from Mozilla) | MPL-2.0 |

- **SHA256 (v0.12 pin, measured 2026-05-10):**
  `b6e66569cc3d438dd5abe514d0df50005d570bfc96c14dca8f768d020cb96171`
- **Mozilla CA data date:** 2026-02-11
- **PRE.J size assertion range:** [200,000 – 350,000] bytes (absorbs ~5 years
  of Mozilla CA bundle growth)

## Upstream

- **cacert.pem:** https://curl.se/docs/caextract.html
  - Quote: "The file is distributed under the Mozilla Public License 2.0."
  - Mozilla CA data: https://wiki.mozilla.org/CA
  - curl.se repackages Mozilla's CA bundle for direct use with curl.

## Update cadence

Mozilla refreshes the CA bundle a few times per year. Re-running
`build-usb.sh` (or `build-usb.ps1`) against the USB re-fetches the latest
bundle automatically. The SHA256 pin above reflects the version shipped at
v0.12 build time; a newer bundle will have a different hash.

## Use pattern

```bash
# curl — pass the bundle explicitly:
curl --cacert "$ROOT/ai-kit/certs/cacert.pem" https://example.com

# Python requests:
export REQUESTS_CA_BUNDLE="$ROOT/ai-kit/certs/cacert.pem"

# Git (on hosts with stale/missing system CAs):
git config --global http.sslCAInfo "$ROOT/ai-kit/certs/cacert.pem"
```

## Why always-on (no bundle toggle)?

At ~226 KB, cacert.pem is too small to warrant a skip toggle. Any host that
needs offline TLS connectivity gets the bundle free; hosts that don't need it
waste only 226 KB. Compare with ffmpeg (~210 MB) and KeePassXC (~250 MB),
which justify toggle gates.

## Why ship pre-built instead of using the system CA bundle?

Some deployment targets (minimal Linux, Windows without curl, offline Raspberry
Pi) have stale or missing system CA bundles. Shipping a known-good Mozilla
bundle makes `curl --cacert` work everywhere without relying on the host OS
having up-to-date TLS roots.
