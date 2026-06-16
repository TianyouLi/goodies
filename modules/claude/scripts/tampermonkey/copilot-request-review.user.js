// ==UserScript==
// @name         goodies: Copilot auto-request-review
// @namespace    https://github.com/TianyouLi/goodies
// @version      0.4.0
// @description  Detect a new push on the open PR tab (no refresh needed) and click the Copilot reviewer's "Re-request review" button — but ONLY if GitHub's own auto-trigger doesn't fire within 10s. Multi-tab coordinated via localStorage. Strict-scoped to GitHub PR pages. Includes a per-tab status panel with action log + copy-to-clipboard for bug reports.
// @author       TianyouLi (with Claude)
// @match        https://github.com/*/*/pull/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    // === Why this script exists =============================================
    // Some GitHub repos (notably org-managed ones with branch protection
    // policies) disable the rule that auto-triggers Copilot code review on
    // push. In those repos the user has to manually click "Re-request
    // review" on the Copilot reviewer in the PR's sidebar after every
    // push. This script does that click automatically — but only when the
    // automatic trigger isn't already doing the job.
    //
    // Detection: a MutationObserver on the PR's timeline catches "push"
    // entries when they appear. After detection, the script enters a 10s
    // observation window during which it watches whether GitHub's auto-
    // trigger fires (Copilot's status flips to "reviewing" or similar). If
    // it does, the script does nothing — auto-trigger handled it. If 10s
    // pass with no state change, the script clicks the request-review
    // button.
    //
    // Multi-tab: cross-tab coordination via localStorage. When one tab
    // clicks (or detects auto-trigger), it broadcasts a per-PR marker;
    // sibling tabs observing the same PR see the marker and skip.
    //
    // Strict scope: this script targets ONLY github.com PR pages. Defense
    // in depth at three levels: @match metadata, hostname guard, and a
    // strict path regex. We refuse to fall back to observing
    // document.body if timeline selectors fail — silent no-op is safer
    // than ambient DOM-watching that might fire spuriously.
    //
    // Companion tooling: goodies-watch's force-push retry rule was a
    // workaround for missing trigger; with this script installed that
    // rule becomes unnecessary. See feedback_copilot_review_manual_trigger
    // and project_tampermonkey_copilot_trigger memories for context.

    // === Tunables ===========================================================
    const LOG_PREFIX = '[goodies/copilot-request-review]';

    // Visible text on the request-review button. Match these against the
    // button's textContent (case-insensitive). Update if GitHub changes
    // the wording.
    const REQUEST_BUTTON_TEXTS = [
        're-request review',
        'request review',
    ];

    // Substring (case-insensitive) we look for in the surrounding DOM to
    // confirm the button belongs to the Copilot reviewer (not a generic
    // request-review button for the whole PR).
    const COPILOT_HINT = 'copilot';

    // Visible push-event markers in the PR timeline. When the timeline
    // observer sees a new node whose text matches one of these patterns,
    // we treat it as "push detected".
    //
    // CRITICAL: these are intentionally tight to match GitHub's *actual*
    // push-event timeline wording — "force-pushed" or "pushed <N>
    // commit/commits". A loose substring match for "pushed" alone would
    // false-trigger on regular comments that happen to contain the word
    // (e.g. someone writing "I pushed my changes earlier"), which would
    // start the observation window and potentially click the review-
    // request button on an unrelated comment. Maintenance: if GitHub
    // changes the timeline wording, update these regexes.
    const PUSH_MARKERS = [
        /force-pushed\b/i,
        /pushed \d+ commit/i,           // "pushed 1 commit", "pushed 3 commits"
        /pushed a commit/i,             // GitHub's singular variant on some pages
    ];

    // Visible markers indicating Copilot is *already* reviewing or has
    // just submitted a review. Match against the Copilot reviewer's row
    // text (case-insensitive). When any of these is present, we skip the
    // click — GitHub's auto-trigger fired, or a recent review is in
    // place.
    const COPILOT_BUSY_MARKERS = [
        'review pending',
        'reviewing',
        'review in progress',
        'approved',
        'commented',
        'requested changes',
    ];

    // Debounce: a single push can produce several DOM updates as the
    // timeline expands. Wait this long after the last detected mutation
    // before acting.
    const PUSH_DEBOUNCE_MS = 1500;

    // Auto-trigger observation window. After push detection, watch for
    // up to this long to see if GitHub's auto-trigger fires (Copilot's
    // state flips to "reviewing"). If it does within the window, skip
    // the click. If the window expires unchanged, click. 10s is the
    // sweet spot: most auto-triggers fire within 5s; 10s gives margin
    // without making the off-trigger case painfully slow.
    const AUTO_TRIGGER_WINDOW_MS = 10000;

    // After clicking (or observing auto-trigger), how long this tab
    // claims the lock and other tabs skip. 30s covers GitHub's eventual-
    // consistency delay between tabs.
    const CROSS_TAB_LOCK_TTL_MS = 30000;

    // === Persistent action log (Layer A observability) =====================
    // The script writes a rolling log of every notable action / decision to
    // localStorage. When the user reports "the script seems broken," the
    // log is the evidence trail: open DevTools, call
    // `window.__goodiesActionLog({asText: true})`, copy the output. No
    // mind-reading required.
    //
    // Ring buffer of LOG_MAX_ENTRIES entries; older drops off the back.
    // ~100 entries × ~200 bytes = ~20KB localStorage worst case. localStorage
    // limit per origin is ~5MB; 20KB is negligible.
    //
    // Global, not per-PR — when the user investigates a failure they often
    // don't know which PR it happened on, only "around the time I pushed".
    // Each entry includes the URL, so cross-PR context is preserved.
    const LOG_KEY = 'goodies-userscript:actionlog';
    const LOG_MAX_ENTRIES = 100;

    // Verbose logging on by default during the dogfood phase. Flip to
    // false once trusted.
    const VERBOSE = true;
    const log = (...args) => VERBOSE && console.log(LOG_PREFIX, ...args);
    const warn = (...args) => console.warn(LOG_PREFIX, ...args);

    // === Action log: persistent ring buffer ================================
    // Forward declaration: the per-tab status panel registers a callback
    // here so it can refresh its log view on every appendLog. Declared
    // before appendLog so it's defined by the time any code runs.
    let panelLogCallback = null;

    function readLogRaw() {
        try {
            const raw = localStorage.getItem(LOG_KEY);
            if (!raw) return [];
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed : [];
        } catch (_) {
            return [];
        }
    }

    function appendLog(event, detail) {
        // event: short string from a known set (see EVENT_KINDS comment).
        // detail: small object with event-specific fields (regex match,
        //   button found?, error message, etc.). Keep terse — this lands
        //   in localStorage on every state transition.
        try {
            const entry = {
                at: new Date().toISOString(),
                tab_id: TAB_ID,
                url: location.href,
                event,
                detail: detail || {},
            };
            const buf = readLogRaw();
            buf.push(entry);
            // Trim to ring-buffer size, dropping oldest.
            const start = Math.max(0, buf.length - LOG_MAX_ENTRIES);
            const trimmed = buf.slice(start);
            localStorage.setItem(LOG_KEY, JSON.stringify(trimmed));
            // Notify the per-tab panel so it can refresh its log view.
            if (panelLogCallback) {
                try { panelLogCallback(entry); } catch (_) { /* never break main path */ }
            }
        } catch (e) {
            // Logging failure must never break the main action path.
            warn('appendLog failed (storage full or disabled?):', e);
        }
    }

    // Known event kinds (for documentation; not enforced at runtime):
    //   script-loaded         — script initialized on a PR page
    //   nav-detected          — SPA navigation handler fired
    //   push-detected         — timeline observer matched a push regex
    //   obs-window-open       — auto-trigger observation window started
    //   obs-window-expired    — observation window finished without state change
    //   auto-trigger-fired    — observed Copilot busy state during the window
    //   click-attempted       — clicked the request-review button
    //   click-skipped-busy    — Copilot already busy, no click
    //   click-skipped-locked  — sibling tab already acted, no click
    //   click-skipped-no-button — no Copilot request-review button found
    //   click-skipped-disabled  — button found but disabled/hidden
    //   sibling-tab-acted     — storage event from another tab
    //   selector-failed       — TIMELINE_SELECTORS chain didn't match
    //   error                 — exception caught somewhere
    //
    // Future maintenance: when adding a new state transition or failure
    // path, append a one-liner here AND a corresponding appendLog() call.

    // Expose retrieval to the user. Two flavors:
    //   window.__goodiesActionLog()              → raw array
    //   window.__goodiesActionLog({asText: true}) → pre-formatted multi-line text
    try {
        Object.defineProperty(window, '__goodiesActionLog', {
            value: function (opts) {
                const buf = readLogRaw();
                if (opts && opts.asText) {
                    return buf.map(e =>
                        `${e.at}  ${e.event.padEnd(24)}  ${e.url}  ${JSON.stringify(e.detail)}`
                    ).join('\n');
                }
                return buf;
            },
            writable: false,
            configurable: true,
        });
    } catch (_) {
        // If `window.__goodiesActionLog` already exists from a prior
        // load, leave it alone — last-loaded version of the script wins
        // implicitly via the buffer, and the log function works either way.
    }

    // === Strict scope: hostname + path guards ===============================
    // The @match in the metadata block is the primary gate, but
    // belt-and-suspenders. If somehow this script runs on a non-github.com
    // page, refuse to operate.
    if (location.hostname !== 'github.com') {
        warn('hostname is not github.com (got "' + location.hostname +
             '"); refusing to run. This script is strictly-scoped to public github.com.');
        return;
    }

    // Strict PR path regex: <owner>/<repo>/pull/<num>(/<sub-route>)?
    // Three path components ending in /pull/<num>, optionally followed
    // by /files, /commits, /checks, etc.
    const PR_PATH_REGEX = /^\/[^/]+\/[^/]+\/pull\/\d+(?:\/|$)/;

    function isOnPRPage() {
        return PR_PATH_REGEX.test(location.pathname);
    }

    // === Per-tab identity (for cross-tab coordination) ======================
    // Random ID generated once per tab session. Used to distinguish "this
    // tab clicked" from "another tab clicked" in the cross-tab lock.
    const TAB_ID = (() => {
        try {
            // Math.random instead of crypto.randomUUID for broader compat.
            return 'tab-' + Math.random().toString(36).slice(2, 10) +
                   '-' + Date.now().toString(36);
        } catch (e) {
            return 'tab-fallback';
        }
    })();
    log('tab id:', TAB_ID);

    // === Cross-tab lock via localStorage =====================================
    // Key shape: goodies-userscript:<owner>/<repo>#<PR>:lock
    // Value: JSON {tabId, action, at} where action ∈ {clicked, auto-trigger-fired}
    function lockKey() {
        const m = location.pathname.match(/^\/([^/]+\/[^/]+)\/pull\/(\d+)/);
        if (!m) return null;
        return `goodies-userscript:${m[1]}#${m[2]}:lock`;
    }

    function readLock() {
        const key = lockKey();
        if (!key) return null;
        try {
            const raw = localStorage.getItem(key);
            if (!raw) return null;
            const parsed = JSON.parse(raw);
            if (Date.now() - (parsed.at || 0) > CROSS_TAB_LOCK_TTL_MS) {
                // Stale; clean up so localStorage doesn't accumulate one
                // entry per PR visited over time.
                try { localStorage.removeItem(key); } catch (_) {}
                return null;
            }
            return parsed;
        } catch (e) {
            return null;
        }
    }

    function writeLock(action) {
        const key = lockKey();
        if (!key) return;
        try {
            const value = JSON.stringify({tabId: TAB_ID, action, at: Date.now()});
            localStorage.setItem(key, value);
            log('cross-tab lock written:', action);
        } catch (e) {
            warn('failed to write cross-tab lock (storage full or disabled?):', e);
        }
    }

    // Listen for sibling tabs writing the lock — cancel any pending
    // observation window because they handled it.
    window.addEventListener('storage', (e) => {
        if (e.key !== lockKey() || !e.newValue) return;
        try {
            const parsed = JSON.parse(e.newValue);
            if (parsed.tabId === TAB_ID) return;  // our own write
            log('sibling tab acted on this PR (' + parsed.action + '); cancelling local observation');
            appendLog('sibling-tab-acted', {by_tab: parsed.tabId, action: parsed.action});
            cancelPendingObservation();
            flashIndicator(`Another tab handled this (${parsed.action})`, 'gray');
        } catch (_) {
            // ignore
        }
    });

    // === Find the request-review button + read Copilot state ================
    function findCopilotReviewerRow() {
        // Iterate buttons / role-button anchors / summary elements whose
        // visible text matches a request-review marker. For the first
        // such match, walk up to 6 ancestors looking for the literal
        // "copilot" substring; return the first match. We do NOT score
        // ancestors by depth or subtree size — the first ancestor that
        // mentions "copilot" wins. The heuristic relies on visible text
        // proximity rather than specific class names because GitHub's
        // class names churn.

        const candidates = Array.from(
            document.querySelectorAll('button, a[role="button"], summary')
        );

        for (const el of candidates) {
            const text = (el.textContent || '').trim().toLowerCase();
            if (!text) continue;
            if (!REQUEST_BUTTON_TEXTS.some(p => text.includes(p))) continue;

            // Walk up to ~6 ancestors looking for the reviewer's login.
            let node = el;
            for (let depth = 0; depth < 6 && node; depth++) {
                const surrounding = (node.textContent || '').toLowerCase();
                if (surrounding.includes(COPILOT_HINT)) {
                    return {button: el, row: node};
                }
                node = node.parentElement;
            }
        }
        return null;
    }

    // Sidebar selectors used to scope the busy-state scan. PR sidebar
    // historically lives under one of these roots; we try each in order
    // and fall back to `document` if none matches. Scoped scanning keeps
    // the per-second poll cheap (the PR sidebar has tens of nodes; the
    // whole document has thousands).
    const SIDEBAR_SELECTORS = [
        '[aria-label="Reviewers"]',           // GitHub sometimes labels the section
        '.discussion-sidebar',                 // legacy class
        '#partial-discussion-sidebar',         // older container id
        'aside',                               // generic sidebar role
    ];

    function findSidebarRoot() {
        for (const sel of SIDEBAR_SELECTORS) {
            const node = document.querySelector(sel);
            if (node) return node;
        }
        return null;  // signals fall-back to whole-document search
    }

    function isCopilotBusy() {
        // Look for any Copilot-row element whose text mentions a "busy"
        // marker. We find the row by text search since we don't have
        // stable class names — find any node containing "copilot" and
        // check its text for busy markers.
        //
        // Scope: prefer the PR sidebar (where reviewer-rows live) so
        // the scan stays cheap during the per-second poll. Fall back
        // to whole-document if no sidebar selector matches.
        //
        // Heuristic: find <li> or <div> or <span> elements whose text
        // mentions "copilot" and is short (under 300 chars — long enough
        // for "Copilot · Review pending · Re-request review" but short
        // enough to exclude page-wide containers).

        const root = findSidebarRoot() || document;
        const allElements = root.querySelectorAll('li, div, span');
        for (const el of allElements) {
            const text = (el.textContent || '').toLowerCase().trim();
            if (text.length === 0 || text.length > 300) continue;
            if (!text.includes(COPILOT_HINT)) continue;
            // The element's text mentions copilot and is short — likely
            // a reviewer row. Check for busy markers.
            for (const marker of COPILOT_BUSY_MARKERS) {
                if (text.includes(marker)) {
                    return {busy: true, marker, snippet: text.slice(0, 120)};
                }
            }
        }
        return {busy: false};
    }

    function shouldClick(button) {
        if (button.disabled) return false;
        if (button.getAttribute('aria-disabled') === 'true') return false;
        const rect = button.getBoundingClientRect();
        // Either dimension being zero means the element isn't visibly
        // clickable. Using `||` (not `&&`): a button that's been
        // collapsed to width 0 but still has height (or vice versa) is
        // not in a state where we should click it.
        if (rect.width === 0 || rect.height === 0) return false;
        return true;
    }

    // === Action with auto-trigger awareness =================================
    let pendingObservation = null;  // {timer, startedAt}

    function cancelPendingObservation() {
        if (pendingObservation) {
            clearTimeout(pendingObservation.timer);
            if (pendingObservation.poller) clearInterval(pendingObservation.poller);
            pendingObservation = null;
        }
    }

    function maybeRequestCopilotReview(reason) {
        // Cross-tab lock check — sibling tab beat us to it.
        // CRITICAL: only skip when the lock was written by a *different*
        // tab. Skipping on our own lock would mean: this tab clicks at
        // T=0 → writeLock('clicked') → second push lands at T=10s within
        // the 30s TTL → readLock() returns our own entry → this tab
        // skips, missing a legitimate re-trigger. The lock's purpose is
        // to deduplicate ACROSS tabs, never to suppress within-tab.
        const lock = readLock();
        if (lock && lock.tabId !== TAB_ID) {
            log('cross-tab lock present (' + lock.action + ' by ' + lock.tabId + '); skipping (reason was: ' + reason + ')');
            appendLog('click-skipped-locked', {reason, locked_by: lock.tabId, locked_action: lock.action});
            return;
        }

        // Already-busy check — Copilot is reviewing or has just reviewed.
        const busy = isCopilotBusy();
        if (busy.busy) {
            log('Copilot already busy (' + busy.marker + '); skipping (reason: ' + reason + ')');
            appendLog('click-skipped-busy', {reason, marker: busy.marker, snippet: busy.snippet});
            writeLock('auto-trigger-fired');  // tell siblings
            setTabStatus('green', 'observed-busy', 'Copilot already on it (' + busy.marker + ')');
            flashIndicator(`Copilot already on it (${busy.marker})`, 'gray');
            return;
        }

        // Reason-specific handling.
        if (reason === 'push detected in timeline') {
            // Don't click immediately; start the auto-trigger observation
            // window. If GitHub's own trigger fires within the window,
            // skip the click.
            startAutoTriggerObservation();
            return;
        }

        // For initial-load or SPA-navigation reasons, no auto-trigger
        // window — just check state and click if appropriate.
        performClick(reason);
    }

    function startAutoTriggerObservation() {
        if (pendingObservation) {
            log('observation window already active; ignoring duplicate trigger');
            return;
        }
        log('push detected; opening ' + AUTO_TRIGGER_WINDOW_MS +
            'ms observation window for GitHub auto-trigger');
        appendLog('obs-window-open', {window_ms: AUTO_TRIGGER_WINDOW_MS});
        setTabStatus('green', 'observing', 'auto-trigger window open');

        const startedAt = Date.now();
        // Poll Copilot state every 1s during the window.
        // Note: do NOT log per-poll — that would add ~10 entries per push
        // to the ring buffer for the boring middle. Log start (above) +
        // end (below; either auto-trigger-fired or obs-window-expired).
        const poller = setInterval(() => {
            const busy = isCopilotBusy();
            if (busy.busy) {
                const elapsedMs = Date.now() - startedAt;
                log('auto-trigger fired during observation window (' +
                    busy.marker + ' at +' + elapsedMs + 'ms); no click needed');
                appendLog('auto-trigger-fired', {marker: busy.marker, elapsed_ms: elapsedMs});
                cancelPendingObservation();
                writeLock('auto-trigger-fired');
                setTabStatus('green', 'auto-trigger-fired',
                    'GitHub fired auto-trigger; script correctly stayed out of the way');
                flashIndicator(`Auto-trigger fired (${busy.marker})`, 'gray');
            }
        }, 1000);

        const timer = setTimeout(() => {
            log('observation window expired with no auto-trigger; clicking now');
            appendLog('obs-window-expired', {window_ms: AUTO_TRIGGER_WINDOW_MS});
            cancelPendingObservation();
            performClick('observation window expired');
        }, AUTO_TRIGGER_WINDOW_MS);

        pendingObservation = {timer, poller, startedAt};
    }

    function performClick(reason) {
        const found = findCopilotReviewerRow();
        if (!found) {
            log('no Copilot request-review button found (reason: ' + reason +
                '). Possible: Copilot not in reviewers, button hidden, PR closed.');
            appendLog('click-skipped-no-button', {reason});
            // We were supposed to act and couldn't find the target. On the
            // common case (PRs with Copilot in the reviewers), this is a
            // real failure — selector stale or DOM shape changed. Surface
            // red. Edge case (Copilot not in this PR's reviewers) reads as
            // a false positive but is rare enough that flagging it is the
            // right default.
            setTabStatus('red', 'no-button-found',
                'expected to act but no Copilot request-review button found');
            return;
        }
        if (!shouldClick(found.button)) {
            log('button found but disabled/hidden (reason: ' + reason + ')');
            appendLog('click-skipped-disabled', {reason});
            setTabStatus('red', 'button-unclickable',
                'request-review button found but disabled/hidden');
            return;
        }
        log('clicking Copilot request-review button (reason: ' + reason + ')');
        appendLog('click-attempted', {reason});
        found.button.click();
        writeLock('clicked');
        setTabStatus('green', 'clicked', 'review requested');
        flashIndicator('Copilot review requested', 'green');
    }

    // === Visible toast ======================================================
    function flashIndicator(message, color) {
        // color ∈ "green" (action taken) | "gray" (informational, no action)
        try {
            const existing = document.getElementById('goodies-userscript-toast');
            if (existing) existing.remove();
            const toast = document.createElement('div');
            toast.id = 'goodies-userscript-toast';
            toast.textContent = `${LOG_PREFIX} ${message}`;
            const bg = color === 'gray' ? '#6e7781' : '#1f883d';
            Object.assign(toast.style, {
                position: 'fixed',
                top: '12px',
                right: '12px',
                zIndex: '99999',
                background: bg,
                color: 'white',
                padding: '8px 12px',
                borderRadius: '6px',
                fontFamily: 'system-ui, sans-serif',
                fontSize: '13px',
                boxShadow: '0 2px 6px rgba(0,0,0,0.2)',
                pointerEvents: 'none',
            });
            document.body.appendChild(toast);
            setTimeout(() => toast.remove(), 3000);
        } catch (e) {
            warn('toast failed (script still ran):', e);
        }
    }

    // === Per-tab status panel ==============================================
    // Persistent UI element in the bottom-right corner showing THIS tab's
    // status (a colored dot) and, when expanded, this tab's filtered log
    // + a "Copy log" button. Strictly per-tab — the dot's color reflects
    // this tab's in-memory state machine, not the cross-tab localStorage
    // mix; the log view filters to entries with tab_id === TAB_ID.
    //
    // Two colors only — green = working as designed, red = NOT doing its
    // job (selector-failed, button missing, exception). No yellow/gray:
    // intermediate states papered over real failures, which would invite
    // the user to ignore them.

    const PANEL_DOT_ID = 'goodies-userscript-status-dot';
    const PANEL_BODY_ID = 'goodies-userscript-status-panel';
    const PANEL_LOG_VISIBLE = 15;            // most recent N entries shown
    const SCRIPT_VERSION_FOR_REPORT = '0.4.0';

    // In-memory tab status. Source of truth for the dot's color.
    // tabStatus.color ∈ "green" | "red"; .label is a short state name;
    // .detail is optional human-readable extra context.
    let tabStatus = {color: 'green', label: 'loaded', detail: ''};

    function setTabStatus(color, label, detail) {
        tabStatus = {color, label, detail: detail || ''};
        updatePanelDot();
        if (panelExpanded) refreshPanelStatus();
    }

    let panelExpanded = false;
    let panelDotEl = null;
    let panelBodyEl = null;
    let panelStatusSectionEl = null;
    let panelLogListEl = null;

    function ensurePanelElements() {
        if (panelDotEl && document.body && document.body.contains(panelDotEl)) return;
        if (!document.body) return;  // page not ready; init() will retry

        // The dot — always visible, position-fixed.
        panelDotEl = document.createElement('div');
        panelDotEl.id = PANEL_DOT_ID;
        Object.assign(panelDotEl.style, {
            position: 'fixed',
            bottom: '12px',
            right: '12px',
            width: '14px',
            height: '14px',
            borderRadius: '50%',
            background: '#1f883d',
            boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
            cursor: 'pointer',
            zIndex: '99998',                      // below the toast (99999)
        });
        panelDotEl.title = 'goodies userscript: working';
        panelDotEl.addEventListener('click', togglePanel);
        document.body.appendChild(panelDotEl);

        // The panel body — hidden by default; click the dot to expand.
        panelBodyEl = document.createElement('div');
        panelBodyEl.id = PANEL_BODY_ID;
        Object.assign(panelBodyEl.style, {
            position: 'fixed',
            bottom: '32px',
            right: '12px',
            width: '360px',
            maxHeight: '420px',
            background: 'white',
            color: '#24292f',
            border: '1px solid #d0d7de',
            borderRadius: '6px',
            boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
            fontFamily: 'system-ui, sans-serif',
            fontSize: '12px',
            zIndex: '99998',
            display: 'none',
            flexDirection: 'column',
            overflow: 'hidden',
        });

        // Header
        const header = document.createElement('div');
        Object.assign(header.style, {
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            padding: '8px 12px',
            background: '#f6f8fa',
            borderBottom: '1px solid #d0d7de',
        });
        const headerTitle = document.createElement('div');
        headerTitle.style.fontWeight = '600';
        headerTitle.textContent = 'goodies userscript';
        const headerClose = document.createElement('div');
        headerClose.textContent = '×';
        Object.assign(headerClose.style, {
            cursor: 'pointer',
            fontSize: '18px',
            lineHeight: '1',
            padding: '0 4px',
            userSelect: 'none',
        });
        headerClose.addEventListener('click', () => setPanelExpanded(false));
        header.appendChild(headerTitle);
        header.appendChild(headerClose);
        panelBodyEl.appendChild(header);

        // Status section (this tab's color + label + detail + tab id)
        panelStatusSectionEl = document.createElement('div');
        Object.assign(panelStatusSectionEl.style, {
            padding: '8px 12px',
            borderBottom: '1px solid #d0d7de',
        });
        panelBodyEl.appendChild(panelStatusSectionEl);

        // Log list section (this tab's filtered, most-recent N entries)
        panelLogListEl = document.createElement('div');
        Object.assign(panelLogListEl.style, {
            flex: '1 1 auto',
            overflow: 'auto',
            padding: '8px 12px',
            fontFamily: 'ui-monospace, monospace',
            fontSize: '11px',
            lineHeight: '1.4',
        });
        panelBodyEl.appendChild(panelLogListEl);

        // Footer with copy + clear buttons
        const footer = document.createElement('div');
        Object.assign(footer.style, {
            display: 'flex',
            gap: '8px',
            padding: '8px 12px',
            borderTop: '1px solid #d0d7de',
            background: '#f6f8fa',
        });
        const copyBtn = makePanelButton('Copy log');
        copyBtn.style.flex = '1';
        copyBtn.addEventListener('click', () => copyTabLog(copyBtn));
        const clearBtn = makePanelButton('Clear log');
        clearBtn.addEventListener('click', clearTabLog);
        footer.appendChild(copyBtn);
        footer.appendChild(clearBtn);
        panelBodyEl.appendChild(footer);

        document.body.appendChild(panelBodyEl);

        // Wire the action-log → panel-refresh callback (declared near
        // appendLog so it could forward-reference this function).
        panelLogCallback = () => { if (panelExpanded) refreshPanelLog(); };
    }

    function makePanelButton(text) {
        const btn = document.createElement('button');
        btn.textContent = text;
        Object.assign(btn.style, {
            padding: '6px 12px',
            border: '1px solid #d0d7de',
            borderRadius: '6px',
            background: 'white',
            cursor: 'pointer',
            fontSize: '12px',
            fontFamily: 'inherit',
        });
        return btn;
    }

    function setPanelExpanded(expanded) {
        panelExpanded = expanded;
        if (panelBodyEl) panelBodyEl.style.display = expanded ? 'flex' : 'none';
        if (expanded) {
            refreshPanelStatus();
            refreshPanelLog();
        }
    }

    function togglePanel() { setPanelExpanded(!panelExpanded); }

    function updatePanelDot() {
        if (!panelDotEl) return;
        const bg = tabStatus.color === 'red' ? '#cf222e' : '#1f883d';
        panelDotEl.style.background = bg;
        panelDotEl.title =
            'goodies userscript: ' + tabStatus.label +
            (tabStatus.detail ? ' (' + tabStatus.detail + ')' : '');
    }

    function refreshPanelStatus() {
        if (!panelStatusSectionEl) return;
        panelStatusSectionEl.innerHTML = '';

        const headline = tabStatus.color === 'red' ? 'NOT WORKING' : 'OK';
        const dotColor = tabStatus.color === 'red' ? '#cf222e' : '#1f883d';

        const row = document.createElement('div');
        Object.assign(row.style, {
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
        });

        const inlineDot = document.createElement('span');
        Object.assign(inlineDot.style, {
            display: 'inline-block',
            width: '10px',
            height: '10px',
            borderRadius: '50%',
            background: dotColor,
        });
        const headlineEl = document.createElement('span');
        headlineEl.style.fontWeight = '600';
        headlineEl.textContent = headline + ' — ' + tabStatus.label;
        row.appendChild(inlineDot);
        row.appendChild(headlineEl);
        panelStatusSectionEl.appendChild(row);

        if (tabStatus.detail) {
            const detail = document.createElement('div');
            Object.assign(detail.style, {
                color: '#57606a',
                marginTop: '4px',
                fontSize: '11px',
            });
            detail.textContent = tabStatus.detail;
            panelStatusSectionEl.appendChild(detail);
        }

        const tabIdLine = document.createElement('div');
        Object.assign(tabIdLine.style, {
            color: '#57606a',
            marginTop: '4px',
            fontFamily: 'ui-monospace, monospace',
            fontSize: '11px',
        });
        tabIdLine.textContent = 'tab: ' + TAB_ID;
        panelStatusSectionEl.appendChild(tabIdLine);
    }

    function getTabFilteredLog() {
        // Per-tab filtering — the panel UI must NEVER show another tab's
        // history (confusing the user about which tab failed). The
        // cross-tab view is deliberately reserved for the rare DevTools
        // path: window.__goodiesActionLog().
        const buf = readLogRaw();
        return buf.filter(e => e.tab_id === TAB_ID);
    }

    function refreshPanelLog() {
        if (!panelLogListEl) return;
        const entries = getTabFilteredLog().slice(-PANEL_LOG_VISIBLE).reverse();
        panelLogListEl.innerHTML = '';
        if (entries.length === 0) {
            const empty = document.createElement('div');
            empty.style.color = '#57606a';
            empty.textContent = '(no log entries for this tab yet)';
            panelLogListEl.appendChild(empty);
            return;
        }
        for (const e of entries) {
            const row = document.createElement('div');
            row.style.marginBottom = '4px';
            const time = document.createElement('span');
            time.style.color = '#57606a';
            time.textContent = e.at.slice(11, 19) + ' ';
            const evt = document.createElement('span');
            evt.style.fontWeight = '600';
            evt.textContent = e.event;
            const det = document.createElement('div');
            Object.assign(det.style, {
                color: '#57606a',
                marginLeft: '12px',
                wordBreak: 'break-word',
            });
            det.textContent = JSON.stringify(e.detail);
            row.appendChild(time);
            row.appendChild(evt);
            row.appendChild(det);
            panelLogListEl.appendChild(row);
        }
    }

    function formatTabLogAsText() {
        const entries = getTabFilteredLog();
        const header =
            'goodies userscript log\n' +
            'script: ' + SCRIPT_VERSION_FOR_REPORT + '\n' +
            'tab: ' + TAB_ID + '\n' +
            'url: ' + location.href + '\n' +
            'entries: ' + entries.length + '\n' +
            'status: ' + tabStatus.color + ' (' + tabStatus.label + ')' +
              (tabStatus.detail ? ' — ' + tabStatus.detail : '') + '\n' +
            '---\n';
        const body = entries.map(e =>
            e.at + '  ' + e.event.padEnd(24) + '  ' + e.url + '  ' +
            JSON.stringify(e.detail)
        ).join('\n');
        return header + body + (body ? '\n' : '');
    }

    async function copyTabLog(btn) {
        const text = formatTabLogAsText();
        let ok = false;
        try {
            await navigator.clipboard.writeText(text);
            ok = true;
        } catch (e) {
            // Clipboard API can fail in older browsers, when the page
            // isn't focused, or under restrictive permission policies.
            // Fall back to the legacy textarea + execCommand approach.
            try {
                const ta = document.createElement('textarea');
                ta.value = text;
                Object.assign(ta.style, {
                    position: 'fixed',
                    left: '-9999px',
                    top: '0',
                });
                document.body.appendChild(ta);
                ta.select();
                ok = document.execCommand('copy');
                ta.remove();
            } catch (_) { ok = false; }
        }
        const orig = btn.textContent;
        btn.textContent = ok ? 'Copied!' : 'Copy failed';
        btn.style.background = ok ? '#dafbe1' : '#ffebe9';
        setTimeout(() => {
            btn.textContent = orig;
            btn.style.background = 'white';
        }, 1500);
    }

    function clearTabLog() {
        // Remove only this tab's entries. Other tabs' history is
        // preserved — clearing one tab must never affect another.
        try {
            const buf = readLogRaw();
            const remaining = buf.filter(e => e.tab_id !== TAB_ID);
            localStorage.setItem(LOG_KEY, JSON.stringify(remaining));
        } catch (_) {}
        refreshPanelLog();
    }

    // === Push detection via timeline MutationObserver =======================
    // Try a list of historical timeline-container selectors. Use the first
    // that matches. Critically: do NOT fall back to document.body — that
    // would observe the entire page and risk false-positive matches on
    // unrelated DOM mutations. If all selectors fail, log a maintenance
    // warning and become a no-op for push-detection (initial-load and
    // SPA-nav paths still work).

    const TIMELINE_SELECTORS = [
        '#discussion_bucket',          // turbo-frame around the timeline
        '.js-discussion',              // legacy class
        'main',                        // PR main content area
    ];

    function findTimelineNode() {
        for (const sel of TIMELINE_SELECTORS) {
            const node = document.querySelector(sel);
            if (node) {
                log('observing timeline via selector:', sel);
                return {node, selector: sel};
            }
        }
        warn('no timeline selector matched (' + TIMELINE_SELECTORS.join(', ') +
             '). Push-detection disabled. Initial-load + SPA-nav paths still work. ' +
             'To restore: update TIMELINE_SELECTORS in this script with whatever ' +
             'GitHub now calls the PR conversation container.');
        appendLog('selector-failed', {tried: TIMELINE_SELECTORS});
        // Push detection is the script's primary trigger; without it the
        // script does NOT do its job on fix-round pushes. Surface red so
        // the user knows the script needs maintenance, not silent no-op.
        setTabStatus('red', 'selector-failed', 'push detection disabled — update TIMELINE_SELECTORS');
        return null;
    }

    let pushDebounceTimer = null;
    function firePushDebounced() {
        pushDebounceTimer = null;
        maybeRequestCopilotReview('push detected in timeline');
    }
    function onMaybePushDetected(addedNodes) {
        for (const node of addedNodes) {
            if (!node || node.nodeType !== Node.ELEMENT_NODE) continue;
            const text = node.textContent || '';
            // Match push-event regex patterns (case-insensitive via /i flag).
            // Tight matching prevents false triggers on comments containing
            // "pushed" in unrelated contexts.
            const matched = PUSH_MARKERS.find(marker => marker.test(text));
            if (matched) {
                if (pushDebounceTimer) clearTimeout(pushDebounceTimer);
                // Snapshot a tiny excerpt of the matched text for the log;
                // truncate hard so we don't store the whole timeline node.
                const snippet = text.replace(/\s+/g, ' ').trim().slice(0, 80);
                appendLog('push-detected', {regex: String(matched), snippet});
                pushDebounceTimer = setTimeout(firePushDebounced, PUSH_DEBOUNCE_MS);
                return;
            }
        }
    }

    function startTimelineObserver() {
        const target = findTimelineNode();
        if (!target) return null;
        const observer = new MutationObserver(mutations => {
            for (const m of mutations) {
                if (m.addedNodes && m.addedNodes.length) {
                    onMaybePushDetected(m.addedNodes);
                }
            }
        });
        // findTimelineNode() returns {node, selector}; observe() needs the
        // Node. Passing the wrapper object throws synchronously and
        // silently disables push detection (observed in manual testing
        // before the fix: the log would stop at script-loaded).
        // Wrap in try/catch so any future shape-change here surfaces as
        // red status + an `error` log entry, instead of breaking init
        // silently — the dot was green when push-detection was actually
        // dead because observe() threw before any state-setting code ran.
        try {
            observer.observe(target.node, {childList: true, subtree: true});
        } catch (e) {
            warn('failed to attach timeline observer:', e);
            appendLog('error', {message: String(e && e.message || e), where: 'startTimelineObserver'});
            setTabStatus('red', 'observer-attach-failed',
                'MutationObserver.observe() threw — push detection dead');
            return null;
        }
        return observer;
    }

    // === SPA navigation handling ============================================
    let lastUrl = location.href;
    let activeObserver = null;

    function onMaybeNavigated() {
        if (location.href === lastUrl) return;
        lastUrl = location.href;
        log('SPA navigation detected:', lastUrl);
        appendLog('nav-detected', {to: lastUrl});
        cancelPendingObservation();
        if (pushDebounceTimer) {
            clearTimeout(pushDebounceTimer);
            pushDebounceTimer = null;
        }
        if (activeObserver) {
            activeObserver.disconnect();
            activeObserver = null;
        }
        if (isOnPRPage()) {
            setTimeout(() => {
                activeObserver = startTimelineObserver();
                maybeRequestCopilotReview('arrived on PR via SPA navigation');
            }, 800);
        }
    }

    // === Init ==============================================================
    appendLog('script-loaded', {version: SCRIPT_VERSION_FOR_REPORT, tab_id: TAB_ID});

    // Build the panel as soon as document.body is available. On
    // document-idle (per the @run-at metadata) it usually already is, but
    // on some pages we may load before body. Retry briefly if needed.
    function tryEnsurePanel(retries) {
        ensurePanelElements();
        if (!panelDotEl && retries > 0) {
            setTimeout(() => tryEnsurePanel(retries - 1), 200);
        } else if (panelDotEl) {
            updatePanelDot();
        }
    }
    tryEnsurePanel(10);

    // Catch unhandled exceptions originating from this script's frame
    // and surface them as red. We can't reliably attribute every error
    // to our script (other scripts share the page), so we stay silent
    // unless the error's text mentions the LOG_PREFIX or a stack frame
    // names this script. Conservative: red on anything we're confident
    // came from us; ignore the rest.
    window.addEventListener('error', (ev) => {
        const msg = (ev.message || '') + ' ' + ((ev.error && ev.error.stack) || '');
        if (msg.includes('copilot-request-review') || msg.includes(LOG_PREFIX)) {
            appendLog('error', {message: ev.message, filename: ev.filename, lineno: ev.lineno});
            setTabStatus('red', 'exception', ev.message || 'unhandled exception');
        }
    });

    if (isOnPRPage()) {
        activeObserver = startTimelineObserver();
        maybeRequestCopilotReview('initial PR page load');
    }

    window.addEventListener('popstate', onMaybeNavigated);
    document.addEventListener('turbo:load', onMaybeNavigated);
    document.addEventListener('pjax:end', onMaybeNavigated);

    // Fallback: poll the URL on a slow interval. Catches SPA nav we
    // didn't intercept via the events above.
    setInterval(onMaybeNavigated, 2000);

    log('userscript loaded; @match=' + location.host + location.pathname);
})();
