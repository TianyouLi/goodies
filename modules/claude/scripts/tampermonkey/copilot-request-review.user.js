// ==UserScript==
// @name         goodies: Copilot click-trigger
// @namespace    https://github.com/TianyouLi/goodies
// @version      1.4.11
// @description  Click Copilot's "Re-request review" button on demand from goodies-watch. Watcher posts a <details> marker stanza in the PR body; userscript scans the rendered description DOM for the marker (zero gh API calls, scales to any number of tabs without rate-limit risk), clicks the button. Strict-scoped to GitHub PR pages.
// @author       TianyouLi (with Claude)
// @match        https://github.com/*/*/pull/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    // === Why this script exists =============================================
    // The userscript is a thin remote-controlled actuator for the
    // request-review button. It does NOT decide whether or when to click
    // — that's goodies-watch's job, using the gh API for authoritative
    // state. The bridge is a <details> stanza in the PR body:
    //
    //   <details><summary>goodies-watch handshake</summary>
    //   goodies-watch:click-request-review nonce=<X> expires=<ISO> writer=<W>
    //   </details>
    //
    // Watcher writes the marker (PATCH /repos/X/Y/pulls/N body). The
    // userscript scans the RENDERED PR description DOM for the marker.
    // No gh API calls — the userscript scales to any number of tabs
    // without rate-limit risk. (Earlier versions tried HTML-comment
    // markers + DOM scrape: GitHub strips HTML comments. Then API
    // fetch: GitHub anonymous rate limit is 60/hr per IP shared
    // across all tabs, hit easily during dev. <details> survives
    // markdown render, so DOM scrape works again with a different
    // marker form.)
    //
    // Marker is visible to humans as a small collapsible
    // "▸ goodies-watch handshake" line in the PR description.
    // Watcher strips it as soon as Copilot review is observed
    // pending or LGTM, so the visibility window is brief.
    //
    // See `docs/design/userscripts-copilot-watch-handshake.md` for the
    // full architectural rationale, decision tree, trade-offs, and
    // verification scenarios.

    // === Tunables ==========================================================
    const LOG_PREFIX = '[goodies/copilot-click-trigger]';

    // Visible text on the request-review button. Match against the
    // button's textContent (case-insensitive). Update if GitHub changes
    // the wording.
    const REQUEST_BUTTON_TEXTS = ['re-request review', 'request review'];

    // Substring (case-insensitive) we walk the surrounding DOM for to
    // confirm the button belongs to the Copilot reviewer.
    const COPILOT_HINT = 'copilot';

    // Marker regex. The marker is a payload inside a <details> block
    // in the PR body. After markdown→HTML render, the payload appears
    // as plain text inside a <p> inside <details>. We scan the
    // textContent of the description DOM for the payload.
    //
    // The marker payload format is identical to the v1.x line:
    //   goodies-watch:click-request-review nonce=<X> expires=<ISO> writer=<W>
    // We do NOT require <details>/<summary> tags in the regex
    // because textContent strips tags. We rely on the marker
    // string's distinctive prefix to be unambiguous.
    //
    // False-positive guard: a marker payload appearing as visible
    // text outside the <details> would also match. Mitigation:
    // marker payload string is distinctive enough that prose
    // documenting it (e.g. design docs) is rare in PR descriptions.
    // The watcher always wraps in <details>, so legitimate markers
    // will always be inside one — we don't enforce that in the
    // userscript regex because textContent doesn't preserve tags.
    const MARKER_REGEX = /goodies-watch:click-request-review\s+nonce=(\S+)\s+expires=(\S+)\s+writer=(\S+)/g;

    // DOM-scan cadence. No gh API calls — DOM reads are free and
    // scale to unlimited tabs. 5s is fine; tighter doesn't help
    // because the cron is the dominant latency contributor.
    const POLL_INTERVAL_MS = 5000;

    // (Skew machinery removed — see "Time source" comment below.)

    // === Persistent action log (Layer A observability, preserved) ===========
    // Layer A from v0.x stays. Failures + actions append to a localStorage
    // ring buffer the user can dump via the panel's "Copy log" button or
    // window.__goodiesActionLog({asText: true}).
    const LOG_KEY = 'goodies-userscript:actionlog';

    // Per-tab clear-cutoff timestamps. When the user clicks "Clear log",
    // we record a cutoff ISO timestamp for this TAB_ID instead of
    // rewriting the shared LOG_KEY buffer. getTabFilteredLog() skips
    // entries older than the cutoff. This avoids a read-modify-write
    // race where clearTabLog() in one tab could clobber a concurrent
    // appendLog() write from another tab.
    const TAB_CLEAR_KEY = 'goodies-userscript:tab-clear-cutoffs';

    function getTabClearCutoffMs() {
        try {
            const raw = localStorage.getItem(TAB_CLEAR_KEY);
            if (!raw) return 0;
            const map = JSON.parse(raw);
            if (!map || !map[TAB_ID]) return 0;
            const ms = new Date(map[TAB_ID]).getTime();
            return isNaN(ms) ? 0 : ms;
        } catch (_) {
            return 0;
        }
    }

    const TAB_CLEAR_MAX_ENTRIES = 50;

    function setTabClearCutoff() {
        try {
            const raw = localStorage.getItem(TAB_CLEAR_KEY);
            const map = (raw && JSON.parse(raw)) || {};
            map[TAB_ID] = new Date().toISOString();
            // Prune to most recent TAB_CLEAR_MAX_ENTRIES entries to cap storage growth.
            // Sort by ISO timestamp descending and keep the newest N.
            const entries = Object.entries(map)
                .filter(([, v]) => typeof v === 'string' && !isNaN(new Date(v).getTime()))
                .sort(([, a], [, b]) => new Date(b).getTime() - new Date(a).getTime())
                .slice(0, TAB_CLEAR_MAX_ENTRIES);
            localStorage.setItem(TAB_CLEAR_KEY, JSON.stringify(Object.fromEntries(entries)));
        } catch (e) {
            logCaught('setTabClearCutoff', e);
        }
    }
    const LOG_MAX_ENTRIES = 100;

    // Acted-(writer,nonce) record shared across all tabs (localStorage).
    // Intentionally cross-tab: prevents a second open tab from re-clicking
    // the same (writer,nonce) after the first tab already acted.
    // One entry per (writer,nonce) pair.
    const ACTED_KEY = 'goodies-userscript:acted-nonces';
    const ACTED_MAX_ENTRIES = 200;

    // Per-nonce reload-attempted table. When no button is found for a
    // fresh marker, the page is reloaded once. We record the nonce so a
    // second scan after reload doesn't loop forever.
    const RELOAD_KEY = 'goodies-userscript:reload-nonces';
    const RELOAD_MAX_ENTRIES = 200;

    const VERBOSE = true;
    const log = (...args) => VERBOSE && console.log(LOG_PREFIX, ...args);
    const warn = (...args) => console.warn(LOG_PREFIX, ...args);

    // === Tab identity =======================================================
    // For per-tab acted-nonce tracking and log entries.
    // Persisted in sessionStorage so the ID survives page reloads (e.g.
    // the stale-DOM reload introduced in v1.4.2). Without persistence,
    // the post-reload tab gets a new ID and the per-tab log filter drops
    // all pre-reload entries — the reload-for-fresh-button path would
    // then appear to have no prior log, making bug reports misleading.
    const TAB_ID_SESSION_KEY = 'goodies-userscript:tab-id';
    const TAB_ID = (() => {
        try {
            const existing = sessionStorage.getItem(TAB_ID_SESSION_KEY);
            if (existing) return existing;
            const fresh = 'tab-' + Math.random().toString(36).slice(2, 10) +
                          '-' + Date.now().toString(36);
            sessionStorage.setItem(TAB_ID_SESSION_KEY, fresh);
            return fresh;
        } catch (e) {
            warn('TAB_ID generation/persist failed; using fallback:', e);
            return 'tab-fallback';
        }
    })();
    log('tab id:', TAB_ID);

    // === Action log (ring buffer in localStorage) ==========================
    let panelLogCallback = null;

    function readLogRaw() {
        try {
            const raw = localStorage.getItem(LOG_KEY);
            if (!raw) return [];
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            // Don't logCaught here — we'd recurse. Plain warn only.
            warn('readLogRaw failed (corrupt JSON or storage blocked):', e);
            return [];
        }
    }

    function appendLog(event, detail) {
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
            const start = Math.max(0, buf.length - LOG_MAX_ENTRIES);
            localStorage.setItem(LOG_KEY, JSON.stringify(buf.slice(start)));
            if (panelLogCallback) {
                try { panelLogCallback(entry); } catch (_) { /* never break main path */ }
            }
        } catch (e) {
            warn('appendLog failed (storage full or disabled?):', e);
        }
    }

    // logCaught: warn + record to action log. Never call from inside
    // appendLog or readLogRaw (recursion).
    function logCaught(where, e, extra) {
        const detail = Object.assign(
            {where, message: String(e && e.message || e)},
            extra || {}
        );
        warn(where + ' caught:', e);
        try { appendLog('error', detail); } catch (_) { /* never recurse */ }
    }

    // Known event kinds (documentation; not enforced):
    //   script-loaded            — script init on a PR page
    //   nav-detected             — SPA navigation
    //   dom-body-changed         — pollDom() saw the PR description text change
    //   marker-seen              — found a fresh marker in body
    //   marker-expired           — found a marker but its `expires` is past
    //   marker-already-acted     — (writer,nonce) already in acted table
    //   click-attempted          — tried to click the button
    //   click-skipped-no-button  — couldn't find the button (red)
    //   click-skipped-disabled   — button found but not clickable (red)
    //   error                    — exception caught somewhere

    // Expose retrieval for DevTools-rare cross-tab investigation.
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
    } catch (_) { /* benign on re-load */ }

    // === Acted-nonce table =================================================
    // localStorage-backed so it survives tab refresh. Keyed by
    // `${writer}:${nonce}`. Trimmed by FIFO when over the cap.
    function readActedRaw() {
        try {
            const raw = localStorage.getItem(ACTED_KEY);
            if (!raw) return [];
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            logCaught('readActedRaw', e);
            return [];
        }
    }

    function hasActed(writer, nonce) {
        const key = `${writer}:${nonce}`;
        return readActedRaw().some(e => e.key === key);
    }

    function recordActed(writer, nonce) {
        try {
            const key = `${writer}:${nonce}`;
            const buf = readActedRaw();
            if (buf.some(e => e.key === key)) return;
            buf.push({key, at: new Date().toISOString()});
            const start = Math.max(0, buf.length - ACTED_MAX_ENTRIES);
            localStorage.setItem(ACTED_KEY, JSON.stringify(buf.slice(start)));
        } catch (e) {
            logCaught('recordActed', e, {writer, nonce});
        }
    }

    // Reload-nonce table (parallel shape to acted-nonce table).
    function readReloadRaw() {
        try {
            const raw = localStorage.getItem(RELOAD_KEY);
            if (!raw) return [];
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            logCaught('readReloadRaw', e);
            return [];
        }
    }

    function hasReloaded(writer, nonce) {
        const key = `${writer}:${nonce}`;
        return readReloadRaw().some(e => e.key === key);
    }

    function recordReload(writer, nonce) {
        try {
            const key = `${writer}:${nonce}`;
            const buf = readReloadRaw();
            if (buf.some(e => e.key === key)) return;
            buf.push({key, at: new Date().toISOString()});
            const start = Math.max(0, buf.length - RELOAD_MAX_ENTRIES);
            localStorage.setItem(RELOAD_KEY, JSON.stringify(buf.slice(start)));
        } catch (e) {
            logCaught('recordReload', e, {writer, nonce});
        }
    }

    // === Strict scope: hostname + path guards ==============================
    if (location.hostname !== 'github.com') {
        warn('hostname is not github.com (got "' + location.hostname +
             '"); refusing to run.');
        return;
    }

    // Match only the conversation root (/owner/repo/pull/N or /owner/repo/pull/N/).
    // Sub-routes like /files, /commits, /checks do NOT render the PR description
    // in the same DOM position, so the marker scan would silently find nothing
    // — or worse, match a stale body from a previous navigation.
    const PR_PATH_REGEX = /^\/[^/]+\/[^/]+\/pull\/\d+\/?$/;
    function isOnPRPage() {
        return PR_PATH_REGEX.test(location.pathname);
    }

    // === Time source ========================================================
    // No skew computation. Earlier versions tried two approaches:
    //
    //   v1.1/1.2: HEAD api.github.com → read Date header. Worked but
    //             cost an API call per refresh, against the 60/hr
    //             anonymous budget the v1.3 pivot tries to eliminate.
    //
    //   v1.3 first cut: pick the newest <relative-time datetime=...>
    //             on the page and treat it as "GitHub-now". WRONG —
    //             those are EVENT timestamps (when a comment was
    //             posted, etc.), not "now". skew_ms would equal
    //             -(age of newest event), causing markers to appear
    //             stale or fresh by random amounts (real-world
    //             observed: 644652ms).
    //
    // We just use Date.now() directly. The expires comparison is
    // approximate by design (10-min validity window in the watcher;
    // a few minutes of browser-clock drift won't materially break
    // the handshake). If the user's clock is wildly off, markers
    // may briefly appear expired-when-fresh or fresh-when-expired,
    // and the watcher's next poll refreshes the marker either way.
    // Wrong skew is worse than no skew.
    function effectiveNowMs() {
        return Date.now();
    }

    // === PR body source (DOM scan) =========================================
    // Read the rendered PR description from the DOM. GitHub strips
    // HTML comments during markdown render, so the watcher's marker
    // is wrapped in <details><summary>...</summary>payload</details>
    // — <details> survives. The marker payload appears in textContent
    // because the structure renders to a <p> inside the <details>.
    //
    // PR_BODY_SELECTORS is a fallback chain — GitHub's class names
    // churn, so we try each in order and use the first that matches.
    const PR_BODY_SELECTORS = [
        '.js-comment-body.markdown-body',          // current GitHub class combo
        '.markdown-body',                           // fallback
        '[class*="comment-body"]',                  // generic class containment
    ];

    function readPRBodyText() {
        // The PR description is the FIRST comment-body on the page.
        // Subsequent .markdown-body matches are review comments etc.
        // Returning textContent so the regex can match across the
        // <details>/<p> boundary.
        for (const sel of PR_BODY_SELECTORS) {
            const node = document.querySelector(sel);
            if (node) {
                return node.textContent || '';
            }
        }
        return '';
    }

    function hashString(s) {
        // Tiny non-cryptographic hash for change detection.
        let h = 5381;
        for (let i = 0; i < s.length; i++) {
            h = ((h << 5) + h + s.charCodeAt(i)) | 0;
        }
        return h;
    }

    // === Marker scan + click ===============================================
    // Return values from scanForMarker — null with a reason string.
    // Callers use these to set accurate status text.
    const SCAN_NULL_NO_MARKER   = 'no-marker';
    const SCAN_NULL_EXPIRED     = 'expired';
    const SCAN_NULL_ALL_ACTED   = 'all-acted';

    function scanForMarker(bodyText) {
        // Returns the first *unacted* non-expired marker in the body
        // (sorted by soonest-to-expire), or null. "Unacted" = the
        // (writer, nonce) pair isn't in the shared (cross-tab) localStorage
        // acted table (ACTED_KEY).
        //
        // Why prefer unacted: in multi-watcher scenarios, multiple
        // markers can coexist. If we always returned the freshest and
        // it happened to already be acted, attemptClick would early-
        // return and we'd never look at the OTHER fresh marker that
        // might be a legitimate new request from a different watcher.
        // Skipping over already-acted markers here makes evaluateMarker
        // visit each new request exactly once.
        //
        // On null: sets scanForMarker.lastNullReason to one of the
        // SCAN_NULL_* constants so the caller can show precise status.
        const markers = [];
        let m;
        MARKER_REGEX.lastIndex = 0;
        while ((m = MARKER_REGEX.exec(bodyText)) !== null) {
            const [, nonce, expires, writer] = m;
            const expiresMs = new Date(expires).getTime();
            if (isNaN(expiresMs)) continue;
            markers.push({nonce, expires, writer, expiresMs});
        }
        if (markers.length === 0) {
            scanForMarker.lastNullReason = SCAN_NULL_NO_MARKER;
            return null;
        }

        const now = effectiveNowMs();
        const fresh = markers.filter(m => m.expiresMs > now);
        if (fresh.length === 0) {
            appendLog('marker-expired', {count: markers.length});
            scanForMarker.lastNullReason = SCAN_NULL_EXPIRED;
            return null;
        }
        // Sort by expires ascending so we evaluate soonest-to-expire
        // first. Watcher writes a 10-min expires; if multiple markers
        // exist (multi-watcher), they're independent requests.
        fresh.sort((a, b) => a.expiresMs - b.expiresMs);
        // Return the first one we haven't acted on. If all fresh
        // markers are already acted, return null — there's no work.
        for (const candidate of fresh) {
            if (!hasActed(candidate.writer, candidate.nonce)) {
                scanForMarker.lastNullReason = null;
                return candidate;
            }
        }
        scanForMarker.lastNullReason = SCAN_NULL_ALL_ACTED;
        return null;
    }
    scanForMarker.lastNullReason = null;

    function ancestorMentionsCopilot(el, maxDepth) {
        // Walk up ancestors checking for "copilot" — but in EVERY
        // possible signal source: textContent (visible text), `alt`
        // attributes (avatar images), `aria-label` (screen-reader
        // text), `title` (tooltips), and `data-login` (GitHub's own
        // user identifier). Icon-only reviewer rows have no visible
        // text but their `<img alt="Copilot">` or
        // `<a data-login="Copilot">` is still discoverable.
        let node = el;
        for (let depth = 0; depth < maxDepth && node; depth++) {
            const text = (node.textContent || '').toLowerCase();
            if (text.includes(COPILOT_HINT)) return true;
            // Check attributes on this node and all descendants up
            // to ~50 elements deep. Cheap.
            const descendants = node.querySelectorAll
                ? node.querySelectorAll('[alt], [aria-label], [title], [data-login]')
                : [];
            let n = 0;
            for (const d of descendants) {
                if (n++ > 50) break;
                const haystack = (
                    (d.getAttribute('alt') || '') + ' ' +
                    (d.getAttribute('aria-label') || '') + ' ' +
                    (d.getAttribute('title') || '') + ' ' +
                    (d.getAttribute('data-login') || '')
                ).toLowerCase();
                if (haystack.includes(COPILOT_HINT)) return true;
            }
            node = node.parentElement;
        }
        return false;
    }

    function findCopilotReviewerRow() {
        // v1.4 strategy ladder, tried in order:
        //
        //  1. Strong signal: GitHub's re-request-review form uses
        //     <button name="re_request_reviewer_id" value="<id>">.
        //     If exactly one such button exists in the Copilot
        //     reviewer's row (via ancestor-attribute scan), use it.
        //
        //  2. Visible-text fallback: the v0.x match — buttons whose
        //     textContent contains "request review" + ancestor
        //     mentions copilot. Catches a UI variant where the
        //     button has visible text instead of an icon.
        //
        //  3. aria-label / title fallback: covers icon-only buttons
        //     whose semantic name is in aria-label.
        //
        // For each candidate, we use ancestorMentionsCopilot which
        // checks BOTH textContent AND alt/aria-label/title/data-login
        // attributes, so icon-only Copilot rows (no visible text)
        // still match via the avatar's alt="Copilot" or similar.

        // Strategy 1: form-name match (most reliable). Restrict to
        // button elements only — hidden inputs share the same name but
        // are never clickable and would cause false "button-unclickable"
        // failures when shouldClick() checks their zero-size bounding box.
        const byName = Array.from(
            document.querySelectorAll('button[name="re_request_reviewer_id"]')
        );
        for (const el of byName) {
            if (ancestorMentionsCopilot(el, 8)) {
                return {button: el, row: el.closest('li, tr, .Box-row, form, div') || el};
            }
        }

        // Strategy 2 + 3: text / aria-label / title match.
        const candidates = Array.from(
            document.querySelectorAll('button, a[role="button"], summary')
        );
        for (const el of candidates) {
            const text = (el.textContent || '').trim().toLowerCase();
            const aria = (el.getAttribute('aria-label') || '').toLowerCase();
            const title = (el.getAttribute('title') || '').toLowerCase();
            const haystack = text + ' ' + aria + ' ' + title;
            if (!REQUEST_BUTTON_TEXTS.some(p => haystack.includes(p))) continue;
            if (ancestorMentionsCopilot(el, 6)) {
                return {button: el, row: el.closest('li, tr, .Box-row, form, div') || el};
            }
        }

        return null;
    }

    function shouldClick(button) {
        if (button.disabled) return false;
        if (button.getAttribute('aria-disabled') === 'true') return false;
        const rect = button.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return false;
        return true;
    }

    function attemptClick(marker) {
        if (hasActed(marker.writer, marker.nonce)) {
            appendLog('marker-already-acted',
                {writer: marker.writer, nonce: marker.nonce});
            setTabStatus('green', 'observing', 'already acted on this nonce');
            return;
        }

        // v1.3 dropped the API-based pending pre-check — the watcher
        // is responsible for not posting a marker when Copilot is
        // already pending (Step 0c). If a marker arrives while pending
        // (manual injection or rare race), the click attempt naturally
        // returns no-button-found (red dot, log entry). The state
        // resolves on its own when Copilot's review finishes; the
        // marker either gets refreshed with new context by the next
        // watcher poll or stripped on Case A.

        const found = findCopilotReviewerRow();
        if (!found) {
            // Button not in DOM. This commonly happens when the PR page
            // loaded before the latest push — GitHub doesn't re-render
            // the reviewer sidebar without a page reload. Reload once
            // per nonce; if the button is still absent after reload
            // (genuinely missing, not stale DOM), report red.
            if (!hasReloaded(marker.writer, marker.nonce)) {
                recordReload(marker.writer, marker.nonce);
                appendLog('reload-for-fresh-button',
                    {writer: marker.writer, nonce: marker.nonce});
                location.reload();
                return;
            }
            appendLog('click-skipped-no-button',
                {writer: marker.writer, nonce: marker.nonce});
            setTabStatus('red', 'no-button-found',
                'watcher requested click but request-review button missing');
            return;
        }
        if (!shouldClick(found.button)) {
            appendLog('click-skipped-disabled',
                {writer: marker.writer, nonce: marker.nonce});
            setTabStatus('red', 'button-unclickable',
                'request-review button found but disabled/hidden');
            return;
        }

        log('clicking request-review (writer=' + marker.writer +
            ' nonce=' + marker.nonce + ')');
        appendLog('click-attempted',
            {writer: marker.writer, nonce: marker.nonce});
        found.button.click();
        recordActed(marker.writer, marker.nonce);
        setTabStatus('green', 'clicked',
            'clicked on watcher request (nonce=' + marker.nonce + ')');
        flashIndicator('Copilot review requested', 'green');
    }

    // === DOM poll loop ====================================================
    // Reads the rendered PR description's textContent every
    // POLL_INTERVAL_MS, hashes it, scans for the marker on change.
    // Free, no gh API. Scales to unlimited tabs.
    let lastBodyHash = 0;
    let bodyMissStreak = 0;
    const BODY_MISS_WARN_THRESHOLD = 5; // ~25s of consecutive misses → selector broken

    function pollDom(reason) {
        const bodyText = readPRBodyText();
        if (!bodyText) {
            bodyMissStreak++;
            if (bodyMissStreak === BODY_MISS_WARN_THRESHOLD) {
                // Selectors have failed for ~25s on a live PR page. This is
                // likely a GitHub DOM change. Log once and flip red so the
                // status panel surfaces the problem without spamming.
                appendLog('body-selector-miss', {streak: bodyMissStreak, reason});
                setTabStatus('red', 'selector-broken',
                    'PR description not found — selectors may need updating');
            }
            return;
        }
        if (bodyMissStreak >= BODY_MISS_WARN_THRESHOLD) {
            // Selectors recovered after a sustained miss. Clear the red status.
            appendLog('body-selector-recovered', {streak: bodyMissStreak});
            setTabStatus('green', 'observing', 'selector recovered');
        }
        bodyMissStreak = 0;
        const h = hashString(bodyText);
        if (h === lastBodyHash) return;  // no change
        lastBodyHash = h;
        appendLog('dom-body-changed', {reason, body_chars: bodyText.length});
        evaluateMarker(bodyText);
    }

    function recordAllFreshMarkers(bodyText) {
        // After a successful click, mark every fresh marker in the body as
        // acted — including other watchers' markers. One click is sufficient
        // to trigger Copilot; sibling markers no longer need action. Without
        // this, the next poll finds a sibling marker, tries to click a
        // now-gone button, and incorrectly flips the status dot red.
        const now = effectiveNowMs();
        const m_re = new RegExp(MARKER_REGEX.source, MARKER_REGEX.flags);
        let m;
        while ((m = m_re.exec(bodyText)) !== null) {
            const [, nonce, expires, writer] = m;
            const expiresMs = new Date(expires).getTime();
            if (!isNaN(expiresMs) && expiresMs > now) {
                recordActed(writer, nonce);
            }
        }
    }

    function evaluateMarker(bodyText) {
        const marker = scanForMarker(bodyText);
        if (!marker) {
            const reason = scanForMarker.lastNullReason;
            const detail =
                reason === SCAN_NULL_EXPIRED   ? 'marker present but expired; awaiting refresh' :
                reason === SCAN_NULL_ALL_ACTED ? 'marker seen but already acted (stored in localStorage); waiting for a new nonce' :
                                                 'no marker; idle';
            setTabStatus('green', 'observing', detail);
            return;
        }
        appendLog('marker-seen',
            {writer: marker.writer, nonce: marker.nonce, expires: marker.expires});
        try {
            attemptClick(marker);
            // Only mark sibling markers acted when a click actually occurred.
            // attemptClick() calls recordActed() on success; on the stale-DOM
            // reload path (or any other early return) it does NOT call
            // recordActed(), so hasActed() remains false and we skip this.
            // This prevents marking sibling markers as acted on reload, which
            // would cause the post-reload run to skip the marker entirely.
            if (hasActed(marker.writer, marker.nonce)) {
                recordAllFreshMarkers(bodyText);
            }
        } catch (e) {
            logCaught('attemptClick', e,
                {writer: marker.writer, nonce: marker.nonce});
            setTabStatus('red', 'click-exception',
                'attemptClick threw — see action log for details');
        }
    }

    // === Visible toast =====================================================
    function flashIndicator(message, color) {
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
            logCaught('flashIndicator', e, {message});
        }
    }

    // === Per-tab status panel ==============================================
    // Same shape as v0.x: 14×14 colored dot bottom-right; click expands
    // panel showing this tab's recent log + Copy/Clear buttons. Hidden
    // on non-PR pages.

    const PANEL_DOT_ID = 'goodies-userscript-status-dot';
    const PANEL_BODY_ID = 'goodies-userscript-status-panel';
    const PANEL_LOG_VISIBLE = 15;
    const SCRIPT_VERSION_FOR_REPORT = '1.4.11';

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
        if (!document.body) return;

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
            zIndex: '99998',
        });
        panelDotEl.title = 'goodies userscript: working';
        panelDotEl.setAttribute('role', 'button');
        panelDotEl.setAttribute('tabindex', '0');
        panelDotEl.setAttribute('aria-label', 'goodies userscript status — click to open log panel');
        panelDotEl.addEventListener('click', togglePanel);
        panelDotEl.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); togglePanel(); }
        });
        document.body.appendChild(panelDotEl);

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
        headerTitle.textContent = 'goodies userscript v' + SCRIPT_VERSION_FOR_REPORT;
        const headerClose = document.createElement('div');
        headerClose.textContent = '×';
        headerClose.setAttribute('role', 'button');
        headerClose.setAttribute('tabindex', '0');
        headerClose.setAttribute('aria-label', 'Close log panel');
        Object.assign(headerClose.style, {
            cursor: 'pointer',
            fontSize: '18px',
            lineHeight: '1',
            padding: '0 4px',
            userSelect: 'none',
        });
        headerClose.addEventListener('click', () => setPanelExpanded(false));
        headerClose.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setPanelExpanded(false); }
        });
        header.appendChild(headerTitle);
        header.appendChild(headerClose);
        panelBodyEl.appendChild(header);

        panelStatusSectionEl = document.createElement('div');
        Object.assign(panelStatusSectionEl.style, {
            padding: '8px 12px',
            borderBottom: '1px solid #d0d7de',
        });
        panelBodyEl.appendChild(panelStatusSectionEl);

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

        const skewLine = document.createElement('div');
        Object.assign(skewLine.style, {
            color: '#57606a',
            marginTop: '4px',
            fontFamily: 'ui-monospace, monospace',
            fontSize: '11px',
        });
        skewLine.textContent = 'tab: ' + TAB_ID;
        panelStatusSectionEl.appendChild(skewLine);
    }

    function getTabFilteredLog() {
        const cutoffMs = getTabClearCutoffMs();
        return readLogRaw().filter(e =>
            e.tab_id === TAB_ID &&
            new Date(e.at).getTime() >= cutoffMs
        );
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
        } catch (eClipboard) {
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
            } catch (eFallback) {
                logCaught('copyTabLog', eFallback, {
                    primary_message: String(eClipboard && eClipboard.message || eClipboard),
                });
                ok = false;
            }
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
        // Record a cutoff timestamp instead of rewriting the shared buffer.
        // Other tabs' concurrent appendLog() writes are unaffected.
        setTabClearCutoff();
        refreshPanelLog();
    }

    function setPanelVisibility(visible) {
        if (panelDotEl) panelDotEl.style.display = visible ? 'block' : 'none';
        if (panelBodyEl && !visible) {
            panelBodyEl.style.display = 'none';
            panelExpanded = false;
        }
    }

    // === SPA navigation handling ===========================================
    let lastUrl = location.href;
    let pollIntervalId = null;

    function startDomPolling() {
        stopDomPolling();
        pollIntervalId = setInterval(() => pollDom('interval'), POLL_INTERVAL_MS);
    }

    function stopDomPolling() {
        if (pollIntervalId !== null) {
            clearInterval(pollIntervalId);
            pollIntervalId = null;
        }
    }

    function onMaybeNavigated() {
        if (location.href === lastUrl) return;
        lastUrl = location.href;
        log('SPA navigation detected:', lastUrl);
        appendLog('nav-detected', {to: lastUrl, on_pr_page: isOnPRPage()});
        // Reset poll state so the new PR's body gets evaluated.
        lastBodyHash = 0;
        if (isOnPRPage()) {
            setPanelVisibility(true);
            setTabStatus('green', 'loaded', 'arrived on PR via SPA navigation');
            startDomPolling();
            // Initial poll without waiting for first interval.
            setTimeout(() => pollDom('spa-nav-arrival'), 800);
        } else {
            setPanelVisibility(false);
            stopDomPolling();
        }
    }

    // === Init ==============================================================
    appendLog('script-loaded',
        {version: SCRIPT_VERSION_FOR_REPORT, tab_id: TAB_ID});

    function tryEnsurePanel(retries) {
        ensurePanelElements();
        if (!panelDotEl && retries > 0) {
            setTimeout(() => tryEnsurePanel(retries - 1), 200);
        } else if (panelDotEl) {
            updatePanelDot();
            setPanelVisibility(isOnPRPage());
        }
    }
    tryEnsurePanel(10);

    // Catch unhandled exceptions originating from this script.
    window.addEventListener('error', (ev) => {
        const msg = (ev.message || '') + ' ' + ((ev.error && ev.error.stack) || '');
        if (msg.includes('copilot-click-trigger') ||
            msg.includes('copilot-request-review') ||
            msg.includes(LOG_PREFIX)) {
            appendLog('error',
                {message: ev.message, filename: ev.filename, lineno: ev.lineno});
            setTabStatus('red', 'exception', ev.message || 'unhandled exception');
        }
    });

    // Boot path: start DOM polling, do initial scan.
    if (isOnPRPage()) {
        startDomPolling();
        // Initial DOM scan after a brief settle delay (gives GitHub
        // SPA time to render the description).
        setTimeout(() => pollDom('initial-load'), 1500);
    }

    window.addEventListener('popstate', onMaybeNavigated);
    document.addEventListener('turbo:load', onMaybeNavigated);
    document.addEventListener('pjax:end', onMaybeNavigated);
    setInterval(onMaybeNavigated, 2000);

    log('userscript v' + SCRIPT_VERSION_FOR_REPORT + ' loaded; @match=' + location.host + location.pathname);
})();
