# Tampermonkey userscripts (Claude PR-review helpers)

Browser-side userscripts that complement the goodies Claude commands.
Installed via [Tampermonkey](https://www.tampermonkey.net/) (or
Greasemonkey / Violentmonkey — any compliant userscript manager).

These are **not** managed by `modules/claude/install.sh` because
userscripts live inside a browser extension, not on the filesystem. Each
script is a standalone `.user.js` file that you install through your
extension's UI.

## Why these exist

Some GitHub repos disable the rule that auto-triggers Copilot code review
on push (this is common in org-managed repos with branch-protection
policies). On those repos, the `goodies-watch` slash command was forced
into a force-push retry loop that wasn't actually doing anything — the
push event never reached Copilot's queue because the trigger was off, and
retrying produced more pushes that also didn't trigger.

These userscripts solve the upstream cause: when you visit a PR page, the
script auto-clicks the "Re-request review" button on the Copilot
reviewer (if it's in pending state). With the script installed,
push-trigger reliability comes from the browser, not from server-side
policy you don't control.

## Scripts

### `copilot-request-review.user.js`

Auto-clicks the Copilot reviewer's "Re-request review" / "Request review"
button when a push is detected on the open PR tab — **no refresh
needed**, **only when GitHub's auto-trigger doesn't fire**, and **only
once across multiple tabs of the same PR**.

Design doc: `docs/design/userscripts-copilot-request-review.md` covers
the architectural rationale, state-machine, and trade-offs in detail.
The summary below is the user-facing view.

- **Match pattern:** `https://github.com/*/*/pull/*` (all PR pages,
  including sub-tabs Files/Commits/Checks). Strict-scoped: the script
  also runs hostname + path-regex guards at startup as belt-and-
  suspenders.
- **Push detection:** a `MutationObserver` on the PR's conversation
  timeline catches "force-pushed" / "pushed N commit" entries. When a
  push lands while you have the tab open, the script notices within
  ~1.5s.
- **Auto-trigger awareness (10s observation window):** after detecting
  a push, the script does NOT click immediately. It opens a 10-second
  observation window, polling the Copilot reviewer's row every second.
  If GitHub's own auto-trigger fires (Copilot's status flips to
  "Review pending" / "Reviewing" / "Approved" / etc.), the script does
  nothing — auto-trigger handled it. If 10s pass without state change,
  the script clicks. The script becomes a *backup* for repos where
  auto-trigger is off, not a *replacement* for repos where it works.
- **Multi-tab coordination via `localStorage`:** when one tab clicks
  (or detects auto-trigger), it writes a per-PR lock with a 30s TTL.
  Sibling tabs observing the same PR see the `storage` event, cancel
  any pending observation window, and show a gray informational toast
  ("Another tab handled this") instead of acting.
- **SPA-aware fallback:** if you navigate *into* a PR via SPA
  navigation (e.g. clicking a PR link from the dashboard), the script
  also checks on arrival in case a push happened while you were
  elsewhere. Listens to `popstate` / `turbo:load` / `pjax:end` events
  plus a 2s URL-change poll.
- **Visible feedback (two colors):**
  - **Green toast** ("Copilot review requested") — script took action.
  - **Gray toast** — informational ("Auto-trigger fired, no click
    needed", "Copilot already on it", "Another tab handled this").
    Distinguishes "we did something" from "we observed something."
- **Per-tab status panel + action log.** A small colored dot in the
  bottom-right corner of every PR page shows *this tab's* status —
  **green = working as intended**, **red = NOT doing its job**
  (selector chain stale, button missing, exception caught). Click the
  dot to expand a panel showing this tab's recent action log + a
  **"Copy log"** button that copies the full log to the clipboard for
  bug reports. Each tab is fully independent — the dot shows that
  tab's status, the panel shows that tab's log, "Copy log" copies that
  tab's log only. No DevTools required to investigate. See "Reporting
  bugs" below for the recommended copy-then-paste flow.
- **Verbose logging on by default during the dogfood phase.** Flip
  `VERBOSE = false` in the script once trusted. The action log is
  separate — always on, persisted to `localStorage`, capped at 100
  entries (ring buffer), retrievable via the panel or via DevTools
  (`window.__goodiesActionLog({asText: true})`).

**Selector strategy — visible text, not aria-label.** The script matches
the request-review button by its visible `textContent` (case-insensitive
match against `"re-request review"` / `"request review"`) plus a textual
proximity check that the surrounding DOM mentions `"copilot"`. The same
visible-text approach detects Copilot's busy state (matching `"review
pending"`, `"reviewing"`, `"approved"`, etc. in the Copilot reviewer's
row). Visible text is what the user sees; matching what's on screen is
more honest and more robust than aria-label or class-name matching,
both of which GitHub churns. **When GitHub changes the wording**
(rare but possible), update the relevant constant array in the script:
`REQUEST_BUTTON_TEXTS` for the click target, `COPILOT_BUSY_MARKERS` for
the auto-trigger detection.

**Timeline selector chain.** Push detection observes one of a small
list of historical timeline-container selectors:
`#discussion_bucket` → `.js-discussion` → `main`.
GitHub renames its containers periodically; the chain tries each in
order and uses the first that matches. **If all fail, push-detection
silently disables** — the script does NOT fall back to observing
`document.body` because that would risk firing on unrelated DOM
mutations elsewhere on the page. Initial-load + SPA-nav paths still
work; only push-detection is degraded. Maintenance: when the chain
goes stale, edit `TIMELINE_SELECTORS` in the script.

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

After install, navigate to any GitHub PR page. You should see a
`[goodies/copilot-request-review]` message in the DevTools console
("userscript loaded; @match=..."). **A toast does *not* appear on
mere page navigation** — toasts only fire when the script takes an
action (green) or observes a notable event like auto-trigger firing
or a sibling tab acting (gray). "No toast on page open" is normal,
not a broken install.

## Verify it works

Three scenarios. Note the timing carefully — the script intentionally
waits up to 10 seconds after detecting a push to see if GitHub's own
auto-trigger fires before clicking, so the action-taken (green toast)
path is normally ~10–12 seconds after the push, not ~1 second.

**Scenario A — auto-trigger works (most repos, first push on a new PR):**
1. Open a PR with Copilot in the Reviewers list. Leave the tab open.
2. From a terminal, push a commit to the PR's branch.
3. Timeline updates → MutationObserver fires → 1.5s debounce → 10s
   observation window opens.
4. Within ~5 seconds of the push, GitHub's auto-trigger fires;
   Copilot's status flips to "Review pending" / "Reviewing".
5. The script detects the state change and shows a **gray toast**
   "[goodies/copilot-request-review] Auto-trigger fired (review
   pending)". **No click attempted.** Script stayed out of the way.

**Scenario B — auto-trigger off (org-managed repos, fix-round pushes):**
1. Same setup as A; push happens.
2. 10s observation window expires without auto-trigger.
3. The script clicks the request-review button. **Green toast** appears:
   "[goodies/copilot-request-review] Copilot review requested".
4. Copilot reviewer's status flips to "Review requested".

**Scenario C — same PR open in multiple tabs:**
1. Open PR #N in tab 1 and tab 2 simultaneously.
2. Push happens.
3. Either the first tab's observation window expires and clicks (green
   toast in tab 1; gray "Another tab handled this" toast in tab 2), OR
   the auto-trigger fires (gray toast in both tabs). Only one tab acts.

If no toast ever appears (and you've pushed/navigated as above), open
DevTools console — verbose logging shows the script's reasoning at
each step:
- `userscript loaded; @match=...` — script did load.
- `observing timeline via selector: <sel>` — observer attached.
- `push detected; opening 10000ms observation window for GitHub
  auto-trigger` — push detection fired.
- `auto-trigger fired during observation window (...)` — GitHub fired,
  no click needed.
- `observation window expired with no auto-trigger; clicking now` —
  10s passed, click is happening.
- `no Copilot request-review button found (reason: ...)` — script ran
  but found nothing to click. Possibly Copilot not in reviewers, or
  selector chain stale.

If you see "userscript loaded" but never "observing timeline", the
timeline selector chain may be stale — update `TIMELINE_SELECTORS`.

## Reporting bugs (the easy path)

The script keeps a per-tab action log so the maintainer can diagnose
issues without asking you to open DevTools.

1. Notice the **status dot in the bottom-right corner** of any PR page.
   Green = the script is working as designed; red = it isn't doing its
   job (selector stale, button missing, etc.).
2. **Click the dot** — a panel pops up showing this tab's recent log
   entries + the current status detail.
3. Click **"Copy log"**. The full log for *this tab only* is copied
   to your clipboard, including a header with the script version, the
   tab id, the URL, and the current status.
4. Paste it into the bug report (GitHub issue, Slack, email).

The log is per-tab: if you have multiple PR tabs open, each tab's
button copies only that tab's history. This keeps reports focused on
the failing tab and doesn't leak your unrelated browsing.

The log lives in `localStorage` under the key
`goodies-userscript:actionlog` and is capped at 100 entries (oldest
drop off the back). Click **"Clear log"** to reset between repro
attempts; this only removes the current tab's entries.

For the rare case where you want everything across tabs (e.g. an
intermittent multi-tab race), open DevTools and call
`window.__goodiesActionLog({asText: true})` for the full text dump.

## Update / uninstall

Tampermonkey shows installed scripts in its dashboard. Edit by clicking
the script name; uninstall via the dashboard's trash icon.

When this repo's version updates, re-paste from the source file. There's
no auto-update mechanism (the script's `// @updateURL` is unset
intentionally — auto-updating from a github raw URL would tie this
script to internet access at every page load).

## Known limitations

- **Browser-only.** Doesn't work in headless CI, freshly-set-up machines
  without Tampermonkey, or someone else's environment. Goodies-watch
  retains a robust mode for those cases.
- **GitHub UI-dependent.** Selector heuristics will need maintenance if
  GitHub redesigns the reviewers sidebar or changes button wording.
  Three documented maintenance loci in the script:
  `REQUEST_BUTTON_TEXTS`, `COPILOT_BUSY_MARKERS`, `TIMELINE_SELECTORS`.
- **Push detection requires the PR tab to be open.** The script *does*
  have push detection via a MutationObserver on the conversation
  timeline — but it only fires when a PR tab is actually open in the
  browser. If you push from CLI without ever having the PR open in any
  tab, the script never sees the push. The fallback path (SPA
  navigation handler) catches the case where you navigate into the PR
  *after* a push happened elsewhere — it checks state on arrival.
- **Doesn't help when someone else pushes** to a PR you don't have
  open — same reason as above. Push detection requires *your* tab to
  observe the timeline update.

## Companion documentation

- `modules/claude/README.md` — top-level claude module README documents
  which scripts complement which claude assets.
- `modules/claude/commands/goodies-watch.md` — the slash command this
  script complements; see its "Push timing (throttle prevention)" section
  for the pre-userscript behavior.
