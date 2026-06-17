# userscripts: Copilot auto-request-review — design (v0.x, SUPERSEDED)

> **⚠ Superseded.** This document describes v0.x of the userscript,
> which used DOM heuristics (visible-text scans of the reviewer
> sidebar, comment threads, timeline) to decide when to click. It has
> been **superseded by v1.0** — see
> [`userscripts-copilot-watch-handshake.md`](./userscripts-copilot-watch-handshake.md).
>
> Real-world dogfooding revealed that the visible-text matchers don't
> reliably detect Copilot's "Approved" / busy / reviewed states across
> GitHub UI variations (icon + screen-reader-only text). The v1.0
> design moves all decision logic to `goodies-watch` (which has
> authoritative state via gh API) and reduces the userscript to a
> thin actuator that clicks on demand.
>
> This document is preserved for **archaeology** — the v0.x patterns
> (push-marker timeline observer, COPILOT_BUSY_MARKERS chains,
> sidebar scoping, cross-tab localStorage lock) may be useful
> reference for similar future userscripts. The patterns themselves
> are sound; they just weren't the right contract for *this* problem.

A browser-side userscript that auto-clicks the Copilot reviewer's
"Re-request review" button on GitHub PR pages when a push is detected,
**only when GitHub's own auto-trigger doesn't fire**.

Implementation: `modules/claude/scripts/tampermonkey/copilot-request-review.user.js` (now at v1.0; this doc describes the v0.x line).

## Problem

Some GitHub repos disable the rule that auto-triggers Copilot code
review on push. This includes most org-managed repos with branch
protection policies, including (confirmed) `intel-sandbox/...` and
(confirmed 2026-06-16) the user's personal `TianyouLi/goodies` repo.
On those repos every push has required a manual click on the Copilot
reviewer's "Re-request review" button to draw a fresh review.

The slash command `goodies-watch` had a `force-push retry` rule meant
to nudge stuck reviews. But when the trigger is disabled, retrying
doesn't help — the new push event also doesn't reach Copilot's queue.
The retries were churn.

The right fix is upstream: solve trigger reliability in the browser,
where the user is already opening PR tabs and pushing commits. A
browser userscript can detect the push and click the request-review
button without forcing the user to refresh, scroll, or remember.

### Non-goals

- **Replace GitHub's auto-trigger when it works.** When auto-trigger
  fires, the script must stay out of the way — clicking redundantly
  could re-queue Copilot's review, possibly cancel an in-progress
  review, or trigger duplicate review-request side effects. The script
  is a *backup* for trigger-off repos, not a *replacement* for
  trigger-on ones.
- **Cover headless / non-browser environments.** The script lives in
  Tampermonkey; it requires a browser, the extension installed, and
  the PR tab open. CI, server-side workflows, fresh laptops without
  Tampermonkey installed — none are in scope. The `goodies-watch`
  slash command retains a robust mode for those cases.
- **Detect pushes by other people on PRs you're watching.** The
  script observes the *open tab's* DOM. A push by a co-author or PR
  rebase happening while you're not on the PR page won't be detected
  until you navigate back into the PR (covered by the SPA-nav path).
- **Cross-instance synchronization.** Tabs on the same browser sync
  via `localStorage`; tabs across different browsers / different
  machines do not. This is a personal-flow tool, not a multi-user
  coordinator.
- **Auto-update from a remote URL.** The userscript's `// @updateURL`
  is intentionally unset — auto-updating from a github raw URL would
  tie the script to internet access at every page load. Updates are
  manual: re-paste from the source file when the goodies repo changes.

## Design

The script's job in one sentence: **on a GitHub PR page, when a push
event is detected and GitHub's auto-trigger does not fire within 10
seconds, click the Copilot reviewer's request-review button — exactly
once, even across multiple tabs of the same PR.**

That sentence has four orthogonal concerns, each its own section
below: detection, gating, action, and coordination.

### 1. Detection: when is the script supposed to consider acting?

Three triggers, in priority order:

1. **Push detected via `MutationObserver`** on the PR's conversation
   timeline (primary). When a push lands, GitHub appends a
   "force-pushed" or "pushed N commit" entry to the timeline. The
   observer fires; the script debounces 1.5s for the timeline to
   settle, then enters the gating phase.

2. **SPA navigation into a PR page** (fallback). GitHub is a SPA;
   navigating between PR sub-tabs or arriving from the dashboard
   doesn't fire `DOMContentLoaded`. The script listens to `popstate`,
   `turbo:load`, `pjax:end`, and polls the URL every 2s as a
   safety net. On detected navigation into a PR, the script re-arms
   the timeline observer for the new DOM and checks current state
   once (in case a push happened while we were elsewhere).

3. **Initial PR page load** (fallback). The first page-load on a PR
   page does an immediate state check, primarily to handle the case
   where the user opens a PR after a push happened but before
   anything triggered review.

Why MutationObserver and not WebSocket / events API polling: the
timeline is GitHub's own authoritative record of pushes, already
delivered to the open tab via GitHub's own real-time channel. Tapping
that delivery is zero additional cost; events-API polling would
require periodic `fetch()` calls on a token, more state, more failure
modes.

### 2. Gating: should we actually click?

Three filters, applied in order. Any filter rejecting the click means
no click happens.

1. **Cross-tab lock.** If a sibling tab on the same PR has acted
   recently (within 30s), this tab skips. Prevents toast spam +
   theoretical click race when the same PR is open in multiple tabs.
   See section 4 for details.

2. **Already-busy check.** Before clicking, scan the Copilot reviewer's
   row for visible text indicating Copilot is already reviewing or has
   submitted a recent review. Markers: `"Review pending"`,
   `"Reviewing"`, `"Review in progress"`, `"Approved"`, `"Commented"`,
   `"Requested changes"`. If any appear, skip the click.

3. **Auto-trigger observation window (10 seconds).** Specific to
   push-detected triggers (not initial-load or SPA-nav, which fire
   the click directly after the busy check). After push detection,
   open a 10s window during which the script polls the Copilot row
   every 1s. If during the window Copilot's status flips to a busy
   marker (auto-trigger fired), skip the click. If the window
   expires unchanged (auto-trigger didn't fire), click.

The 10s window is the central design tunable. **Too short** (1-2s):
the script preempts a working auto-trigger, defeating the purpose.
**Too long** (30+s): the script feels unresponsive on auto-trigger-
off repos. **10s is the sweet spot**: most auto-triggers fire within
5s observed empirically; 10s gives margin without making the
trigger-off case painfully slow. The user-visible cost on trigger-off
repos is a 10-second wait between push and review request; on
trigger-on repos there is no cost (script silently observes, never
acts).

### 3. Action: what does clicking entail?

After all gates pass, find the request-review button:

1. Walk all `<button>`, `<a role="button">`, `<summary>` elements.
2. Filter to those whose visible `textContent` matches `"re-request
   review"` or `"request review"` (case-insensitive).
3. Walk up to 6 ancestors checking for `"copilot"` in surrounding
   text — confirms the button belongs to the Copilot reviewer, not
   a generic request-review button for the whole PR.
4. Final pre-click check: button is enabled (not `disabled`,
   `aria-disabled`), and visible (non-zero rect). If not, skip.
5. Call `button.click()`.

After the click: write the cross-tab lock with `action: "clicked"`,
flash a green toast (`"Copilot review requested"`), continue
observing for the next push.

If no busy markers appear in the row but the button cannot be
clicked, this is treated as a state we don't understand — log
verbosely in DevTools and skip. Defensive default.

#### Why visible text instead of aria-label

aria-labels are kept stable for accessibility *in theory*, but
GitHub does change them periodically. Visible text is what the user
sees on screen; matching it is more honest and produces more
predictable behavior under UI churn. The cost is fragility to text-
changes (e.g. wording drift from "Re-request review" to "Request
re-review"), which is exactly as fragile as aria-label matching but
easier for a human maintainer to spot.

#### Why no `data-testid` or class-name selectors

GitHub's class names churn across deploys — the same selector that
worked yesterday breaks today. `data-testid` attributes appear on
some elements but not others, and aren't applied consistently to
the request-review button. Visible text + textual-proximity
("copilot" appears in surrounding DOM) is the most stable
combination available.

### 4. Coordination: multi-tab without race conditions

When the same PR is open in multiple tabs, all of them see the same
timeline updates. Without coordination, all of them race to click
the request-review button. The naive worst-case: 3 tabs → 3 click
attempts → potentially 3 review requests in Copilot's queue.

Coordination via `localStorage`:

- **Lock key shape:** `goodies-userscript:<owner>/<repo>#<PR>:lock`
- **Value:** JSON `{tabId, action, at}` where `action` is one of
  `"clicked"` or `"auto-trigger-fired"`, `at` is `Date.now()`,
  `tabId` is a per-tab random ID generated once per script load.
- **TTL:** 30 seconds. Covers GitHub's eventual-consistency delay
  between tabs receiving DOM updates.

Two interaction patterns:

1. **Pre-click read.** Before any click, read the lock. If a recent
   entry from a different `tabId` is present, skip — sibling tab
   already acted.

2. **`storage` event listener.** When a sibling tab writes the
   lock, this tab cancels its pending observation window (if any)
   and shows a gray "Another tab handled this" toast.

The combination handles all four scenarios:

- **Different PRs, multiple tabs.** Each tab's lock key is per-PR;
  no cross-PR interference.
- **Same PR, multiple tabs, push detected.** First tab to finish its
  observation window (or detect auto-trigger) writes the lock; other
  tabs see the storage event and cancel.
- **Same PR, multiple tabs, both detect simultaneously.** Race
  condition is bounded by the localStorage write atomicity. Worst
  case both write within milliseconds; both check the lock; one of
  them sees its own entry and proceeds, one sees the other's. In
  practice, observation-window jitter (poll cadence, debounce) makes
  exact simultaneity unlikely.
- **Tab opened before script was installed.** Older tab doesn't
  observe; newer tab handles all detection. No coordination
  required, no failure mode.

### 5. Observability: per-tab status panel + action log

The script can fail silently in two distinct ways: GitHub renames a
selector (push detection silently dies), or the request-review button
can't be found at click time (Copilot row's DOM shape shifted). Both
modes look identical to a user — "I pushed; nothing happened." Asking
the user to open DevTools and read source is too high a cost.

Two cooperating layers:

**Layer A — persistent action log.** Every notable state transition
appends one entry to a ring buffer in `localStorage`
(`goodies-userscript:actionlog`, capped at 100 entries). Each entry
carries timestamp, tab id, URL, event kind, and a small detail
object. The ring is global across tabs, so a single user investigation
can correlate behavior across all PR tabs they had open.
`window.__goodiesActionLog({asText: true})` exposes the formatted text
for DevTools-aware investigation.

**Layer B — per-tab status panel.** A small colored dot in the
bottom-right corner of every PR page reflects *this tab's* in-memory
status. Click the dot to expand a panel showing this tab's recent log
entries + a **"Copy log"** button that copies the tab-filtered log
(with header: script version, tab id, URL, current status) to the
clipboard. A **"Clear log"** button removes only this tab's entries.

The panel is strictly per-tab. The dot reflects this tab's in-memory
state machine, not a localStorage read; the log view filters to
`tab_id === TAB_ID`; the copy button copies only this tab's entries.
Mixing tabs into the panel UI would mean a healthy tab shows red
because some other tab errored, which would be misleading. Each tab
investigates its own behavior.

**Two colors only — green / red.** Green = working as designed
(loaded, observing, acting, recently succeeded, correctly stayed out
of the way for auto-trigger). Red = NOT doing its job (selector chain
stale, request-review button not found, button found but unclickable,
unhandled exception). Yellow / "degraded" was considered and
rejected: an intermediate color papers over real failures with a
softer signal and would invite users to ignore them. We expect the
script to work; if it isn't, that's red, not "yellow." A hover tooltip
names the precise label (`selector-failed`, `no-button-found`,
`exception`) for finer-grained investigation.

**Why bottom-right, not top-right.** The toast already lives at
top-right; placing the panel/dot at the same corner would collide.
Bottom-right separates the two visually: the toast is transient
(action-taken / observed-event), the panel is persistent (current
state).

**Why default-collapsed (dot only).** Default-on full panel would
permanently occupy ~400px of viewport. The dot is 14×14px and
peripherally noticeable on color change. The expanded panel is for
investigation, not ambient awareness.

**Why poll-driven log refresh, not push-driven only.** When the panel
is expanded, `appendLog()` notifies a registered callback so the panel
refreshes immediately. But the panel also re-reads on expand to catch
any entries written before the panel was first opened (the
`script-loaded` entry, for instance, fires before `tryEnsurePanel()`
attaches). The callback is the fast path; the read-on-expand is the
correctness backstop.

### 6. Strict scoping: where the script will and won't run

Three layers of scope enforcement, defense in depth:

1. **`@match https://github.com/*/*/pull/*`** — Tampermonkey only
   injects on URLs matching this pattern. The script literally
   cannot load on non-PR pages. Includes all PR sub-routes
   (`/files`, `/commits`, `/checks`).

2. **Hostname guard at script start.** `if (location.hostname !==
   'github.com') return;` Belt-and-suspenders against future
   `@match` misconfiguration or extension bugs. Not a strict-
   subset check; runs only on the public github.com host (excludes
   any GHES instance unless added explicitly to `@match`).

3. **Strict path regex.** `/^\/[^/]+\/[^/]+\/pull\/\d+(?:\/|$)/`.
   The URL-change handler and initial-fire logic both check this.
   Even if `@match` and the hostname guard let something through,
   the regex requires the exact `<owner>/<repo>/pull/<num>` shape.

Critically: **no `document.body` fallback** in the timeline
selector chain. If `TIMELINE_SELECTORS` (`#discussion_bucket`,
`.js-discussion`, `main`) all fail, push-detection is silently
disabled. Initial-load + SPA-nav paths still work, but the
MutationObserver does not attach. This is intentional: a broad
`document.body` observer would catch unrelated DOM mutations and
risk false-positive matches on the `"pushed"` text marker
(comments, file diffs, code blocks could plausibly contain
"pushed" in unrelated contexts).

The trade-off: when GitHub renames its timeline container, push-
detection silently breaks until someone updates `TIMELINE_SELECTORS`.
The DevTools console logs an explicit warning naming the broken
selectors and the fix locus when this happens — readable in <30s
and the maintenance path is clear.

## State machine

```
[script loaded]
       │
       ▼
hostname ≠ github.com? ─── yes ──▶ [refuse + log, exit]
       │ no
       ▼
isOnPRPage()? ─── no ──▶ [register SPA listeners, idle]
       │ yes
       ▼
[initial-fire]
       │
       ▼
maybeRequestCopilotReview('initial PR page load')
       │
       ▼
attach MutationObserver on timeline (or skip with warning if no selector matches)
       │
       └─▶ idle, listening for:
              - timeline mutation (push)
              - SPA navigation
              - storage event (sibling tab acted)


[on timeline mutation: PUSH_MARKERS in added node]
       │
       ▼
[debounce 1.5s]
       │
       ▼
maybeRequestCopilotReview('push detected in timeline')
       │
       ├─▶ cross-tab lock present? ── yes ──▶ [skip + log]
       │
       ├─▶ Copilot busy now? ── yes ──▶ [write lock 'auto-trigger-fired',
       │                                  gray toast 'Copilot already on it',
       │                                  exit]
       │
       └─▶ open auto-trigger observation window
              │
              ├─[every 1s] poll busy state
              │     │
              │     ├─ became busy ─▶ [write lock 'auto-trigger-fired',
              │     │                  gray toast 'Auto-trigger fired',
              │     │                  cancel window]
              │
              └─[at 10s] window expired
                    │
                    └─▶ performClick('observation window expired')
                          │
                          ├─▶ button.click()
                          ├─▶ write lock 'clicked'
                          └─▶ green toast 'Copilot review requested'


[on storage event: sibling tab wrote lock]
       │
       └─▶ cancel pending observation, gray toast 'Another tab handled this'


[on SPA navigation into a different PR]
       │
       └─▶ disconnect old observer, cancel old window,
           re-attach observer on new timeline,
           maybeRequestCopilotReview('arrived on PR via SPA navigation')
```

## Trade-offs

**Auto-trigger awareness adds 10s latency on trigger-off repos.**
Without it, the script would click immediately on push detection — but
that produces redundant clicks on trigger-on repos. The 10s window
makes the script correct on both classes of repo at the cost of a
visible delay where the script's the one doing work. Acceptable
because trigger-off repos are the friction case anyway; another 10s
on top of "already required a manual click before" is an improvement,
not a regression.

**Cross-tab lock is a localStorage write per push.** Negligible
cost in storage / latency. The 30s TTL means stale entries auto-
expire even if the writing tab crashes mid-action.

**Visible-text matching can break on UI changes.** Same fragility
as any approach to GitHub's UI; the alternatives (class names,
data-testid) are equally or more fragile. Mitigation: clearly
documented maintenance loci (REQUEST_BUTTON_TEXTS,
COPILOT_BUSY_MARKERS, TIMELINE_SELECTORS), verbose DevTools logging
that surfaces stale selectors visibly, and the bats tests that
guard against silent regressions in the script's own structure.

**Verbose logging is noisy by default.** During the dogfood phase
(first weeks of usage), seeing the script's reasoning in DevTools
is part of the safety story — users can verify it's behaving
correctly without reading source. Once trusted, `VERBOSE = false`
silences it. Default-noisy is the conservative choice.

**No retry / queue.** If a click fails (the button vanishes between
detection and click — a rare race), the script logs and gives up.
The next push will re-trigger detection naturally; no need for a
retry loop that could compound errors.

**Browser-only doesn't cover all flows.** The user might push from
CI, from a forge bot, from a phone app, from a co-author. None of
these are visible to the userscript. `goodies-watch` retains a
robust path for these cases (the slash command can poll the API
directly).

## Verification

- **Bats assertions** in `tests/modules/claude.bats` (v0.x era) used
  to guard structural anchors of v0.x's script:
  - File exists with `// ==UserScript==` header
  - `@match` is `https://github.com/*/*/pull/*`
  - Uses `MutationObserver` (push-detection, not page-load-only) —
    **note: this assertion was inverted in v1.0.** Current bats
    asserts the userscript does NOT use `MutationObserver` for push
    detection (v1.0 polls the body for marker stanzas instead).
    This v0.x doc is preserved as archaeology; refer to current
    `tests/modules/claude.bats` for the live assertions.
  - Uses `REQUEST_BUTTON_TEXTS` + `textContent` (visible-text matching)
  - Does not regress to a `querySelector('button[aria-label]')` style
  - Has the persistent action log (`LOG_KEY`, `appendLog`, `tab_id`,
    `__goodiesActionLog`) and the per-tab panel (`PANEL_DOT_ID`,
    `copyTabLog`, `clearTabLog`, `getTabFilteredLog`)
  - Status indicator is binary green/red — no `setTabStatus('yellow', ...)`
    or `setTabStatus('gray', ...)` regressions
  - README exists alongside the script
  - `install.sh` does NOT symlink the userscript onto the filesystem
- **Syntax check via `node --check`** (run during development) —
  catches accidental JS parse errors. Not a runtime check (the
  script never runs in Node) but a structural one.
- **Dogfood plan:** install via Tampermonkey on the user's main
  browser, exercise on PR #37 (currently in flight) and following
  PRs in the goodies-review pattern queue. Promote to others
  (README in user-facing docs, sharing instructions) only after
  confirming the script works for the user's daily flow.

## Maintenance

**When does this script need attention?**

- **GitHub changes the request-review button wording.** Symptom: green
  toast never fires, DevTools logs "no Copilot request-review button
  found" repeatedly. Fix: update `REQUEST_BUTTON_TEXTS` array.
- **GitHub changes Copilot's busy-state wording.** Symptom: script
  clicks redundantly when auto-trigger has fired (user sees both
  green toast and Copilot already-reviewing in sidebar). Fix: update
  `COPILOT_BUSY_MARKERS` array.
- **GitHub renames the timeline container.** Symptom: push detection
  stops working (no toast on push); DevTools logs "no timeline
  selector matched" with a warning. Fix: inspect the PR conversation
  page, find the new container's selector, prepend it to
  `TIMELINE_SELECTORS`.
- **GitHub disables the public PR page entirely or moves it.** Out
  of scope; the script is incompatible.

**When does this script need to evolve?**

- If the user wants to use it in a GHES instance, add the host to
  `@match` (e.g. `// @match https://github.your-corp.com/*/*/pull/*`).
- If the auto-trigger window heuristic proves too short / too long,
  tune `AUTO_TRIGGER_WINDOW_MS`.
- If multi-tab coordination misbehaves on slow networks, tune
  `CROSS_TAB_LOCK_TTL_MS`.

## Linked context

- `modules/claude/scripts/tampermonkey/copilot-request-review.user.js` — implementation
- `modules/claude/scripts/tampermonkey/README.md` — user-facing install + verify
- `modules/claude/README.md` — module-level layout + dependency map
- `modules/claude/commands/goodies-watch.md` — the slash command this
  script complements; see its "Push timing" section for the
  pre-userscript robust-mode behavior
- `modules/claude/commands/goodies-review.md` — also benefits from
  reliable trigger; the goodies-review tool's review cycles use the
  same Copilot request-review button
