/**
 * _extras-workspace.js — S3.2, v0.8 RAG epic
 * PIN: Hollama 0.35.4 / commit 78c63850fa9fdb3dc4ce447c6b0e86c3af926123
 *
 * Injects a workspace <select> above Hollama's model picker.
 * Persists selection to localStorage (doomstick_workspace).
 * Dispatches doomstick:workspace-changed { detail: { workspace } }
 * so _extras-rag.js (S3.1) and _extras-sessions.js (S3.3) can refetch.
 *
 * Anchor fallback chain: model picker → sidebar → body
 */

(function doomstickWorkspace() {
  'use strict';

  // ── Mobile gate — first thing in the IIFE ──────────────────────────────────
  var IS_MOBILE = matchMedia('(pointer: coarse)').matches ||
    /Mobi|Android|iPhone|iPad/.test(navigator.userAgent);
  if (IS_MOBILE) return;

  // ── Constants ──────────────────────────────────────────────────────────────
  var RAG_BASE             = 'http://127.0.0.1:8768';
  var WORKSPACE_KEY        = 'doomstick_workspace';
  var DEFAULT_WORKSPACE    = 'default';
  var LIST_TIMEOUT_MS      = 3000;
  var ANCHOR_WAIT_MS       = 10000;
  var WORKSPACE_CHANGE_EVENT = 'doomstick:workspace-changed';
  var LOG_PREFIX           = '[doomstick]';

  // Candidates for finding the workspace dropdown insertion anchor.
  // Per Windows DOM probe 2026-05-09, the stable parent is
  // .prompt-editor__project (the BEM-class wrapper around the model picker
  // block). Strategy A: inject the workspace dropdown as firstChild of that
  // wrapper so the picker sits visually above the model row. The Svelte
  // hash classes inside (svelte-9c382j etc.) are build-dependent — we do
  // NOT match against them. The Bits UI Combobox listbox IS portaled when
  // opened, but the trigger input #model stays inside this wrapper.
  var STABLE_PARENT_SELECTOR = '.prompt-editor__project';
  var MODEL_PICKER_CANDIDATES = [
    'input[data-melt-combobox-input]',                  // semantic, BEM-independent (most stable)
    '#model',                                           // confirmed in browser
    'input.field-combobox-input',                       // Hollama BEM source class
    'input[id="model"]',
    '[data-testid="model-select"]'
  ];

  // ── CSS injection ──────────────────────────────────────────────────────────
  // All S3.2-specific styles live here — do NOT touch _doomstick-extras.css
  // (parallel S3.1 / S3.3 agents write to it independently).
  function injectStyles() {
    try {
      if (document.querySelector('style[data-doomstick-workspace]')) return;
      var style = document.createElement('style');
      style.setAttribute('data-doomstick-workspace', '1');
      style.textContent = [
        '.doomstick-workspace-wrapper {',
        '  margin: 0.5rem 0;',
        '  padding: 0.5rem;',
        '  border-bottom: 1px solid var(--color-shade-4, #e5e7eb);',
        '}',
        '.doomstick-workspace-label {',
        '  display: block;',
        '  font-size: 0.75rem;',
        '  margin-bottom: 0.25rem;',
        '  color: var(--color-shade-7, #6b7280);',
        '  user-select: none;',
        '}',
        '.doomstick-workspace-dropdown {',
        '  width: 100%;',
        '  padding: 0.375rem 0.5rem;',
        '  background: var(--color-shade-1, #fff);',
        '  border: 1px solid var(--color-shade-4, #d1d5db);',
        '  border-radius: 0.25rem;',
        '  font-size: 0.875rem;',
        '  color: inherit;',
        '  cursor: pointer;',
        '}'
      ].join('\n');
      document.head.appendChild(style);
    } catch (styleErr) {
      console.warn(LOG_PREFIX + ' style injection failed (non-fatal)', styleErr);
    }
  }

  // ── Anchor resolution ──────────────────────────────────────────────────────

  /**
   * Resolve the stable insertion parent. Two strategies:
   *   1. Direct: .prompt-editor__project exists (BEM, hash-independent) — use it.
   *   2. Climb: probe MODEL_PICKER_CANDIDATES for the trigger input, then walk
   *      up via .closest(STABLE_PARENT_SELECTOR). Survives Hollama bumps that
   *      don't rename the wrapper class.
   * Returns the .prompt-editor__project element (we prepend INSIDE it as
   * firstChild, NOT before its outer parent — Strategy A from the Windows
   * DOM-probe report).
   */
  function findModelPickerAnchor() {
    try {
      var direct = document.querySelector(STABLE_PARENT_SELECTOR);
      if (direct) return direct;
    } catch (_) { /* invalid selector on unusual DOM — skip */ }

    for (var i = 0; i < MODEL_PICKER_CANDIDATES.length; i++) {
      try {
        var el = document.querySelector(MODEL_PICKER_CANDIDATES[i]);
        if (el) {
          var wrapper = el.closest(STABLE_PARENT_SELECTOR);
          if (wrapper) return wrapper;
          // Last-resort: nearest div ancestor's parent (legacy fallback path).
          var block = el.closest('div, fieldset, section, label');
          if (block && block.parentElement) return block.parentElement;
        }
      } catch (_) {
        // Invalid selector in an unusual DOM — skip and try next.
      }
    }
    return null;
  }

  /**
   * Sidebar fallback: [data-testid="sidebar"] or nav[aria-label="Main navigation"].
   * Returns the element itself as the insertion parent (prepend inside it).
   */
  function findSidebarRoot() {
    return document.querySelector('[data-testid="sidebar"]') ||
           document.querySelector('nav[aria-label="Main navigation"]') ||
           null;
  }

  /**
   * Wait for the model picker anchor to appear in the DOM (Hollama is a
   * Svelte SPA — the picker may not exist at DOMContentLoaded).
   * Calls callback(parentEl) once found, or falls back after ANCHOR_WAIT_MS.
   */
  function whenAnchorReady(callback) {
    var found = findModelPickerAnchor();
    if (found) {
      callback(found, 'anchor');
      return;
    }

    var obs = new MutationObserver(function () {
      var a = findModelPickerAnchor();
      if (a) {
        obs.disconnect();
        callback(a, 'anchor');
      }
    });
    obs.observe(document.body, { childList: true, subtree: true });

    // Safety timeout: if the model picker never materialises, fall back to
    // the sidebar root (degraded placement but still functional), and last
    // resort to document.body.
    setTimeout(function () {
      obs.disconnect();
      // Don't inject twice if a parallel MutationObserver callback already fired.
      if (document.querySelector('.doomstick-workspace-dropdown')) return;
      var sidebar = findSidebarRoot();
      if (sidebar) {
        callback(sidebar, 'sidebar');
      } else {
        callback(document.body, 'body');
      }
    }, ANCHOR_WAIT_MS);
  }

  // ── Workspace list fetch ───────────────────────────────────────────────────

  /**
   * Fetch /rag/list-workspaces with a timeout.
   * Resolves to an array of workspace objects: [{name, chunks, docs}, ...].
   * On any error, resolves to [] so the caller can use the fallback path.
   */
  function fetchWorkspaces() {
    return new Promise(function (resolve) {
      var controller;
      var timeoutId;
      try {
        controller = new AbortController();
        timeoutId = setTimeout(function () { controller.abort(); }, LIST_TIMEOUT_MS);
      } catch (_) {
        // AbortController not available in some edge environments — degrade.
        resolve([]);
        return;
      }

      fetch(RAG_BASE + '/rag/list-workspaces', { signal: controller.signal })
        .then(function (resp) {
          clearTimeout(timeoutId);
          if (!resp.ok) throw new Error('HTTP ' + resp.status);
          return resp.json();
        })
        .then(function (data) {
          var workspaces = (data && Array.isArray(data.workspaces)) ? data.workspaces : [];
          resolve(workspaces);
        })
        .catch(function (err) {
          clearTimeout(timeoutId);
          console.warn(LOG_PREFIX + ' /rag/list-workspaces fetch failed (non-fatal):', err.message || err);
          resolve([]);
        });
    });
  }

  // ── localStorage helpers ───────────────────────────────────────────────────

  function readStoredWorkspace() {
    try {
      return localStorage.getItem(WORKSPACE_KEY) || DEFAULT_WORKSPACE;
    } catch (_) {
      return DEFAULT_WORKSPACE;
    }
  }

  function writeStoredWorkspace(name) {
    try {
      localStorage.setItem(WORKSPACE_KEY, name);
    } catch (err) {
      console.warn(LOG_PREFIX + ' localStorage write failed (non-fatal):', err);
    }
  }

  // ── Dropdown build ─────────────────────────────────────────────────────────

  /**
   * Build the <option> list from the API response.
   * Always includes `default` as the first option (even on empty response).
   * Subsequent entries are taken from the API, de-duped against `default`.
   * Each shows: "name (N docs)".
   */
  function buildOptions(workspaces, currentName) {
    // Start with an explicit default option.
    var options = [{ name: DEFAULT_WORKSPACE, docs: null, chunks: null }];

    if (Array.isArray(workspaces)) {
      workspaces.forEach(function (ws) {
        if (ws && typeof ws.name === 'string' && ws.name !== DEFAULT_WORKSPACE) {
          options.push(ws);
        }
      });
    }

    return options.map(function (ws) {
      var opt = document.createElement('option');
      opt.value = ws.name;
      var docCount = (ws.docs != null) ? ws.docs : null;
      opt.textContent = docCount != null
        ? ws.name + ' (' + docCount + ' docs)'
        : ws.name;
      if (ws.name === currentName) opt.selected = true;
      return opt;
    });
  }

  // ── Dropdown injection ─────────────────────────────────────────────────────

  /**
   * Build and insert the workspace wrapper into the DOM.
   * parentEl: the element to insert before (anchor mode) or prepend into
   *           (sidebar / body fallback modes).
   * placement: 'anchor' | 'sidebar' | 'body'
   * options:   array of <option> elements to populate the <select>
   */
  function injectDropdown(parentEl, placement, options) {
    // Guard: never inject twice.
    if (document.querySelector('.doomstick-workspace-dropdown')) return;

    try {
      var wrapper = document.createElement('div');
      wrapper.className = 'doomstick-workspace-wrapper';

      var label = document.createElement('label');
      label.className = 'doomstick-workspace-label';
      label.setAttribute('for', 'doomstick-workspace-select');
      label.textContent = 'Workspace';

      var select = document.createElement('select');
      select.id = 'doomstick-workspace-select';
      select.className = 'doomstick-workspace-dropdown';
      select.setAttribute('aria-label', 'RAG workspace selector');

      options.forEach(function (opt) { select.appendChild(opt); });

      wrapper.appendChild(label);
      wrapper.appendChild(select);

      // All placement modes: prepend the wrapper as the first child of parentEl.
      // For 'anchor' this puts it above the model picker block; for 'sidebar'
      // and 'body' it puts it at the top of the fallback container.
      parentEl.insertBefore(wrapper, parentEl.firstChild);

      console.log(LOG_PREFIX + ' workspace dropdown injected (placement: ' + placement + ')');

      // Wire the change handler after the element is in the DOM.
      select.addEventListener('change', function () {
        var newWorkspace = select.value;
        writeStoredWorkspace(newWorkspace);
        console.log(LOG_PREFIX + ' workspace changed to:', newWorkspace);
        try {
          window.dispatchEvent(new CustomEvent(WORKSPACE_CHANGE_EVENT, {
            detail: { workspace: newWorkspace }
          }));
        } catch (evtErr) {
          console.warn(LOG_PREFIX + ' workspace-changed event dispatch failed (non-fatal):', evtErr);
        }
      });

    } catch (domErr) {
      console.error(LOG_PREFIX + ' dropdown injection failed (non-fatal):', domErr);
    }
  }

  // ── Boot sequence ──────────────────────────────────────────────────────────

  function run() {
    injectStyles();

    var currentWorkspace = readStoredWorkspace();

    // Fetch workspace list and wait for the DOM anchor in parallel so the
    // dropdown appears as soon as both are ready (whichever is slower wins).
    var workspacesReady = fetchWorkspaces();

    whenAnchorReady(function (parentEl, placement) {
      workspacesReady.then(function (workspaces) {
        // If API returned no workspaces (fresh kit / redbean down), the
        // buildOptions function still ensures `default` is present.
        var opts = buildOptions(workspaces, currentWorkspace);
        injectDropdown(parentEl, placement, opts);
      }).catch(function (err) {
        // fetchWorkspaces resolves (never rejects), but guard defensively.
        console.warn(LOG_PREFIX + ' unexpected workspace fetch error (non-fatal):', err);
        var opts = buildOptions([], currentWorkspace);
        injectDropdown(parentEl, placement, opts);
      });
    });
  }

  // Run immediately if document is already parsed, otherwise wait for
  // DOMContentLoaded. The "defer" attribute should guarantee the DOM is
  // ready, but this guard makes the script safe if loaded any other way.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }

}());
