# dashboard/chat — Hollama vendor pin

Filled at S1.4 of the v0.8 RAG epic.

This file documents the **DOM contract** — every observable assumption
the Doomstick adapter makes about Hollama's runtime DOM. Adapter
breakage on a Hollama bump shows up first as MutationObserver wait
timeouts; the breakage points back here.

---

## Pin

- **Upstream:** [github.com/fmaclen/hollama](https://github.com/fmaclen/hollama)
- **Commit SHA:** `78c63850fa9fdb3dc4ce447c6b0e86c3af926123`
- **Tag / version:** `0.35.4`
- **Build command:**
  ```
  git clone https://github.com/fmaclen/hollama /tmp/hollama-build
  cd /tmp/hollama-build
  npm ci
  npm install --save-dev @sveltejs/adapter-static
  # Patch svelte.config.js — replace adapterCloudflare with adapterStatic
  # (see "Build patch notes" below)
  npm run build
  # Post-process index.html to convert absolute paths to relative
  sed -e 's|href="/_app/|href="./_app/|g' \
      -e 's|href="/favicon|href="./favicon|g' \
      -e 's|href="/fonts/|href="./fonts/|g' \
      -e 's|import("/_app/|import("./_app/|g' \
      build/index.html > /tmp/index-patched.html
  cp /tmp/index-patched.html build/index.html
  cp -r build/* <repo>/dashboard/chat/
  cp LICENSE <repo>/dashboard/chat/LICENSE
  ```
- **License:** MIT (verbatim copy at `dashboard/chat/LICENSE`)

## Build patch notes

Risk R3 materialized as expected. Two changes required for `file://` compatibility:

**1. Swap adapter (svelte.config.js):** Upstream uses `@sveltejs/adapter-cloudflare`
which emits a server-rendered bundle, not a static SPA. Replaced with
`@sveltejs/adapter-static` (installed as devDependency) with `fallback: 'index.html'`
(SPA mode). Added `kit.paths.relative = true` in the config — this handles dynamic
JS imports between chunks (they come out as `../chunks/...` relative paths), but
does NOT fix the initial HTML.

**2. Post-process index.html:** SvelteKit's adapter-static still emits absolute
paths in the prerendered `index.html` (`/_app/...`, `/favicon.png`, `/fonts/...`)
even with `paths.relative = true`. The `paths.relative` option only affects the
JS runtime router, not the static HTML generation. Fix: a targeted sed pass on
`build/index.html` converts all `/` root-relative paths to `./` relative paths.
The JS chunks themselves use correct relative `../chunks/...` imports already;
only the HTML needs patching.

When bumping Hollama, run the same sed post-process on the new `build/index.html`.
The pattern is stable — SvelteKit has not changed this HTML generation behavior
for several major versions.

## Adapter file layout

The `_doomstick-extras*` files load AFTER Hollama's app boots. Split
across stories so Wave 3 can dispatch parallel agents with no file
overlap:

| File | Story | Purpose |
|------|-------|---------|
| `_doomstick-extras.css` | S2.6 | Shared styling for popup + dropdown + journal |
| `_extras-providers.js` | S2.6 | First-run server seeding (E4B, 26B, embeddings) |
| `_extras-rag.js` | S3.1 | `#filename` autocomplete + send-intercept retrieval |
| `_extras-workspace.js` | S3.2 | Workspace dropdown injected above model picker |
| `_extras-sessions.js` | S3.3 | Debounced `/chat/save` + `/chat/list` merge |
| `_extras-journal.js` | S4.2 | Sidebar tab + date picker + editor |

`dashboard/chat/index.html` gets ONE diff to upstream Hollama:

```html
<link rel="stylesheet" href="_doomstick-extras.css">
<script defer src="_extras-providers.js"></script>
<script defer src="_extras-rag.js"></script>
<script defer src="_extras-workspace.js"></script>
<script defer src="_extras-sessions.js"></script>
<script defer src="_extras-journal.js"></script>
```

(Injected before `</body>`. The script `defer` attribute ensures Hollama's
own bundle runs first; adapters wait for the DOM via MutationObserver.)

## DOM contract (partially filled at S1.4)

Each row below is a coupling point. If upstream renames a selector,
fix it here AND in the adapter that uses it.

Selectors that are stable in source (not hydration-generated) are
confirmed. Selectors that depend on Svelte's runtime rendering or
Bits UI components need live browser verification.

| Selector / API | Used by | Purpose | Status |
|----------------|---------|---------|--------|
| `textarea.prompt-editor__textarea` | `_extras-rag.js` | Prompt input — hash-keypress autocomplete + send-intercept. Source: `Prompt.svelte` line 317 — `class="prompt-editor__textarea"` + `name="prompt"`. | Confirmed from source (CSS class is static) |
| `nav[aria-label="Main navigation"]` or `[data-testid="sidebar"]` | `_extras-workspace.js`, `_extras-journal.js` | Sidebar root — workspace dropdown injects ABOVE; journal tab injects BESIDE. Source: `CollapsibleSidebar.svelte` line 66 — `data-testid="sidebar"`. | Confirmed from source |
| `#model` (preferred) or `input[data-melt-combobox-input]` | `_extras-workspace.js` | Model picker trigger — workspace dropdown injects as firstChild of the wrapper `.prompt-editor__project` (Strategy A). Bits UI Combobox is implemented internally with melt-ui; the listbox IS portaled when opened, but the trigger input stays inside `.prompt-editor__project`. | **Confirmed in browser** — Windows DOM probe 2026-05-09. Stable parent: `.prompt-editor__project`. |
| `.prompt-editor__submit button` (also intercept Ctrl+Enter on textarea) | `_extras-rag.js` | Send-button click — intercept for retrieval-then-augment. **Critical:** the button is `type="button"`, NOT `type="submit"`, and there is NO `<form>` element wrapping the prompt editor. Adapter MUST hook `click` on the button AND `keydown` Ctrl+Enter / Cmd+Enter on the textarea — Hollama submits on either path, and bare Enter inserts a newline (it is NOT a submit key). | **Confirmed in browser** — Windows DOM probe 2026-05-09. Stable parent: `.prompt-editor__submit`. |
| `#sessions-panel` | `_extras-sessions.js` | Sessions sidebar root — adapter merges server-side sessions in. Source: `CollapsibleSidebar.svelte` line 113 — `id="sessions-panel"`. | Confirmed from source |

### localStorage keys (the adapter touches)

Actual keys verified by reading `/src/lib/localStorage.ts`:

| Key | Owner | Read | Write | Notes |
|-----|-------|------|-------|-------|
| `hollama-settings` | Hollama | yes (S2.6 first-run check) | no | User preferences (theme, language, models). Enum: `StorageKey.HollamaPreferences`. Note: PINNED.md skeleton used `hollama-preferences` — the actual key is `hollama-settings`. |
| `hollama-servers` | Hollama | yes (S2.6 first-run check) | yes (S2.6 first-run seed) | Array of server connection objects. Enum: `StorageKey.HollamaServers`. |
| `hollama-sessions` | Hollama | yes (S3.3 boot, merge with server) | yes (S3.3 debounced save) | Array of session objects. Enum: `StorageKey.HollamaSessions`. |
| `hollama-knowledge` | Hollama | no | no | Knowledge base items. Adapter doesn't touch. Enum: `StorageKey.HollamaKnowledge`. |
| `doomstick_seeded_v1` | Doomstick adapter | yes (S2.6) | yes (S2.6) | First-run idempotency flag |
| `doomstick_workspace` | Doomstick adapter | yes (S3.2) | yes (S3.2) | Currently selected workspace name |

### Send-flow contract (S3.1 — `_extras-rag.js`)

When the user hits Send with a prompt that begins with `@<doc_path>`
(injected by the `#filename` autocomplete):

1. Adapter's send-intercept hook fires BEFORE Hollama's actual fetch
2. Strip the `@<doc_path>` token, keep the rest as the user's question
3. POST `http://127.0.0.1:8768/rag/query?workspace=<current>&k=5`
   with `q=<user-question>`
4. Build augmented prompt:
   ```
   Relevant excerpts from <doc_path>:
   [chunk 1 text]
   [chunk 2 text]
   ...

   User question: <original question>
   ```
5. Replace the textarea content with the augmented prompt and let
   Hollama's own send proceed normally

If `/rag/query` fails (8768 down, network error, no results), adapter
falls back to letting the original prompt through unmodified with a
console warning. **Fail-soft.**

### Save-flow contract (S3.3 — `_extras-sessions.js`)

On every detectable session change (MutationObserver on `#sessions-panel`
or polling localStorage at 1Hz — decide at S3.3):

1. Debounce 2 s after last change
2. Read full session JSON from `hollama-sessions` in localStorage
3. POST to `http://127.0.0.1:8768/chat/save` with
   `{id, workspace, title, body}` where body is the opaque session JSON
4. On 2xx response: log `[doomstick] saved session <id>` to console
5. On error: log warning, fall back to localStorage-only

On boot:

1. GET `http://127.0.0.1:8768/chat/list?workspace=<current>`
2. Merge server sessions into Hollama's localStorage session array,
   prefer server copy on UUID collision
3. Trigger Hollama's session-list re-render via `location.reload()`
   gated by a `sessionStorage.doomstick_boot_merge_done` flag (one
   reload per browser session; cleared on workspace change so the
   user sees the new workspace's sessions). **NOTE:**
   `dispatchEvent(new StorageEvent('storage'))` does NOT work for this
   purpose — confirmed by Windows DOM probe 2026-05-09: Hollama 0.35.4
   has zero `addEventListener('storage', ...)` registrations across all
   47 `_app/immutable/*.js` bundles, so same-window dispatch is a no-op.
   The dispatch in `_extras-providers.js` is harmless defensive code; the
   provider seed works only because the localStorage write happens before
   Hollama's first read.

## Upgrade checklist (when bumping Hollama)

1. Stash current `dashboard/chat/_app/` etc, fetch new build, replace
2. Apply adapter-static patch + index.html sed post-process (see Build patch notes)
3. Reload `file://.../dashboard/chat/index.html` (or `http://localhost:8780`), open DevTools
4. For each row in the DOM contract table above: confirm selector
   still resolves
5. Spot-check first-run seeding (S2.6), `#filename` autocomplete
   (S3.1), workspace dropdown (S3.2), session save (S3.3), journal
   tab (S4.2)
6. If any selector moved, update both this file and the adapter that
   uses it
7. Update SHA / tag at top of this file
8. Smoke the chat tab in Edge or Chrome on Windows: open Settings →
   Re-verify each server, send a `#<doc>` query, confirm the augmented
   prompt round-trips and that the journal tab append + reload works

## Why not fork Hollama

Forking introduces a perpetual diff against an active single-author
upstream; the adapter pattern buys the same features for ~400 lines
of vanilla JS across five `_extras-*.js` files plus one `.css`. The
DOM contract above is the only Hollama-internal coupling, and it's
small enough to re-verify in 10–30 minutes per upstream bump. If the
adapter ever exceeds ~500 lines total, revisit the fork question.

---

_Filled at S1.4 of the v0.8 RAG epic (2026-05-09). Skeleton committed at Wave 0._
