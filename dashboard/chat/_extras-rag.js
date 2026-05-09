/**
 * _extras-rag.js — S3.1, v0.8 RAG epic
 *
 * `#filename` autocomplete + send-intercept retrieval for vendored Hollama 0.35.4.
 * PIN: commit 78c63850fa9fdb3dc4ce447c6b0e86c3af926123
 *
 * Flow:
 *   '#' at word boundary → popup from /rag/list-docs → pick → @<doc_path> token
 *   '@<doc_path> <question>' on send → /rag/query → augmented prompt → Hollama submit
 *
 * '@' not '#' as the post-pick marker: '#' is the UI trigger only;
 * '@' is what the send-intercept recognises so the two concerns stay decoupled.
 *
 * dispatchEvent(new Event('input',{bubbles:true})) after programmatic textarea
 * writes: Svelte's reactive binding reads value on 'input', not on DOM mutation —
 * without it the store holds the stale value when the send button is re-clicked.
 */

(function doomstickRag() {
  'use strict';

  // Mobile gate: popup requires pointer-fine device (hover, keyboard nav).
  var IS_MOBILE = matchMedia('(pointer: coarse)').matches ||
    /Mobi|Android|iPhone|iPad/.test(navigator.userAgent);
  if (IS_MOBILE) return;

  // ── Constants ──────────────────────────────────────────────────────────────

  var RAG_BASE            = 'http://127.0.0.1:8768';
  var QUERY_K             = 5;
  var QUERY_TIMEOUT_MS    = 5000;
  var LISTDOCS_TIMEOUT_MS = 2000;
  var TOKEN_REGEX         = /@(\S+)/;  // eslint-disable-line no-unused-vars
  var WORKSPACE_KEY       = 'doomstick_workspace';
  var DEFAULT_WORKSPACE   = 'default';
  var LOG                 = '[doomstick]';

  var TEXTAREA_CANDIDATES = [
    'textarea.prompt-editor__textarea',
    'textarea[name="prompt"]',
  ];

  var SEND_BUTTON_CANDIDATES = [
    '.prompt-editor__submit button',                  // confirmed primary (Windows DOM probe 2026-05-09)
    '.prompt-editor__submit > button',                 // tighter fallback if Hollama nests buttons in future
    '.prompt-editor__submit button:last-of-type',     // legacy fallback — single button today, harmless
    // NOTE: '[type="submit"]' selectors removed — the button is type="button"
    //       and there is NO <form> element. Use click + Ctrl+Enter keydown only.
  ];

  // S3.1-specific CSS; injected as a <style> element — _doomstick-extras.css untouched.
  var POPUP_CSS =
    '.doomstick-rag-popup{position:absolute;z-index:9999;' +
    'background:var(--color-background,#1a1a2e);border:1px solid var(--color-border,#333);' +
    'border-radius:6px;min-width:280px;max-width:440px;max-height:220px;overflow-y:auto;' +
    'box-shadow:0 4px 16px rgba(0,0,0,.4);font-size:13px;display:none}' +
    '.doomstick-rag-popup.doomstick-popup--open{display:block}' +
    '.doomstick-rag-item{padding:7px 12px;cursor:pointer;white-space:nowrap;' +
    'overflow:hidden;text-overflow:ellipsis;color:var(--color-text,#e0e0e0)}' +
    '.doomstick-rag-item:hover,.doomstick-rag-item--active{background:var(--color-accent,#2d2d5e)}' +
    '.doomstick-rag-empty{padding:8px 12px;color:var(--color-text-muted,#888);font-style:italic}';

  // ── State ──────────────────────────────────────────────────────────────────

  var docCache      = {};   // keyed by workspace; invalidated on workspace-changed
  var popup         = null;
  var activeTextarea = null;
  var activeIndex   = -1;
  var popupOpen     = false;

  // ── Selectors ──────────────────────────────────────────────────────────────

  function findTextarea() {
    for (var i = 0; i < TEXTAREA_CANDIDATES.length; i++) {
      var el = document.querySelector(TEXTAREA_CANDIDATES[i]);
      if (el) return el;
    }
    return null;
  }

  function findSendButton() {
    for (var i = 0; i < SEND_BUTTON_CANDIDATES.length; i++) {
      var el = document.querySelector(SEND_BUTTON_CANDIDATES[i]);
      if (el) return el;
    }
    return null;
  }

  // ── Network ────────────────────────────────────────────────────────────────

  function fetchWithTimeout(url, ms) {
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, ms);
    return fetch(url, { signal: ctrl.signal }).then(function (res) {
      clearTimeout(timer);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    }, function (err) {
      clearTimeout(timer);
      throw err;
    });
  }

  function getCurrentWorkspace() {
    try { return localStorage.getItem(WORKSPACE_KEY) || DEFAULT_WORKSPACE; }
    catch (e) { return DEFAULT_WORKSPACE; }
  }

  // ── Popup ──────────────────────────────────────────────────────────────────

  function buildPopup() {
    popup = document.createElement('div');
    popup.className = 'doomstick-rag-popup';
    popup.setAttribute('role', 'listbox');
    document.body.appendChild(popup);
  }

  function positionPopup(textarea) {
    try {
      var r  = textarea.getBoundingClientRect();
      var sy = window.scrollY || document.documentElement.scrollTop;
      var sx = window.scrollX || document.documentElement.scrollLeft;
      var h  = popup.offsetHeight || 220;
      var top = r.top >= h + 4 ? sy + r.top - h - 4 : sy + r.bottom + 4;
      popup.style.top  = top + 'px';
      popup.style.left = (sx + r.left) + 'px';
      popup.style.width = Math.max(r.width, 280) + 'px';
    } catch (e) {
      console.warn(LOG, 'popup position failed (non-fatal)', e);
    }
  }

  function setActiveIndex(idx) {
    var items = popup.querySelectorAll('.doomstick-rag-item');
    items.forEach(function (el, i) {
      el.classList.toggle('doomstick-rag-item--active', i === idx);
    });
    activeIndex = idx;
  }

  function renderItems(docs) {
    popup.innerHTML = '';
    if (!docs || !docs.length) {
      var em = document.createElement('div');
      em.className = 'doomstick-rag-empty';
      em.textContent = 'No matching docs';
      popup.appendChild(em);
      return;
    }
    docs.forEach(function (doc, idx) {
      var item = document.createElement('div');
      item.className = 'doomstick-rag-item';
      item.setAttribute('role', 'option');
      item.setAttribute('data-doc-path', doc.doc_path);
      item.textContent = doc.doc_path + ' · ' + doc.chunk_count + ' chunks';
      item.addEventListener('mouseover', function () { setActiveIndex(idx); });
      item.addEventListener('mousedown', function (e) {
        // mousedown before blur keeps textarea focus so insertion works.
        e.preventDefault();
        pickItem(doc.doc_path);
      });
      popup.appendChild(item);
    });
  }

  function openPopup(textarea, docs) {
    if (!popup) buildPopup();
    activeIndex = -1;
    renderItems(docs);
    popup.classList.add('doomstick-popup--open');
    popupOpen = true;
    positionPopup(textarea);
  }

  function closePopup() {
    if (!popup) return;
    popup.classList.remove('doomstick-popup--open');
    popupOpen = false;
    activeIndex = -1;
  }

  // Replace #<partial> token with @<doc_path> in the textarea.
  function pickItem(docPath) {
    if (!activeTextarea) return;
    try {
      var val    = activeTextarea.value;
      var cursor = activeTextarea.selectionStart;
      var start  = cursor;
      while (start > 0 && !/\s/.test(val[start - 1])) { start--; }
      if (val[start] !== '#') { closePopup(); return; }
      var replacement = '@' + docPath;
      activeTextarea.value = val.slice(0, start) + replacement + val.slice(cursor);
      var pos = start + replacement.length;
      activeTextarea.setSelectionRange(pos, pos);
      // Svelte reactive binding requires 'input' event for programmatic value changes.
      activeTextarea.dispatchEvent(new Event('input', { bubbles: true }));
      activeTextarea.focus();
    } catch (e) {
      console.warn(LOG, 'pickItem failed (non-fatal)', e);
    }
    closePopup();
  }

  // ── Autocomplete ───────────────────────────────────────────────────────────

  function getHashPartial(textarea) {
    var val    = textarea.value;
    var cursor = textarea.selectionStart;
    var start  = cursor;
    while (start > 0 && !/\s/.test(val[start - 1])) { start--; }
    var token = val.slice(start, cursor);
    return token[0] === '#' ? token.slice(1) : null;
  }

  function fetchDocList(workspace, cb) {
    if (docCache[workspace]) { cb(null, docCache[workspace]); return; }
    var url = RAG_BASE + '/rag/list-docs?workspace=' + encodeURIComponent(workspace);
    fetchWithTimeout(url, LISTDOCS_TIMEOUT_MS)
      .then(function (data) {
        var docs = (data && Array.isArray(data.docs)) ? data.docs : [];
        docCache[workspace] = docs;
        cb(null, docs);
      })
      .catch(function (err) {
        console.warn(LOG, '/rag/list-docs failed (non-fatal)', err);
        cb(err, []);
      });
  }

  function filterDocs(docs, partial) {
    if (!partial) return docs;
    var lp = partial.toLowerCase();
    return docs.filter(function (d) { return d.doc_path.toLowerCase().indexOf(lp) !== -1; });
  }

  function handleInput(e) {
    var ta = e.target || activeTextarea;
    if (!ta) return;
    var partial = getHashPartial(ta);
    if (partial === null) { if (popupOpen) closePopup(); return; }
    fetchDocList(getCurrentWorkspace(), function (err, docs) {
      // Re-check: user may have moved cursor or deleted '#' while fetch was in flight.
      var p2 = getHashPartial(ta);
      if (p2 === null) { if (popupOpen) closePopup(); return; }
      openPopup(ta, filterDocs(docs, p2));
    });
  }

  function handleKeydown(e) {
    // Popup navigation (always capture-phase).
    if (popupOpen) {
      var items = popup ? popup.querySelectorAll('.doomstick-rag-item') : [];
      if (e.key === 'Escape') { e.stopPropagation(); closePopup(); return; }
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setActiveIndex(Math.min(activeIndex + 1, items.length - 1));
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setActiveIndex(Math.max(activeIndex - 1, 0));
        return;
      }
      if (e.key === 'Enter' && !e.shiftKey && activeIndex >= 0 && items[activeIndex]) {
        e.preventDefault();
        e.stopPropagation();
        pickItem(items[activeIndex].getAttribute('data-doc-path'));
        return;
      }
    }

    // Send-intercept via Ctrl+Enter / Cmd+Enter when popup is closed.
    // Hollama 0.35.4's prompt editor submits on Ctrl+Enter (or Cmd+Enter on
    // macOS), NOT bare Enter — bare Enter inserts a newline. Confirmed by
    // Windows agent DOM probe 2026-05-09 (docs/testing/wave-3-prep-2026-05-09/).
    if (!popupOpen && e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      maybeIntercept(e, activeTextarea);
    }
  }

  // ── Send-intercept ─────────────────────────────────────────────────────────

  function parseToken(val) {
    var m = val.trim().match(/^@(\S+)\s+([\s\S]+)$/);
    return m ? { docPath: m[1], userQuestion: m[2].trim() } : null;
  }

  function buildAugmentedPrompt(docPath, question, chunks) {
    var parts = ['Relevant excerpts from ' + docPath + ':'];
    chunks.forEach(function (c, i) {
      if (i > 0) parts.push('---');
      parts.push(typeof c === 'string' ? c : (c.text || ''));
    });
    parts.push('', 'User question: ' + question);
    return parts.join('\n');
  }

  function setTextareaValue(ta, val) {
    try {
      ta.value = val;
      // Svelte reactive binding: programmatic .value change requires 'input' event.
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    } catch (e) {
      console.warn(LOG, 'setTextareaValue failed (non-fatal)', e);
    }
  }

  function replaySubmit(ta, fallbackValue) {
    try {
      var btn = findSendButton();
      if (btn) { btn.click(); return; }
      var form = ta.closest('form');
      if (form) { form.requestSubmit(); return; }
      console.warn(LOG, 'replaySubmit: no send button or form found — restoring original');
      setTextareaValue(ta, fallbackValue);
    } catch (e) {
      console.warn(LOG, 'replaySubmit failed (non-fatal)', e);
      try { setTextareaValue(ta, fallbackValue); } catch (_) {}
    }
  }

  // Synchronously calls preventDefault if intercepting; async augmentation
  // then re-fires submit via replaySubmit.
  function maybeIntercept(event, ta) {
    if (!ta) return;
    var parsed = parseToken(ta.value);
    if (!parsed) return;

    if (!parsed.userQuestion) {
      console.warn(LOG, 'no question after @token — sending original unmodified');
      return;
    }

    // Prevent Hollama's submit now; we'll replay after augmentation.
    event.preventDefault();
    event.stopPropagation();

    var docPath      = parsed.docPath;
    var userQuestion = parsed.userQuestion;
    var original     = ta.value;
    var ws           = getCurrentWorkspace();
    var url = RAG_BASE + '/rag/query' +
      '?q='         + encodeURIComponent(userQuestion) +
      '&workspace=' + encodeURIComponent(ws) +
      '&k='         + QUERY_K;

    fetchWithTimeout(url, QUERY_TIMEOUT_MS)
      .then(function (data) {
        var chunks = [];
        try {
          if (data && Array.isArray(data.results) && data.results.length) {
            chunks = data.results.map(function (r) { return r.text || ''; });
          }
        } catch (e) {
          console.warn(LOG, '/rag/query parse error', e);
        }
        if (!chunks.length) {
          console.warn(LOG, '/rag/query no results — sending original unmodified');
          replaySubmit(ta, original);
          return;
        }
        setTextareaValue(ta, buildAugmentedPrompt(docPath, userQuestion, chunks));
        replaySubmit(ta, original);
      })
      .catch(function (err) {
        console.warn(LOG, '/rag/query failed — sending original unmodified', err);
        replaySubmit(ta, original);
      });
  }

  // ── Hook installation ──────────────────────────────────────────────────────

  function installTextareaHooks(ta) {
    activeTextarea = ta;
    ta.addEventListener('input', handleInput);
    ta.addEventListener('keydown', handleKeydown, true); // capture for popup + send
    ta.addEventListener('blur', function () {
      // Delay so mousedown on a popup item fires before blur closes the popup.
      setTimeout(function () { if (popupOpen) closePopup(); }, 150);
    });
  }

  function installSendButtonHook(btn) {
    btn.addEventListener('click', function (e) {
      if (!activeTextarea) return;
      maybeIntercept(e, activeTextarea);
    }, true); // capture-phase: fires before Hollama's own click handler
  }

  // ── MutationObserver bootstrap ─────────────────────────────────────────────
  // Hollama is a Svelte SPA — textarea and send button appear after hydration,
  // not at DOMContentLoaded. MutationObserver watches for their insertion.

  function whenReady(finder, callback) {
    var found = finder();
    if (found) { callback(found); return; }
    var obs = new MutationObserver(function () {
      var el = finder();
      if (el) { obs.disconnect(); callback(el); }
    });
    obs.observe(document.body, { childList: true, subtree: true });
  }

  // ── Workspace-change listener ──────────────────────────────────────────────

  window.addEventListener('doomstick:workspace-changed', function (ev) {
    try {
      var ws = (ev.detail && ev.detail.workspace) ? ev.detail.workspace : DEFAULT_WORKSPACE;
      delete docCache[ws]; // force re-fetch on next '#' keypress for new workspace
      console.log(LOG, 'workspace changed to', ws, '— doc cache invalidated');
    } catch (e) {
      console.warn(LOG, 'workspace-changed handler failed (non-fatal)', e);
    }
  });

  // Click outside popup → dismiss.
  document.addEventListener('mousedown', function (e) {
    if (popupOpen && popup && !popup.contains(e.target)) closePopup();
  }, true);

  // ── Boot ───────────────────────────────────────────────────────────────────

  function init() {
    try {
      var style = document.createElement('style');
      style.id = 'doomstick-rag-styles';
      style.textContent = POPUP_CSS;
      document.head.appendChild(style);

      buildPopup();

      whenReady(findTextarea, function (ta) {
        console.log(LOG, 'textarea ready — installing RAG hooks');
        installTextareaHooks(ta);
      });

      whenReady(findSendButton, function (btn) {
        console.log(LOG, 'send button ready — installing send-intercept');
        installSendButtonHook(btn);
      });
    } catch (e) {
      console.error(LOG, 'RAG adapter init failed (non-fatal)', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

}());
