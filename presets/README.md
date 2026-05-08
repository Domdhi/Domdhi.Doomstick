# presets/

Menu data for the interactive `build-usb.{sh,ps1}` wizard. Both scripts read
these TSV files at wizard time so adding a new option (a different Wikipedia
ZIM, a new OSM region, a Whisper variant) is a single edit, not two.

## Format

- Tab-delimited (literal `\t`, not multiple spaces).
- Comment lines start with `#` and are skipped.
- Blank lines are skipped.
- First non-comment row is the header — also skipped at parse time, but kept
  for human readers.
- Column order matters; see each file's header for its schema.

Both `bash` (`while IFS=$'\t' read ...`) and PowerShell
(`Import-Csv -Delimiter "\`t\``") parse this format with no external deps.

## Files

| File | Purpose | Columns |
|------|---------|---------|
| `bundles.tsv` | tiny / balanced / full bundle definitions | name, label, e4b, moe, emb, wiki, osm, whisper, ocr, docs, redbean, doom, zim_idx, osm_idx, whisper_idx, estimated_bytes, summary |
| `zim.tsv` | Wikipedia ZIM options | label, url, filename, bytes |
| `osm.tsv` | OSM Geofabrik region options | label, url, filename, bytes |
| `whisper.tsv` | Whisperfile variants | label, url, filename, bytes |
| `ocr.tsv` | Tesseract.js language packs | code, label, bytes |

`redbean` and `doom` were added in v0.5. If you add another customer of redbean
later (a Piper column, a RAG column), the field index for `zim_idx` /
`osm_idx` / `whisper_idx` shifts again — both `apply_bundle` (bash) and
`Apply-Bundle` (PowerShell) must update in lockstep or the wizard silently
maps the wrong fields.

## Adding an entry

Edit the relevant `.tsv`, add a row, save. Both `build-usb.sh` and
`build-usb.ps1` will pick it up on next wizard invocation. No script changes
needed.

For ZIM and OSM, the URL is upstream — the kit doesn't host these. Verify the
URL before committing (a 404 only surfaces at user build time and is a bad UX
moment).
