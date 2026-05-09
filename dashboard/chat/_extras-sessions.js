/**
 * _extras-sessions.js — S3.3, v0.8 RAG epic
 *
 * Debounced auto-save + boot-merge for Hollama 0.35.4 sessions.
 * Rides USB-resident SQLite via redbean's /chat/{save,list,load} endpoints
 * (S2.5, already shipped). Sessions now travel with the USB stick.
 *
 * PIN: Hollama 0.35.4 / commit 78c63850fa9fdb3dc4ce447c6b0e86c3af926123
 *
 * Design decisions:
 *
 *   POLLING vs MONKEY-PATCHING: This shim detects localStorage writes by
 *   polling at 1 Hz (comparing JSON snapshots), not by wrapping
 *   localStorage.setItem. Polling is simpler, requires no assumption about
 *   Svelte's internal call order, and survives any lockdown policy that
 *   prevents storage-proxy patterns. CPU cost: stringifying ~1-5 KB at 1 Hz
 *   is invisible on any hardware that can run llamafile. The alternative
 *   (monkey-patch setItem) would break if another script cached the original
 *   before we patched it, or if the Hollama bundle uses a WeakRef to the
 *   original. Not worth the fragility.
 *
 *   SAVE STRATEGY: On every debounced trigger, ALL sessions in the local
 *   array are POSTed — not just the delta. Hollama session bodies are KB-
 *   range; even with 20 sessions this is a handful of small HTTP requests.
 *   The server upserts on id, so re-saving an unchanged session is a no-op
 *   at the SQLite layer. If session bodies ever grow to MB scale, the
 *   optimization is to track a per-id hash or compare updatedAt before
 *   POSTing — that work belongs in a future story, not v0.8.
 *
 *   BOOT-MERGE: The merge uses an N+1 GET pattern (one /chat/list then one
 *   /chat/load per server-only session). For v0.8, where a user might have
 *   tens of sessions, this is fine. If it ever reaches hundreds the server
 *   could expose a /chat/export endpoint that returns bodies in bulk. The
 *   optimization opportunity is called out inline below.
 *
 *   STORAGE EVENT: After merging server sessions into localStorage, we
 *   dispatch a StorageEvent on the same window to nudge Hollama's store
 *   subscriber. Hollama subscribes via window.addEventListener('storage') —
 *   dispatching it manually from the same frame should trigger the same
 *   handler. This path is flagged <TBD-VERIFY-IN-BROWSER> because the
 *   real-browser behaviour of same-window StorageEvent dispatch against a
 *   Svelte store subscriber has not been live-verified yet; the Windows
 *   agent's parallel DOM probe is checking it.
 *
 * localStorage keys (per PINNED.md §localStorage keys):
 *   hollama-sessions     — array of session objects (read + written here)
 *   doomstick_workspace  — current workspace name (read here, owned by S3.2)
 */

(function doomstickSessions() {
  'use strict';

  // ─── Mobile gate (must be first) ────────────────────────────────────────────
  // Hollama's chat tab is desktop-primary. The session shim is desktop-only.
  // Phones can't reach redbean on 8768 (it runs on the host, not the device).
  var IS_MOBILE = matchMedia('(pointer: coarse)').matches ||
    /Mobi|Android|iPhone|iPad/.test(navigator.userAgent);
  if (IS_MOBILE) {
    return;
  }

  // ─── Constants ──────────────────────────────────────────────────────────────
  var RAG_BASE            = 'http://127.0.0.1:8768';
  var SESSIONS_KEY        = 'hollama-sessions';
  var WORKSPACE_KEY       = 'doomstick_workspace';
  var DEFAULT_WORKSPACE   = 'default';
  var SAVE_DEBOUNCE_MS    = 2000;
  var POLL_INTERVAL_MS    = 1000;
  var FETCH_TIMEOUT_MS    = 5000;
  var SAVE_TIMEOUT_MS     = 5000;
  var WORKSPACE_CHANGE_EVENT = 'doomstick:workspace-changed';
  var LOG_PREFIX          = '[doomstick]';

  // ─── State ──────────────────────────────────────────────────────────────────
  var lastSeenJson  = null;   // last JSON string we observed in localStorage
  var debounceTimer = null;   // setTimeout handle for the save debounce
  var pollHandle    = null;   // setInterval handle for the 1 Hz poller

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /** Return the current workspace, falling back to DEFAULT_WORKSPACE. */
  function currentWorkspace() {
    try {
      return localStorage.getItem(WORKSPACE_KEY) || DEFAULT_WORKSPACE;
    } catch (e) {
      return DEFAULT_WORKSPACE;
    }
  }

  /**
   * Read hollama-sessions from localStorage.
   * Returns an array (possibly empty) or null if localStorage is unavailable
   * or the value is not valid JSON.
   */
  function readLocalSessions() {
    try {
      var raw = localStorage.getItem(SESSIONS_KEY);
      if (!raw) return [];
      var arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr : [];
    } catch (e) {
      console.warn(LOG_PREFIX + ' could not read ' + SESSIONS_KEY + ' from localStorage', e);
      return null;
    }
  }

  /**
   * Write an array of sessions back to localStorage.
   * Returns true on success, false on failure.
   */
  function writeLocalSessions(sessions) {
    try {
      localStorage.setItem(SESSIONS_KEY, JSON.stringify(sessions));
      return true;
    } catch (e) {
      console.warn(LOG_PREFIX + ' could not write ' + SESSIONS_KEY + ' to localStorage', e);
      return false;
    }
  }

  /**
   * Extract a stable `updated_at` string from a Hollama session object.
   * Hollama uses `updatedAt` (camelCase). If absent, return empty string —
   * the server will use now_iso() on its side regardless.
   */
  function sessionUpdatedAt(session) {
    if (session && session.updatedAt) return String(session.updatedAt);
    if (session && session.updated_at) return String(session.updated_at);
    return '';
  }

  /**
   * fetch() wrapper with AbortController timeout and fail-soft error handling.
   * Returns a Response on HTTP success (any status), or null on network error /
   * timeout.
   */
  function fetchWithTimeout(url, options, timeoutMs) {
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, timeoutMs);
    var opts = Object.assign({}, options, { signal: controller.signal });
    return fetch(url, opts)
      .then(function (res) {
        clearTimeout(timer);
        return res;
      })
      .catch(function (err) {
        clearTimeout(timer);
        // AbortError is expected on timeout; other errors are network failures.
        // Both are non-fatal — caller logs and continues with localStorage-only.
        return null;
      });
  }

  // ─── Save flow ──────────────────────────────────────────────────────────────

  /**
   * POST a single session to /chat/save.
   * Returns true if the server returned 2xx, false otherwise.
   */
  function saveOneSession(session, workspace) {
    var id    = session && session.id ? String(session.id) : null;
    var title = (session && session.title) ? String(session.title) : '';
    var body  = null;

    try {
      body = JSON.stringify(session);
    } catch (e) {
      console.warn(LOG_PREFIX + ' could not stringify session ' + id + ' — skipping', e);
      return Promise.resolve(false);
    }

    if (!id || !body) {
      console.warn(LOG_PREFIX + ' session missing id — skipping save');
      return Promise.resolve(false);
    }

    var payload = JSON.stringify({
      id:        id,
      workspace: workspace,
      title:     title,
      body:      body
    });

    return fetchWithTimeout(
      RAG_BASE + '/chat/save',
      {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    payload
      },
      SAVE_TIMEOUT_MS
    ).then(function (res) {
      if (!res) return false;
      return res.ok;
    });
  }

  /**
   * Save ALL sessions from localStorage to the server.
   * Called after the 2 s debounce settles.
   *
   * Strategy: POST every session, not just changed ones. Bodies are KB-range;
   * server upserts are cheap. Delta tracking (comparing updatedAt or body
   * hashes) is the v0.8+ optimization if session bodies grow to MB scale.
   */
  function flushSessions() {
    var sessions = readLocalSessions();
    if (!sessions || sessions.length === 0) return;

    var workspace = currentWorkspace();
    var promises  = sessions.map(function (s) { return saveOneSession(s, workspace); });

    Promise.all(promises)
      .then(function (results) {
        var successes = results.filter(Boolean).length;
        if (successes === results.length) {
          console.log(LOG_PREFIX + ' saved ' + successes + ' session(s) to /chat/save');
        } else {
          var failures = results.length - successes;
          console.warn(
            LOG_PREFIX + ' /chat/save: ' + successes + ' saved, ' + failures + ' failed (non-fatal)'
          );
        }
      })
      .catch(function (err) {
        // Promise.all only rejects if one of its inputs rejects — our per-
        // session promises always resolve, so this is a belt-and-suspenders
        // guard only.
        console.warn(LOG_PREFIX + ' /chat/save batch failed (non-fatal)', err);
      });
  }

  /**
   * Schedule a debounced save.  Every write to localStorage.hollama-sessions
   * resets the 2 s timer.  Only the final settled state is flushed to the
   * server (matching Hollama's streaming-token pattern).
   */
  function scheduleSave() {
    if (debounceTimer !== null) {
      clearTimeout(debounceTimer);
    }
    debounceTimer = setTimeout(function () {
      debounceTimer = null;
      try {
        flushSessions();
      } catch (e) {
        console.warn(LOG_PREFIX + ' flushSessions threw (non-fatal)', e);
      }
    }, SAVE_DEBOUNCE_MS);
  }

  // ─── 1 Hz poller ────────────────────────────────────────────────────────────

  /**
   * Compare the current localStorage value of hollama-sessions against the
   * last seen snapshot.  If it changed, schedule a save.
   *
   * Called at 1 Hz.  Runs synchronously; stringify cost is negligible for
   * KB-range payloads.
   */
  function pollTick() {
    try {
      var current = localStorage.getItem(SESSIONS_KEY);
      if (current !== lastSeenJson) {
        lastSeenJson = current;
        scheduleSave();
      }
    } catch (e) {
      // localStorage may be unavailable in certain private-browsing modes.
      // Swallow and keep polling — there's nothing else to do.
      console.warn(LOG_PREFIX + ' poll tick error (non-fatal)', e);
    }
  }

  function startPoller() {
    if (pollHandle !== null) clearInterval(pollHandle);
    // Capture initial snapshot so the first tick doesn't trigger a spurious save.
    try {
      lastSeenJson = localStorage.getItem(SESSIONS_KEY);
    } catch (e) {
      lastSeenJson = null;
    }
    pollHandle = setInterval(pollTick, POLL_INTERVAL_MS);
  }

  function stopPoller() {
    if (pollHandle !== null) {
      clearInterval(pollHandle);
      pollHandle = null;
    }
  }

  // ─── Boot-merge flow ────────────────────────────────────────────────────────

  /**
   * Fetch the list of server sessions for `workspace` and merge them into
   * the local hollama-sessions array.
   *
   * Algorithm:
   *  1. GET /chat/list?workspace=<name>  →  array of {id, title, bytes, updated_at}
   *     NOTE: body is NOT included in list response; must GET /chat/load per session.
   *  2. For each server session:
   *     a. If not present locally by id → fetch body from /chat/load?id=<id>
   *        and inject into local array.
   *     b. If present locally AND on server → compare updated_at strings
   *        (ISO 8601 — lexicographic comparison is correct).
   *        Server wins on conflict (per PINNED.md §Save-flow contract).
   *        If server is newer → fetch body and replace local copy.
   *        If local is newer → keep local copy (server will receive it on
   *        next debounced save, which is scheduled separately).
   *  3. Write merged array back to localStorage.hollama-sessions.
   *  4. Dispatch StorageEvent to trigger Hollama's store subscriber.
   *
   * Optimization note: this is an N+1 GET pattern — one list call, then one
   * /chat/load per session that needs a body. For v0.8 (tens of sessions) this
   * is fine.  A future /chat/export endpoint returning bodies in bulk would
   * reduce this to 1 round trip.  That optimization lives in a future story.
   */
  function bootMerge(workspace) {
    var listUrl = RAG_BASE + '/chat/list?workspace=' + encodeURIComponent(workspace);

    fetchWithTimeout(listUrl, {}, FETCH_TIMEOUT_MS)
      .then(function (res) {
        if (!res) {
          console.warn(LOG_PREFIX + ' /chat/list unreachable — continuing with localStorage-only');
          return null;
        }
        if (!res.ok) {
          console.warn(LOG_PREFIX + ' /chat/list returned ' + res.status + ' — continuing with localStorage-only');
          return null;
        }
        return res.json();
      })
      .then(function (data) {
        if (!data || !Array.isArray(data.chats)) return;

        var localSessions = readLocalSessions();
        if (!localSessions) localSessions = [];

        // Build an id → local-session index for O(1) lookups.
        var localIndex = {};
        localSessions.forEach(function (s) {
          if (s && s.id) localIndex[s.id] = s;
        });

        // Build an id → server-metadata index for O(1) lookups.
        var serverMeta = {};
        data.chats.forEach(function (c) {
          if (c && c.id) serverMeta[c.id] = c;
        });

        // Determine which server sessions need a body fetch.
        //   - Not present locally at all → always fetch.
        //   - Present locally with server updated_at > local updated_at → fetch.
        //   - Present locally with local >= server → skip (local wins; will
        //     propagate to server on next debounced save).
        var toFetch = data.chats.filter(function (serverEntry) {
          var local = localIndex[serverEntry.id];
          if (!local) return true;  // not in localStorage → needs fetch
          var localTs  = sessionUpdatedAt(local);
          var serverTs = serverEntry.updated_at || '';
          // ISO 8601 strings compare lexicographically. Server wins on tie.
          return serverTs >= localTs;
        });

        if (toFetch.length === 0) {
          // Nothing to pull from the server.  Re-arm the poller snapshot so the
          // just-merged localStorage state doesn't trigger a spurious save.
          try { lastSeenJson = localStorage.getItem(SESSIONS_KEY); } catch (e) {}
          return;
        }

        // Fetch bodies for sessions that need them.
        var fetchPromises = toFetch.map(function (serverEntry) {
          var loadUrl = RAG_BASE + '/chat/load?id=' + encodeURIComponent(serverEntry.id);
          return fetchWithTimeout(loadUrl, {}, FETCH_TIMEOUT_MS)
            .then(function (res) {
              if (!res || !res.ok) {
                console.warn(LOG_PREFIX + ' /chat/load failed for id=' + serverEntry.id + ' (non-fatal)');
                return null;
              }
              return res.json();
            })
            .then(function (data) {
              if (!data || typeof data.body !== 'string') return null;
              try {
                return JSON.parse(data.body);
              } catch (e) {
                console.warn(LOG_PREFIX + ' could not parse body for session ' + serverEntry.id + ' (non-fatal)', e);
                return null;
              }
            })
            .catch(function (e) {
              console.warn(LOG_PREFIX + ' /chat/load threw for id=' + serverEntry.id + ' (non-fatal)', e);
              return null;
            });
        });

        Promise.all(fetchPromises)
          .then(function (loadedSessions) {
            // Apply loaded sessions into the local array.
            // Loaded entries replace existing ones (server wins); new entries
            // are appended.
            loadedSessions.forEach(function (serverSession) {
              if (!serverSession || !serverSession.id) return;
              var idx = localSessions.findIndex(function (s) { return s.id === serverSession.id; });
              if (idx !== -1) {
                localSessions[idx] = serverSession;  // replace with server copy
              } else {
                localSessions.push(serverSession);   // inject new session
              }
            });

            var merged = localSessions;
            var written = writeLocalSessions(merged);

            if (written) {
              console.log(
                LOG_PREFIX + ' boot-merge: pulled ' +
                loadedSessions.filter(Boolean).length +
                ' session(s) from server (workspace=' + workspace + ')'
              );

              // Re-arm the poller snapshot so the write we just did doesn't
              // immediately trigger a debounced save back to the server.
              try { lastSeenJson = localStorage.getItem(SESSIONS_KEY); } catch (e) {}

              // Trigger Hollama's session-list re-render. Confirmed by Windows
              // agent DOM probe 2026-05-09: Hollama 0.35.4 has NO 'storage'
              // event listener anywhere in its bundle (zero matches across
              // all 47 _app/immutable/*.js files), so dispatching a StorageEvent
              // is a no-op for hollama-sessions. The only way to make the merged
              // result visible is a full page reload, gated by a sessionStorage
              // flag so we don't infinite-loop on every navigation.
              // (See docs/testing/wave-3-prep-2026-05-09/windows-followup/REPORT.md
              // §"Probe 3 — StorageEvent on hollama-sessions" for the 47-bundle
              // search + behavioral test that confirmed this.)
              try {
                if (sessionStorage.getItem('doomstick_boot_merge_done') !== '1') {
                  sessionStorage.setItem('doomstick_boot_merge_done', '1');
                  console.log(LOG_PREFIX + ' boot-merged sessions; reloading to render');
                  // setTimeout 0 gives the console.log a chance to flush before
                  // the navigation throws the page away.
                  setTimeout(function () { location.reload(); }, 0);
                }
              } catch (reloadErr) {
                console.warn(LOG_PREFIX + ' reload trigger failed (non-fatal); merged data is on disk but UI may not refresh until next manual reload', reloadErr);
              }
            }
          })
          .catch(function (err) {
            // Belt-and-suspenders — per-session promises always resolve, so
            // Promise.all should not reject here.
            console.warn(LOG_PREFIX + ' boot-merge merge step failed (non-fatal)', err);
          });
      })
      .catch(function (err) {
        console.warn(LOG_PREFIX + ' boot-merge /chat/list threw (non-fatal)', err);
      });
  }

  // ─── Workspace-change listener ──────────────────────────────────────────────

  /**
   * When S3.2 signals a workspace change, re-run boot-merge for the new
   * workspace so sessions scoped to that workspace are merged in.
   *
   * We also flush any pending debounced save for the OLD workspace first,
   * so sessions aren't lost across a workspace switch.
   */
  window.addEventListener(WORKSPACE_CHANGE_EVENT, function (event) {
    try {
      var newWorkspace = (event.detail && event.detail.workspace)
        ? event.detail.workspace
        : DEFAULT_WORKSPACE;
      console.log(LOG_PREFIX + ' workspace changed to "' + newWorkspace + '" — re-running boot-merge');

      // Flush immediately (don't wait for debounce) so the old workspace's
      // sessions are persisted before we switch context.
      if (debounceTimer !== null) {
        clearTimeout(debounceTimer);
        debounceTimer = null;
        try { flushSessions(); } catch (e) {
          console.warn(LOG_PREFIX + ' pre-switch flush failed (non-fatal)', e);
        }
      }

      // Clear the boot-merge flag so the reload after the new merge fires —
      // a workspace switch is user-initiated and the user expects to see the
      // new workspace's sessions, which Hollama can't render in-place (no
      // 'storage' listener — see Windows DOM probe finding).
      try { sessionStorage.removeItem('doomstick_boot_merge_done'); } catch (e) {}

      bootMerge(newWorkspace);
    } catch (e) {
      console.warn(LOG_PREFIX + ' workspace-change handler threw (non-fatal)', e);
    }
  });

  // ─── Boot ───────────────────────────────────────────────────────────────────

  function run() {
    try {
      var workspace = currentWorkspace();
      console.log(LOG_PREFIX + ' sessions shim booting (workspace="' + workspace + '")');

      // 1. Run boot-merge — pulls server sessions and merges with localStorage.
      bootMerge(workspace);

      // 2. Start the 1 Hz poller — watches for Hollama writes and schedules
      //    debounced saves.  Starts AFTER boot-merge is fired (async) so the
      //    poller's initial snapshot reflects the pre-merge state; the merge
      //    will re-arm the snapshot when it completes.
      startPoller();

    } catch (e) {
      // Never throw — a sessions-shim failure must not break Hollama's boot.
      console.error(LOG_PREFIX + ' sessions shim failed to boot (non-fatal)', e);
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
