/**
 * _extras-journal.js — S4.2, v0.8 RAG epic
 *
 * Daily journal sidebar entry for the vendored Hollama 0.35.4 chat tab.
 * Adds a "Journal" button to the sidebar that opens a panel with a date
 * picker (defaulting to today) and a textarea editor. "Save" posts to
 * /journal/append on redbean (port 8768), which appends a "## HH:MM"
 * section to workspace/<current>/journal/YYYY-MM-DD.md AND auto-ingests
 * the file into RAG so the day's notes are queryable via /rag/query.
 *
 * Coordination contract:
 *   - Reads localStorage.doomstick_workspace (set by S3.2 _extras-workspace.js)
 *   - Listens to window 'doomstick:workspace-changed' (S3.2 dispatches)
 *
 * Endpoints:
 *   GET  /journal/today?workspace=<name>  → { content, doc_path, exists }
 *   POST /journal/append?workspace=<name> JSON{text} → { status, ... }
 *
 * Hollama 0.35.4 sidebar contract (per dashboard/chat/PINNED.md):
 *   [data-testid="sidebar"] is the stable sidebar root (BEM-confirmed).
 *   Inject the journal entry as a sibling of #sessions-panel inside the
 *   sidebar — sidebar's flex layout absorbs new children naturally.
 *
 * Mobile mode: the chat tab is desktop-primary; the journal feature is
 * desktop-only (mobile users use PocketPal AI per the §02m Mobile Field
 * Kit on the dashboard).
 */

(function doomstickJournal() {
  'use strict';

  var IS_MOBILE = (function () {
    try {
      return matchMedia('(pointer: coarse)').matches ||
             /Mobi|Android|iPhone|iPad/.test(navigator.userAgent);
    } catch (_) { return false; }
  }());
  if (IS_MOBILE) return;

  // ── Constants ──────────────────────────────────────────────────────────────
  var RAG_BASE              = 'http://127.0.0.1:8768';
  var WORKSPACE_KEY         = 'doomstick_workspace';
  var DEFAULT_WORKSPACE     = 'default';
  var WORKSPACE_CHANGE_EVENT = 'doomstick:workspace-changed';
  var FETCH_TIMEOUT_MS      = 5000;
  var SAVE_TIMEOUT_MS       = 30000;  // generous: auto-ingest is in this round-trip
  var ANCHOR_WAIT_MS        = 10000;
  var LOG                   = '[doomstick]';

  // ── Helpers ────────────────────────────────────────────────────────────────
  function currentWorkspace() {
    try {
      var ws = localStorage.getItem(WORKSPACE_KEY);
      return (typeof ws === 'string' && ws !== '') ? ws : DEFAULT_WORKSPACE;
    } catch (_) { return DEFAULT_WORKSPACE; }
  }

  function todayISO() {
    var d = new Date();
    var pad = function (n) { return n < 10 ? '0' + n : '' + n; };
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }

  function fetchWithTimeout(url, opts, timeoutMs) {
    var controller = (typeof AbortController !== 'undefined') ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, timeoutMs) : null;
    var finalOpts = opts || {};
    if (controller) finalOpts.signal = controller.signal;
    return fetch(url, finalOpts)
      .then(function (resp) {
        if (timer) clearTimeout(timer);
        return resp;
      })
      .catch(function (err) {
        if (timer) clearTimeout(timer);
        return Promise.reject(err);
      });
  }

  // ── CSS injection ──────────────────────────────────────────────────────────
  function injectStyles() {
    try {
      if (document.querySelector('style[data-doomstick-journal]')) return;
      var style = document.createElement('style');
      style.setAttribute('data-doomstick-journal', '1');
      style.textContent = [
        '.doomstick-journal-button {',
        '  display: block;',
        '  width: 100%;',
        '  padding: 0.5rem 0.75rem;',
        '  margin: 0.5rem 0 0 0;',
        '  background: var(--color-shade-2, #f3f4f6);',
        '  border: 1px solid var(--color-shade-4, #e5e7eb);',
        '  border-radius: 0.375rem;',
        '  font-size: 0.875rem;',
        '  text-align: left;',
        '  cursor: pointer;',
        '  color: inherit;',
        '}',
        '.doomstick-journal-button:hover {',
        '  background: var(--color-shade-3, #e5e7eb);',
        '}',
        '.doomstick-journal-panel {',
        '  position: fixed;',
        '  top: 50%; left: 50%;',
        '  transform: translate(-50%, -50%);',
        '  width: min(90vw, 36rem);',
        '  max-height: 80vh;',
        '  z-index: 9500;',
        '  display: flex; flex-direction: column;',
        '  background: var(--color-shade-1, #fff);',
        '  border: 1px solid var(--color-shade-4, #e5e7eb);',
        '  border-radius: 0.5rem;',
        '  box-shadow: 0 8px 32px rgba(0,0,0,0.18);',
        '  padding: 1rem;',
        '}',
        '.doomstick-journal-overlay {',
        '  position: fixed; inset: 0;',
        '  background: rgba(0,0,0,0.35);',
        '  z-index: 9400;',
        '}',
        '.doomstick-journal-header {',
        '  display: flex; align-items: center; justify-content: space-between;',
        '  margin-bottom: 0.75rem;',
        '}',
        '.doomstick-journal-header h2 {',
        '  margin: 0; font-size: 1rem;',
        '}',
        '.doomstick-journal-close {',
        '  background: transparent; border: none;',
        '  font-size: 1.25rem; line-height: 1;',
        '  cursor: pointer; padding: 0.25rem 0.5rem;',
        '  color: inherit;',
        '}',
        '.doomstick-journal-row {',
        '  display: flex; align-items: center; gap: 0.5rem;',
        '  margin-bottom: 0.5rem; font-size: 0.8125rem;',
        '}',
        '.doomstick-journal-row label { min-width: 5rem; color: var(--color-shade-7, #6b7280); }',
        '.doomstick-journal-row input[type="date"] {',
        '  padding: 0.25rem 0.5rem;',
        '  background: var(--color-shade-1, #fff);',
        '  border: 1px solid var(--color-shade-4, #d1d5db);',
        '  border-radius: 0.25rem;',
        '  color: inherit;',
        '}',
        '.doomstick-journal-existing {',
        '  flex: 1;',
        '  margin: 0.5rem 0;',
        '  padding: 0.5rem;',
        '  background: var(--color-shade-2, #f9fafb);',
        '  border: 1px solid var(--color-shade-4, #e5e7eb);',
        '  border-radius: 0.25rem;',
        '  font-family: ui-monospace, "JetBrains Mono", monospace;',
        '  font-size: 0.75rem;',
        '  white-space: pre-wrap;',
        '  overflow: auto;',
        '  max-height: 25vh;',
        '}',
        '.doomstick-journal-existing.empty {',
        '  font-style: italic; color: var(--color-shade-7, #9ca3af);',
        '}',
        '.doomstick-journal-textarea {',
        '  width: 100%; min-height: 8rem; resize: vertical;',
        '  padding: 0.5rem;',
        '  background: var(--color-shade-1, #fff);',
        '  border: 1px solid var(--color-shade-4, #d1d5db);',
        '  border-radius: 0.25rem;',
        '  font-family: inherit; font-size: 0.875rem;',
        '  color: inherit;',
        '  box-sizing: border-box;',
        '}',
        '.doomstick-journal-actions {',
        '  display: flex; justify-content: flex-end; gap: 0.5rem;',
        '  margin-top: 0.75rem;',
        '}',
        '.doomstick-journal-actions button {',
        '  padding: 0.375rem 0.875rem;',
        '  border: 1px solid var(--color-shade-4, #d1d5db);',
        '  border-radius: 0.25rem;',
        '  font-size: 0.8125rem;',
        '  cursor: pointer;',
        '  background: var(--color-shade-1, #fff);',
        '  color: inherit;',
        '}',
        '.doomstick-journal-actions button.primary {',
        '  background: var(--color-shade-7, #4b5563);',
        '  color: var(--color-shade-1, #fff);',
        '  border-color: var(--color-shade-7, #4b5563);',
        '}',
        '.doomstick-journal-status {',
        '  font-size: 0.75rem; color: var(--color-shade-7, #6b7280);',
        '  margin-right: auto; align-self: center;',
        '}',
        '.doomstick-journal-status.error { color: #b91c1c; }'
      ].join('\n');
      document.head.appendChild(style);
    } catch (e) {
      console.warn(LOG + ' journal style injection failed (non-fatal)', e);
    }
  }

  // ── Sidebar anchor ─────────────────────────────────────────────────────────
  function findSidebar() {
    return document.querySelector('[data-testid="sidebar"]') ||
           document.querySelector('nav[aria-label="Main navigation"]') ||
           null;
  }

  function whenSidebarReady(callback) {
    var found = findSidebar();
    if (found) { callback(found); return; }
    var obs = new MutationObserver(function () {
      var s = findSidebar();
      if (s) { obs.disconnect(); callback(s); }
    });
    try {
      obs.observe(document.body, { childList: true, subtree: true });
    } catch (_) { return; }
    setTimeout(function () {
      obs.disconnect();
      if (!document.querySelector('.doomstick-journal-button')) {
        var fallback = document.body;
        callback(fallback);
      }
    }, ANCHOR_WAIT_MS);
  }

  // ── Panel lifecycle ────────────────────────────────────────────────────────
  var openPanel = null;

  function closePanel() {
    if (!openPanel) return;
    try {
      if (openPanel.overlay && openPanel.overlay.parentNode) {
        openPanel.overlay.parentNode.removeChild(openPanel.overlay);
      }
      if (openPanel.panel && openPanel.panel.parentNode) {
        openPanel.panel.parentNode.removeChild(openPanel.panel);
      }
    } catch (_) {}
    openPanel = null;
  }

  function loadDateContent(workspace, dateISO, existingEl, statusEl) {
    // /journal/today only returns today's file. For arbitrary dates we'd need
    // a /journal/load?date=<d> endpoint (not in v0.8). For non-today dates,
    // hide the existing-content panel — the user can still write a new entry,
    // which will land in today's file regardless of the date picker (the
    // backend always uses os.date() server-side).
    var isToday = (dateISO === todayISO());
    if (!isToday) {
      existingEl.textContent = '(viewing past dates is a v0.9 feature — appending always goes to today\'s file)';
      existingEl.classList.add('empty');
      return;
    }
    statusEl.textContent = 'loading…';
    statusEl.classList.remove('error');
    fetchWithTimeout(
      RAG_BASE + '/journal/today?workspace=' + encodeURIComponent(workspace),
      { method: 'GET' },
      FETCH_TIMEOUT_MS
    )
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        if (data.exists && data.content) {
          existingEl.textContent = data.content;
          existingEl.classList.remove('empty');
        } else {
          existingEl.textContent = '(no entries yet today — start writing below)';
          existingEl.classList.add('empty');
        }
        statusEl.textContent = '';
      })
      .catch(function (err) {
        existingEl.textContent = '(could not reach redbean on 8768 — start-doom may not be running)';
        existingEl.classList.add('empty');
        statusEl.textContent = 'load error: ' + ((err && err.message) || err);
        statusEl.classList.add('error');
      });
  }

  function buildPanel(workspace) {
    var overlay = document.createElement('div');
    overlay.className = 'doomstick-journal-overlay';
    overlay.addEventListener('click', closePanel);

    var panel = document.createElement('div');
    panel.className = 'doomstick-journal-panel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Doomstick journal');

    var header = document.createElement('div');
    header.className = 'doomstick-journal-header';
    var title = document.createElement('h2');
    title.textContent = 'Journal · workspace: ' + workspace;
    header.appendChild(title);
    var closeBtn = document.createElement('button');
    closeBtn.className = 'doomstick-journal-close';
    closeBtn.setAttribute('aria-label', 'Close journal');
    closeBtn.textContent = '×';
    closeBtn.addEventListener('click', closePanel);
    header.appendChild(closeBtn);
    panel.appendChild(header);

    var dateRow = document.createElement('div');
    dateRow.className = 'doomstick-journal-row';
    var dateLabel = document.createElement('label');
    dateLabel.setAttribute('for', 'doomstick-journal-date');
    dateLabel.textContent = 'Date:';
    var dateInput = document.createElement('input');
    dateInput.type = 'date';
    dateInput.id = 'doomstick-journal-date';
    dateInput.value = todayISO();
    dateRow.appendChild(dateLabel);
    dateRow.appendChild(dateInput);
    panel.appendChild(dateRow);

    var existingLabel = document.createElement('div');
    existingLabel.className = 'doomstick-journal-row';
    existingLabel.style.marginTop = '0.5rem';
    var existingTextLabel = document.createElement('label');
    existingTextLabel.textContent = 'Today so far:';
    existingLabel.appendChild(existingTextLabel);
    panel.appendChild(existingLabel);

    var existing = document.createElement('div');
    existing.className = 'doomstick-journal-existing empty';
    existing.textContent = 'loading…';
    panel.appendChild(existing);

    var ta = document.createElement('textarea');
    ta.className = 'doomstick-journal-textarea';
    ta.placeholder = 'Append a new entry — saves with timestamp ## HH:MM and auto-ingests into RAG.';
    panel.appendChild(ta);

    var actions = document.createElement('div');
    actions.className = 'doomstick-journal-actions';
    var status = document.createElement('span');
    status.className = 'doomstick-journal-status';
    actions.appendChild(status);
    var cancel = document.createElement('button');
    cancel.textContent = 'Close';
    cancel.addEventListener('click', closePanel);
    actions.appendChild(cancel);
    var save = document.createElement('button');
    save.className = 'primary';
    save.textContent = 'Append';
    actions.appendChild(save);
    panel.appendChild(actions);

    save.addEventListener('click', function () {
      var text = (ta.value || '').replace(/\s+$/, '');
      if (!text) {
        status.textContent = 'nothing to append';
        status.classList.add('error');
        return;
      }
      status.textContent = 'saving…';
      status.classList.remove('error');
      save.disabled = true;
      cancel.disabled = true;
      var ws = currentWorkspace();
      fetchWithTimeout(
        RAG_BASE + '/journal/append?workspace=' + encodeURIComponent(ws),
        {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ text: text })
        },
        SAVE_TIMEOUT_MS
      )
        .then(function (r) {
          return r.json().then(function (data) { return { ok: r.ok, data: data }; });
        })
        .then(function (res) {
          save.disabled = false;
          cancel.disabled = false;
          if (!res.ok) {
            status.textContent = 'save failed: ' + (res.data && res.data.error || 'unknown');
            status.classList.add('error');
            console.warn(LOG + ' /journal/append failed', res.data);
            return;
          }
          var label = 'saved (' + (res.data.bytes_written || 0) + ' bytes)';
          if (res.data.ingest_status === 'ok') {
            label += ' · indexed ' + (res.data.chunks_written || 0) + ' chunk(s)';
          } else if (res.data.ingest_status === 'failed') {
            label += ' · indexing failed (start-embed not running?)';
          }
          status.textContent = label;
          ta.value = '';
          // Re-load today's content so the user sees their entry plus existing.
          loadDateContent(ws, dateInput.value, existing, status);
          console.log(LOG + ' journal append ok', res.data);
        })
        .catch(function (err) {
          save.disabled = false;
          cancel.disabled = false;
          status.textContent = 'save error: ' + ((err && err.message) || err);
          status.classList.add('error');
          console.warn(LOG + ' /journal/append threw', err);
        });
    });

    dateInput.addEventListener('change', function () {
      loadDateContent(currentWorkspace(), dateInput.value, existing, status);
    });

    document.body.appendChild(overlay);
    document.body.appendChild(panel);
    openPanel = { overlay: overlay, panel: panel };

    // Initial load.
    loadDateContent(workspace, dateInput.value, existing, status);
    setTimeout(function () { try { ta.focus(); } catch (_) {} }, 50);
  }

  // ── Sidebar button ─────────────────────────────────────────────────────────
  function injectButton(sidebar) {
    try {
      if (document.querySelector('.doomstick-journal-button')) return;
      var btn = document.createElement('button');
      btn.className = 'doomstick-journal-button';
      btn.type = 'button';
      btn.textContent = '📓 Journal';
      btn.title = 'Open the daily journal · workspace=' + currentWorkspace();
      btn.addEventListener('click', function () {
        if (openPanel) { closePanel(); return; }
        buildPanel(currentWorkspace());
      });
      // Place near the sessions panel if we can find it; otherwise at the
      // top of the sidebar.
      var sessions = sidebar.querySelector('#sessions-panel');
      if (sessions && sessions.parentNode) {
        sessions.parentNode.insertBefore(btn, sessions);
      } else {
        sidebar.insertBefore(btn, sidebar.firstChild);
      }
      console.log(LOG + ' journal button injected');
    } catch (e) {
      console.warn(LOG + ' journal button injection failed (non-fatal)', e);
    }
  }

  // ── Coordination ───────────────────────────────────────────────────────────
  window.addEventListener(WORKSPACE_CHANGE_EVENT, function (ev) {
    try {
      var ws = (ev && ev.detail && ev.detail.workspace) || currentWorkspace();
      var btn = document.querySelector('.doomstick-journal-button');
      if (btn) btn.title = 'Open the daily journal · workspace=' + ws;
      // Close any open panel — user must reopen for the new workspace context.
      closePanel();
    } catch (_) {}
  });

  // Esc closes the open panel.
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && openPanel) {
      closePanel();
    }
  });

  // ── Boot ───────────────────────────────────────────────────────────────────
  function run() {
    try {
      injectStyles();
      whenSidebarReady(function (sidebar) {
        injectButton(sidebar);
      });
    } catch (e) {
      console.error(LOG + ' journal boot failed (non-fatal)', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
}());
