/**
 * _extras-providers.js — S2.6, v0.8 RAG epic
 *
 * First-run provider seeding for the vendored Hollama 0.35.4 chat tab.
 * Runs as a deferred script injected into dashboard/chat/index.html.
 *
 * PIN: Hollama 0.35.4 / commit 78c63850fa9fdb3dc4ce447c6b0e86c3af926123
 *
 * Server object schema (from src/lib/connections.ts at pinned commit):
 *   {
 *     id:             string          // unique identifier — Hollama uses 6-char base-36
 *                                     // random strings (e.g. "z7avx9"); we use stable
 *                                     // deterministic IDs so re-seeding is idempotent
 *     baseUrl:        string          // OpenAI-compatible base URL (include /v1 suffix)
 *     connectionType: string          // 'ollama' | 'openai' | 'openai-compatible'
 *     isVerified:     Date | null     // null = unverified; Hollama sets after /api/version
 *     isEnabled:      boolean         // true = Hollama fetches models from this server
 *     label?:         string          // human-readable display name shown in sidebar
 *     modelFilter?:   string          // substring filter applied to Hollama's model list
 *     apiKey?:        string          // optional; not needed for local llamafile
 *   }
 *
 * localStorage keys (per PINNED.md § localStorage keys):
 *   hollama-servers      — array of Server objects (read + written here)
 *   doomstick_seeded_v1  — idempotency flag; set to '1' after this script runs
 *
 * Timing decision: Hollama initialises its Svelte store by reading localStorage
 * synchronously at module import time, inside the dynamic import chain kicked
 * off by the inline <body> script. "defer" scripts run after HTML parsing
 * completes but generally BEFORE Hollama's dynamic imports resolve, so writing
 * `hollama-servers` here lands before Hollama's store reads it on first boot.
 *
 * The `dispatchEvent(new StorageEvent('storage'))` call below is harmless
 * defensive code, NOT a load-bearing fallback. Confirmed by Windows agent
 * DOM probe 2026-05-09 (docs/testing/wave-3-prep-2026-05-09/windows-followup/):
 * Hollama 0.35.4's compiled bundle has ZERO `addEventListener('storage', ...)`
 * registrations across all 47 _app/immutable/*.js files. Same-window
 * StorageEvent dispatch is legal JS (the HTML5 "fires only in OTHER windows"
 * rule applies to native localStorage.setItem writes, not to explicit
 * dispatchEvent calls), but no listener exists to receive it — the call is
 * a no-op for Hollama's UI. Provider seeding works because the localStorage
 * write happens BEFORE Hollama's first read, not because of the dispatch.
 * The dispatch is kept in case a future Hollama upstream adds a listener.
 */

(function doomstickProviders() {
  'use strict';

  const SEEDED_KEY = 'doomstick_seeded_v1';
  const SERVERS_KEY = 'hollama-servers';
  const LOG_PREFIX = '[doomstick]';

  /**
   * Three default servers. Array order is preserved in localStorage and
   * determines which server Hollama selects by default when the user first
   * opens the model picker. E4B is first so it is the default.
   *
   * isEnabled: true  — Hollama fetches the model list from enabled servers.
   *                    Set true so the servers are immediately usable without
   *                    requiring the user to manually enable them in Settings.
   * isVerified: null — Hollama verifies on demand when the user opens Settings
   *                    or when it can reach the endpoint. Null is the correct
   *                    initial state per getDefaultServer() in connections.ts.
   * modelFilter      — Substring filter for Hollama's model list dropdown.
   *                    Set to the full model filename so only the right model
   *                    appears even if llamafile exposes others in future.
   */
  var SEEDS = [
    {
      id: 'doomstick-e4b-v1',
      label: 'Doomstick AI Core (E4B)',
      baseUrl: 'http://127.0.0.1:8765/v1',
      connectionType: 'openai-compatible',
      modelFilter: 'gemma-4-E4B-it-Q4_K_M',
      isVerified: null,
      isEnabled: true
    },
    {
      id: 'doomstick-26b-v1',
      label: 'Doomstick AI Core (26B)',
      baseUrl: 'http://127.0.0.1:8765/v1',
      connectionType: 'openai-compatible',
      modelFilter: 'gemma-4-26B-A4B-it-UD-Q4_K_M',
      isVerified: null,
      isEnabled: true
    },
    {
      id: 'doomstick-embed-v1',
      label: 'Doomstick Embeddings',
      baseUrl: 'http://127.0.0.1:8769/v1',
      connectionType: 'openai-compatible',
      modelFilter: 'embeddinggemma-300m-qat-Q8_0',
      isVerified: null,
      isEnabled: false  // embeddings-only; Hollama's chat flow can't use it,
                        // but registering it gives the user visibility into
                        // what's running and a one-click way to inspect it.
                        // Disabled by default to avoid polluting the model list.
    }
  ];

  function run() {
    try {
      // AC 3: flag is always checked first; both paths set it before returning.
      if (localStorage.getItem(SEEDED_KEY) === '1') {
        console.log(LOG_PREFIX + ' providers already seeded — skipping');
        return;
      }

      var raw = localStorage.getItem(SERVERS_KEY);
      var existing = null;

      try {
        existing = JSON.parse(raw || '[]');
      } catch (parseErr) {
        console.warn(LOG_PREFIX + ' hollama-servers parse error — treating as empty', parseErr);
        existing = [];
      }

      // AC 2: existing user with non-empty hollama-servers → no-op on data.
      if (Array.isArray(existing) && existing.length > 0) {
        console.log(LOG_PREFIX + ' existing servers found — skipping seed, marking as seeded');
        localStorage.setItem(SEEDED_KEY, '1');
        return;
      }

      // AC 1: fresh install → seed 3 servers.
      localStorage.setItem(SERVERS_KEY, JSON.stringify(SEEDS));
      localStorage.setItem(SEEDED_KEY, '1');
      console.log(LOG_PREFIX + ' seeded 3 servers into hollama-servers');

      // Nudge Hollama's store subscriber in case hydration already ran.
      // window.dispatchEvent so it fires on the same browsing context.
      try {
        window.dispatchEvent(new StorageEvent('storage', {
          key: SERVERS_KEY,
          newValue: localStorage.getItem(SERVERS_KEY),
          storageArea: localStorage
        }));
      } catch (evtErr) {
        // Non-fatal — Hollama will pick up the value on next render cycle.
        console.warn(LOG_PREFIX + ' StorageEvent dispatch failed (non-fatal)', evtErr);
      }

      // First-boot UX hint: Hollama keeps `isVerified: null` on each server
      // until the user opens /settings and clicks Re-verify (or until the
      // app calls /api/version itself, which it doesn't do for
      // openai-compatible servers on boot). Until then, the model list is
      // empty and the Send button is disabled. Auto-firing Hollama's
      // internal verification is too coupled to the bundle's private API
      // to do safely from an adapter; documenting the one-click step is
      // the right answer until Hollama exposes a hook. v0.8.1 finding #4.
      showToast('3 servers added · open Settings → click Re-verify on each to load models');

    } catch (err) {
      // Never throw — a seeding failure must not break Hollama's boot.
      console.error(LOG_PREFIX + ' provider seeding failed (non-fatal)', err);
    }
  }

  function showToast(message) {
    try {
      var toast = document.createElement('div');
      toast.className = 'doomstick-toast';
      toast.textContent = message;
      document.body.appendChild(toast);

      // Begin fade-out at 2.6 s, remove at 3 s (matches CSS animation duration).
      setTimeout(function () {
        toast.classList.add('doomstick-toast--dismissing');
      }, 2600);

      setTimeout(function () {
        if (toast.parentNode) {
          toast.parentNode.removeChild(toast);
        }
      }, 3000);
    } catch (toastErr) {
      // Toast is purely cosmetic — swallow silently.
      console.warn(LOG_PREFIX + ' toast failed (non-fatal)', toastErr);
    }
  }

  // Run immediately if document is already parsed, otherwise wait for
  // DOMContentLoaded (the "defer" attribute should guarantee the DOM is
  // ready, but this guard makes the script safe if loaded any other way).
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }

}());
