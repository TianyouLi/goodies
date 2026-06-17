# Tampermonkey userscripts (Claude PR-review helpers)

Browser-side userscripts that complement the goodies Claude commands.
Installed via [Tampermonkey](https://www.tampermonkey.net/) (or
Greasemonkey / Violentmonkey — any compliant userscript manager).

These are **not** managed by `modules/claude/install.sh` because
userscripts live inside a browser extension, not on the filesystem.
Each script is a standalone `.user.js` file that you install through
your extension's UI.

## Why these exist

Some GitHub repos disable the rule that auto-triggers Copilot code
review on push (this is common in org-managed repos with branch-
protection policies). On those repos the user has to manually click
"Re-request review" on the Copilot reviewer in the PR's sidebar
after every push.

The v1.0 design factors this into two cooperating pieces:

- **`goodies-watch`** decides *whether and when* to ask Copilot for
  a review, using the gh API for authoritative state (PR open,
  Copilot a reviewer, comments resolved, etc.). It posts a tiny
  marker stanza in the PR body when the click is needed.
- **The userscript** is a thin actuator: it polls the PR body for
  the marker, finds the request-review button, clicks it, and
  records the click in its action log. The watcher independently
  observes the resulting state change and strips the marker.

This split puts decision logic where authoritative state lives (gh
API) and DOM interaction where it's unavoidable (browser).

## Scripts

### `copilot-request-review.user.js` (v1.0+)

Click trigger for Copilot's "Re-request review" button, driven by a
marker stanza that `goodies-watch` writes into the PR body.

Design doc:
[`docs/design/userscripts-copilot-watch-handshake.md`](../../../../docs/design/userscripts-copilot-watch-handshake.md)
covers the architectural rationale, decision tree, and trade-offs in
detail. The summary below is the user-facing view.

- **Match pattern:** `https://github.com/*/*/pull/*` (all PR pages
  — Tampermonkey injection scope). At runtime the script further
  restricts itself to the **PR conversation root** (`/owner/repo/pull/N`
  only, strict end-anchor). Sub-routes like `/files`, `/commits`, and
  `/checks` are skipped because the PR description is not rendered in
  the same DOM position there; the status dot will not appear and
  marker scanning will not run on those pages.
- **Marker stanza:** the watcher writes a `<details>` block into
  the PR body; the userscript reads the rendered description's
  `textContent` and scans for the marker payload line inside it:
  `goodies-watch:click-request-review nonce=<X> expires=<ISO> writer=<W>`.
  The summary header (`goodies-watch handshake`) is collapsed by
  default so the marker is visually unobtrusive, but the payload
  text is present in the DOM and readable. (HTML comments were the
  v0.x form but GitHub strips them during markdown render — that's
  why the `<details>` form was adopted in v1.3.)
- **Polling cadence:** every 5 seconds, the userscript reads the
  rendered PR description's `textContent` from the DOM and hashes
  it. Only when the hash changes does it scan for the marker
  payload — avoiding redundant regex work on unchanged bodies.
  **Zero gh API calls** — DOM reads are free and scale to unlimited
  tabs without rate-limit risk.
  (Earlier versions tried HTML-comment markers + DOM scrape:
  GitHub strips HTML comments during markdown render. Then API
  fetch with ETag: hit the 60/hr anonymous rate limit. v1.3 uses
  a `<details>` marker form that survives sanitization, with the
  payload visible in the rendered DOM as plain text.)
- **No clock skew compensation.** v1.x earlier tried two
  approaches (HEAD api.github.com → Date header; DOM-derive from
  `<relative-time>`). Both had problems: the API call burns
  rate-limit budget, the DOM-derive is wrong (those are EVENT
  timestamps not "now"). v1.3 uses `Date.now()` directly. The
  marker's 10-min validity window tolerates browser-clock drift
  up to a few minutes, and the watcher's next poll re-posts a
  fresh marker if the old one expired before action.
- **Idempotency:** the userscript records `(writer, nonce)` pairs
  in `localStorage` after acting. Re-seeing the same marker
  (e.g. after a tab refresh) doesn't re-click. In multi-watcher
  scenarios, one successful click is sufficient — after acting, the
  script marks all other fresh markers in the body as already-acted
  so subsequent polls don't attempt a second click (which would fail
  because the request-review button is gone after the first click).
- **Visible feedback:**
  - **Green toast** ("Copilot review requested") — shown once when
    the script clicks the button.
  - **Status dot (green/red)** in the bottom-right corner reflects
    the script's ongoing state (see below). No toast for status
    transitions — the dot is the two-color signal.

**Per-tab status panel + action log.** A 14×14px colored dot in the
bottom-right corner of every PR page shows *this tab's* status —
**green = working as intended**, **red = NOT doing its job** (marker
present but request-review button missing/unclickable, or unhandled
exception). Click the dot to expand a panel with this tab's recent
log + a **"Copy log"** button that writes the full log to clipboard
for bug reports. Each tab is fully independent. No DevTools required
to investigate. See "Reporting bugs" below.

**Verbose logging on by default during the dogfood phase.** The
action log is separate — always on, persisted to `localStorage`,
capped at 100 entries (ring buffer). Retrievable via the panel's
Copy log button or via DevTools
(`window.__goodiesActionLog({asText: true})`).

### Selector strategy — three strategies, visible text preferred

The script uses three strategies to find the request-review button,
in priority order:

1. **Form name** (`button[name="re_request_reviewer_id"]`) — the
   most reliable signal; GitHub's form submit button for re-request
   carries this name regardless of how it is visually rendered
   (text or icon-only). Proximity check confirms a `copilot`
   ancestor in the DOM (checks `textContent`, `alt`, `aria-label`,
   `title`, and `data-login` attributes).
2. **Visible text + proximity** — `textContent` matched
   case-insensitively against `REQUEST_BUTTON_TEXTS` (`"re-request
   review"` / `"request review"`) in a Copilot ancestor row.
3. **aria-label / title discovery** — scans attribute values for
   any element in the reviewers section that mentions the action,
   combined with the proximity check.

**When GitHub changes the wording** (rare but possible), update
`REQUEST_BUTTON_TEXTS` and verify Strategy 1 still matches the form
`name` attribute. Everything else (PR state, Copilot reviewer state,
comment resolution) is handled by `goodies-watch`'s gh-API-based
decision tree.

## Install

1. Install [Tampermonkey](https://www.tampermonkey.net/) for your
   browser (Chrome, Firefox, Edge, Safari, Opera all supported).
2. Open the script file in your browser:
   ```
   file:///path/to/goodies/modules/claude/scripts/tampermonkey/copilot-request-review.user.js
   ```
   Tampermonkey detects `.user.js` files and offers to install. Or:
3. Copy the file contents into Tampermonkey's "Create new script" UI
   and save.

After install, navigate to any GitHub PR page. You should see:
- A `[goodies/copilot-click-trigger] tab id: tab-...` line in the
  DevTools console.
- A green dot in the bottom-right corner of the page.

**A toast does not appear on mere page navigation** — toasts only
fire when the script actually clicks the button (green toast). "No
toast on page open" is normal, not a broken install.

## Verify it works

The userscript v1.0 only acts when `goodies-watch` posts a marker.
On its own, the userscript does nothing observable except show the
status dot. Three scenarios for verification:

**Scenario A — userscript installed, watcher running, fix-round push:**

1. From the goodies repo, run `/goodies-watch` on a PR you're
   working on.
2. Push a commit (the user has fixed Copilot's last review).
3. Within ~3 min (one watcher poll), the watcher posts a marker
   stanza into the PR body.
4. Within ~5s of the marker landing (the userscript's DOM-poll
   interval; zero gh API calls), the userscript:
   - Sees the marker.
   - Clicks the Copilot request-review button.
   - Flashes a green toast.
   - Records the click in the action log (`click-attempted`).
5. Watcher's next poll observes Copilot's `requested_reviewers`
   went pending, strips its own marker.
6. Eventually Copilot's review materializes; the watcher surfaces
   any findings via Case B (or LGTMs via Case A).

**Scenario B — userscript NOT installed, watcher running:**

1. Same setup, but no Tampermonkey extension.
2. Watcher posts marker.
3. Marker sits past `expires` (10 min by default) without a
   state change.
4. Watcher's Step 0j fallback strips the marker and prompts the
   user with: *"Userscript marker on PR #N expired without
   observed state change. [a] Click 'Request review' manually [b]
   Skip"*.

**Scenario C — userscript installed but button can't be clicked:**

1. Marker lands in PR body.
2. Userscript reads marker but `findCopilotReviewerRow()` returns
   nothing (Copilot not in reviewers, or GitHub renamed something).
3. Status dot turns **red**, action log entry
   `click-skipped-no-button`.
4. Watcher times out (no state change) and falls back to the user
   prompt as in Scenario B.
5. The user can investigate by clicking the red dot, hitting "Copy
   log", and pasting the log into a bug report.

## Reporting bugs (the easy path)

The script keeps a per-tab action log so the maintainer can diagnose
issues without asking you to open DevTools.

1. Notice the **status dot in the bottom-right corner** of any PR
   page. Green = the script is working as designed; red = it isn't
   doing its job (marker present but button missing, exception
   caught, etc.).
2. **Click the dot** — a panel pops up showing this tab's recent
   log entries + the current status detail.
3. Click **"Copy log"**. The full log for *this tab only* is copied
   to your clipboard, including a header with the script version,
   tab id, URL, and current status.
4. Paste it into the bug report (GitHub issue, Slack, email).

The log is per-tab: if you have multiple PR tabs open, each tab's
button copies only that tab's history. Click **"Clear log"** to
reset between repro attempts; this records a per-tab cutoff
timestamp so entries written before the clear no longer appear in
*this tab's* panel view. The shared `goodies-userscript:actionlog`
ring buffer is not modified — other tabs' views and
`window.__goodiesActionLog()` still see the full history.

The log lives in `localStorage` under the key
`goodies-userscript:actionlog` and is capped at 100 entries (oldest
drop off the back).

For the rare case where you want everything across tabs (e.g. an
intermittent multi-tab race), open DevTools and call
`window.__goodiesActionLog({asText: true})` for the full text dump.

## Update / uninstall

Tampermonkey shows installed scripts in its dashboard. Edit by
clicking the script name; uninstall via the dashboard's trash icon.

When this repo's version updates, re-paste from the source file.
There's no auto-update mechanism (the script's `// @updateURL` is
unset intentionally — auto-updating from a github raw URL would tie
this script to internet access at every page load).

## Known limitations

- **Browser-only.** Doesn't work in headless CI, freshly-set-up
  machines without Tampermonkey, or someone else's environment.
  Watcher's Step 0j fallback prompts the user in those cases.
- **Watcher must be running.** v1.0 doesn't react to pushes on
  its own. If the user hasn't run `/goodies-watch`, no marker
  exists for the userscript to act on. The status dot stays
  green-observing.
- **GitHub UI-dependent for the click.** The visible-text
  heuristic for the request-review button is the only DOM
  contract left. Layer A action log will surface
  `click-skipped-no-button` if this breaks.
- **Push detection requires the watcher to run.** The userscript
  does NOT independently detect pushes anymore (v0.x did via
  timeline `MutationObserver`, but v1.0 retired this in favor of
  the watcher's gh-API view). If `/goodies-watch` isn't running,
  pushes go unnoticed.

## Companion documentation

- `docs/design/userscripts-copilot-watch-handshake.md` — v1.0
  design (architecture, decision tree, trade-offs)
- `docs/design/userscripts-copilot-request-review.md` — v0.x
  design (DOM-heuristic detection; **superseded** by v1.0, kept
  for archaeology)
- `modules/claude/README.md` — top-level claude module README
- `modules/claude/commands/goodies-watch.md` — the slash command
  this script complements; Step 0 of its SOP encodes the marker
  post/strip handshake.
