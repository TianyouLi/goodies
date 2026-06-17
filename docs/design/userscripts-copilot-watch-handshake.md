# userscripts: Copilot click-trigger via goodies-watch handshake — design

A re-architecture of the Tampermonkey Copilot click-trigger
userscript. Replaces the v0.x DOM-heuristic-driven design with a
narrow actuator that takes commands from `goodies-watch`. The
watcher already has authoritative state via the gh API; the only
thing it can't do reliably is *click the request-review button*
on repos where the auto-trigger is disabled. The userscript
exists for that one job.

Implementation: `modules/claude/scripts/tampermonkey/copilot-request-review.user.js`
(rewritten in this PR), with companion changes in
`modules/claude/commands/goodies-watch.md`.

Supersedes `userscripts-copilot-request-review.md` (v0.x design
doc, kept for archaeology — references the in-browser detection
that v1.0 retires).

## Problem

The v0.x userscript shipped in
[goodies#38](https://github.com/TianyouLi/goodies/pull/38) reads PR
state, Copilot reviewer state, and comment-thread state from the
DOM via visible-text heuristics. Real-world dogfooding on PR #37
revealed that GitHub's reviewer-row text doesn't always match our
`COPILOT_BUSY_MARKERS` / `COPILOT_REVIEWED_MARKERS`, and the script
went red on benign states (Copilot was Approved, but the row's
visible text didn't include the literal word "approved" — possibly
a checkmark icon with screen-reader-only text).

This is the script solving the wrong problem. The list of facts
the v0.x script tries to infer from the DOM is exactly the list of
facts the gh API exposes precisely:

| Fact | DOM heuristic (v0.x) | gh API (v1.0) |
|---|---|---|
| PR state (open/closed/merged) | scan state-pill area | `gh api .../pulls/N --jq .state` |
| Copilot is a reviewer | scan sidebar text | `gh api .../pulls/N/requested_reviewers` |
| Copilot has reviewed | scan reviewer row | `gh api .../pulls/N/reviews` |
| Last review was LGTM | infer from "approved" + 0 threads | `comments since LAST_PUSH == 0` |
| Threads resolved/outdated | scan each thread for badges | GraphQL `reviewThreads.isResolved` / `.isOutdated` |
| Auto-trigger fired after push | 10s observation window polling | check `requested_reviewers` then poll |

Every row of that table is more brittle on the left and more
authoritative on the right. The exception is the bottom row of
**what the script does**, which is invisible in the table:

| Action | API | Browser |
|---|---|---|
| Click "Request review" on Copilot | unreliable for org-managed repos | exact match for what the user does manually |

The API can technically PATCH `requested_reviewers`, but for repos
with org-policy-disabled auto-triggers the request doesn't actually
reach Copilot's queue — same failure mode that motivated the
userscript in the first place. Only a real DOM click reproduces
the manual-click trigger reliably.

So: **the userscript should do exactly that one thing**, and the
watcher should do everything else.

## Design

### One sentence

When `goodies-watch` decides Copilot needs to be re-asked for a
review, it appends a `<details>` stanza to the PR body. The
userscript scans the **rendered PR description DOM** every 5s
for the marker payload, finds the request-review button, clicks
it, and lets the watcher detect the resulting state change via
gh API. The watcher then strips its own marker. The userscript
makes **zero gh API calls** — it scales to unlimited tabs
without rate-limit risk.

### Channel: `<details>` block in the PR body

The marker is added by the watcher to the **end of the PR body**
inside a `<details>` HTML block. The `<details>` element survives
GitHub's markdown→HTML sanitizer (we verified empirically — the
inner text appears in `textContent` of the rendered PR
description). The marker is **visible to humans** as a small
collapsible expando line; clicking the disclosure triangle reveals
the payload. Watcher strips its own marker as soon as Copilot
review goes pending or LGTM, so the visibility window is brief
(typically 5–10 seconds).

```html
<details><summary>goodies-watch handshake (writer=<id>)</summary>

goodies-watch:click-request-review nonce=<random> expires=<iso8601> writer=<watcher-id>
</details>
```

**Channel evolution (real-world testing drove three pivots):**

- **v1.0 — `<!-- ... -->` HTML comment + DOM scan.** Idea: invisible
  to humans, the userscript reads the rendered DOM. Outcome: GitHub
  STRIPS HTML comments during markdown render. The userscript never
  sees the marker in `textContent` or `innerHTML`. **Failed in
  real-world test on PR #39 round 1.**

- **v1.1/v1.2 — `<!-- ... -->` HTML comment + gh API fetch.** Idea:
  preserve the invisible-marker UX by reading the raw `body` field
  via `api.github.com`. ETag conditional requests (304 = free) keep
  most polls outside the rate-limit budget. Outcome: works
  architecturally, but the initial 200 response per tab DOES count.
  Multi-tab testing across an hour blew through the 60/hr anonymous
  limit per IP. **Failed in real-world test on PR #39 round 4.**

- **v1.3 — `<details>` marker + DOM scan (chosen).** Different
  marker form survives the render; userscript reads `textContent`.
  Visible to humans but compact. **Zero gh API calls** — scales to
  unlimited tabs without rate-limit risk.

**Why PR body and not a comment / label / check run.** Considered
four channels for the original v1.0 design:

- **(α) Marker in PR body — chosen.** GitHub-stored, watcher edits
  via `gh api PATCH`, userscript reads via DOM scan. Doesn't
  pollute the PR conversation.
- **(β) Marker comment in conversation timeline** — would post
  a new comment per re-review request. PR #38's 5 fix-rounds
  would have produced 5 marker comments + 5 deletions = noise.
- **(γ) Toggle a label** like `goodies:click-now` — visible as
  a chip; tolerable but still visible.
- **(δ) Check run** — cleaner than a comment, but adds an extra
  channel for the userscript to read (the Checks tab) and
  appears in the PR's Checks summary.

User explicitly rejected high-noise channels: "i dont want to have
a lot of comments in the pr." The `<details>` marker is silent
relative to comments — it's compact, scoped to the description,
self-labeled, and stripped within seconds of Copilot acting.

**Marker shape.** Four required fields:

| Field | Purpose |
|---|---|
| `nonce` | Idempotency token. The userscript clicks at most once per `(writer, nonce)` pair. Watcher generates a fresh nonce per poll. |
| `expires` | Self-cleanup. If watcher dies / loses the user, an old marker auto-expires and the userscript ignores it. |
| `writer` | Watcher-instance UUID generated on watcher startup. Used to disambiguate multiple concurrent watchers (see Trade-offs § multi-watcher). |
| (the literal payload prefix) | `goodies-watch:click-request-review` — the substring the userscript matches on inside the `<details>` text. |

Concrete marker:

```html
<details><summary>goodies-watch handshake (writer=w-7d8f2)</summary>

goodies-watch:click-request-review nonce=0a3f7c2e expires=2026-06-16T15:30:00Z writer=w-7d8f2
</details>
```

Watcher writes the marker by appending to (or replacing within)
the PR body via:

```sh
gh api --method PATCH /repos/<OWNER>/<REPO>/pulls/<N> \
  -f body="$(NEW_BODY_WITH_MARKER)"
```

The watcher's body-edit logic is **idempotent**: it strips any
prior `<details>` marker block whose payload includes the watcher's
own writer ID, then appends the new one. The strip uses a
multiline Python `re.sub` (the `<details>` block spans 3+ lines).
WATCHER_ID is passed via environment variable and run through
`re.escape()` — not interpolated into the Python source — to
prevent regex metacharacters from corrupting the strip pattern.
This protects the user's content if the watcher edits the body
more than once.

### Watcher decision tree (gh-API only)

The decision logic that v0.x tried to encode in JavaScript moves
into the watcher's prompt. Each step is one or two `gh api` calls.

```
On every poll (every 3 min by default):

Step 0: Is the PR still open?
  gh api .../pulls/N --jq .state
  closed/merged → strip any marker, exit gracefully

Step 1: Is Copilot a requested reviewer?
  gh api .../pulls/N/requested_reviewers
  no  → strip any marker, exit gracefully (script not applicable)
  yes → continue

Step 2: Is Copilot review currently pending? (already in flight)
  gh api .../pulls/N/requested_reviewers
  pending → exit (auto-trigger handled it; nothing to do)
  not    → continue

Step 3: Has Copilot ever reviewed this PR?
  gh api .../pulls/N/reviews → submitted reviews
  no       → expected_to_act=YES (initial review missing — request)
  yes     → continue

Step 4: Did the last push happen AFTER Copilot's last review?
  Compare LAST_PUSH vs LAST_REVIEW (existing watcher logic).
  no  → exit (review is fresh; don't re-request)
  yes → continue

Step 5: Did Copilot's last review have ANY comments at all?
  Comments-on-the-most-recent-review-event count
  no (LGTM)  → exit (Copilot was happy last time; only the user
                can decide to ask again — STOP)
  yes        → continue

Step 6: Are all those comments resolved or outdated?
  GraphQL reviewThreads.isResolved / .isOutdated for each thread
  with a Copilot author
  no  → exit (user hasn't finished addressing yet)
  yes → continue

Step 7: Post the marker (if not already present and unexpired).
  Generate fresh nonce + expires=NOW+10min
  PATCH PR body to include the marker stanza

Step 8: Wait for ack.
  Poll Copilot's requested_reviewers + reviews state.
  When a new "review pending" or new submitted_at appears
  AFTER the marker was posted, the userscript clicked it.
  Strip the marker.

Step 9: Timeout fallback.
  If the marker has been in the body for > expires_in and no
  state change is observed, strip the marker and prompt the user
  (the existing manual-trigger path).
```

This collapses two pieces of v0.x logic the watcher already has
inside its current SOP:

- The "PUSH_AGE >= 900s" stalled-push prompt (Step 9 fallback).
- The Case A LGTM detection (Step 5).

### Userscript responsibility (narrowed)

```
On script load + on URL change + every 5s (DOM poll):
  1. If not on a PR page → hide UI, do nothing.
  2. Read PR description's textContent from the DOM
     (.js-comment-body.markdown-body or fallback chain).
  3. Hash the text, compare to last seen. If unchanged, return.
  4. Scan textContent for marker payload matching:
       /goodies-watch:click-request-review\s+nonce=(\S+)\s+expires=(\S+)\s+writer=(\S+)/
     Iterate fresh (non-expired) markers in soonest-to-expire order
     and return the first NOT-yet-acted (writer,nonce) pair.
  5. If marker missing or expired → green dot, no-op.
  6. If marker present and (writer,nonce) not yet acted by this tab:
       Find request-review button via visible-text + copilot-proximity.
       If found and clickable → click → record (writer,nonce) as acted.
       If button missing/unclickable → red dot, log to action log.
  7. Status panel + action log unchanged (Layer A observability
     stays intact for click-time DOM failures).
```

#### Detection cadence: 5s DOM scan (zero gh API)

**Why DOM with `<details>` marker, not API.** Three pivots got us
here:

| Version | Channel | Marker form | Outcome |
|---|---|---|---|
| v1.0 | DOM scrape | `<!-- ... -->` | HTML comments stripped during render — userscript never saw markers |
| v1.1/v1.2 | gh API + ETag | `<!-- ... -->` | Initial 200 burns rate-limit budget; multi-tab testing hit 60/hr anonymous limit |
| **v1.3** | **DOM scrape** | **`<details>...</details>`** | **`<details>` survives sanitization; payload visible in textContent; zero API calls** |

DOM scans are free and scale to unlimited tabs. The PR description's
`textContent` includes the inner text of `<details>` blocks, so the
marker payload is reachable.

**Choice of 5s.** Worst-case latency (user push → click) is
bounded by *watcher's 3-min cron + userscript's 5s DOM poll* ≈ ~3
min. Tighter polls don't help because the cron is the dominant
contributor. 5s gives snappy feedback without measurable battery
cost (textContent read is microseconds).

**Selector chain for description body** (with fallback for GitHub
class-name churn):

```js
const PR_BODY_SELECTORS = [
    '.js-comment-body.markdown-body',           // current
    '.markdown-body',                            // fallback
    '[class*="comment-body"]',                   // generic
];
```

#### Time source: Date.now() (skew not compensated)

The marker's `expires` is a GitHub-server-clock ISO8601 timestamp,
written by the watcher using the `Date:` header from `gh api`. The
userscript reads it against `Date.now()` directly — no skew
compensation.

Earlier versions tried two skew-compensation approaches:

- **HEAD api.github.com → Date header** (v1.1/v1.2). Worked but
  cost an API call against the rate-limit budget the v1.3 pivot
  is trying to eliminate.
- **DOM-derive from `<relative-time datetime>` elements** (v1.3
  first cut). WRONG — those are EVENT timestamps (when a comment
  was posted), not "now". `skew_ms` ended up equal to
  `-(age of newest event)`, real-world observed at 644652ms
  (~10 min). Worse than no skew.

v1.3 final design: use `Date.now()` directly. The marker's 10-min
validity window tolerates a few minutes of browser-clock drift. If
the user's clock is wildly off, markers may briefly appear
expired-when-fresh or fresh-when-expired, and the watcher's next
poll re-posts a fresh marker either way. Wrong skew is worse than
no skew.

**What the userscript no longer does:**

- ❌ Push detection via timeline `MutationObserver` for push events.
- ❌ `COPILOT_BUSY_MARKERS` / `COPILOT_REVIEWED_MARKERS` scanning.
- ❌ 10-second auto-trigger observation window.
- ❌ Comment thread state inference (resolved / outdated).
- ❌ LGTM heuristic.
- ❌ Cross-tab `localStorage` lock.

**Why no localStorage cross-tab lock anymore.** With the
marker-based design, multiple tabs can race to click the
request-review button — but the click is idempotent at the GitHub
level (the second click finds the button has vanished, exits
silently). And acted-nonces are recorded per-tab in the action log
(persistent localStorage ring buffer), so a tab that already acted
won't re-attempt for the same nonce. The cross-tab lock was
solving a problem that disappears under the new model.

The userscript's *decision logic* shrinks dramatically (the v0.x
state-detection code paths — busy markers, thread state, observation
window, push markers, timeline observer — all retire). The total
file size shrinks more modestly, from ~1120 lines to ~1080 lines —
the panel UI, action log infrastructure, and CSS-via-JS are kept
verbatim from v0.x because they were already correct and unrelated
to the decision logic the rewrite targets. The win is in *what the
script does*, not in raw line count: every DOM read past the
request-review button finder is gone.

### Acknowledgment lifecycle

The handshake is **implicit** — the watcher detects the click via
gh API state change, not via an explicit ack message from the
userscript.

```
Watcher posts marker  ────►  Userscript polls PR body
                                    │
                                    ▼
                              Sees marker, clicks button
                                    │
                                    ▼
                              GitHub records the request
                                    │
Watcher polls API         ◄─────────┘
sees Copilot.requested_reviewers became "pending" again
or sees Copilot's submitted_at advanced
                                    │
                                    ▼
                       Watcher strips marker from PR body
```

No explicit ack message means **no extra writes to PR body or
comments by the userscript**. The userscript is read-only on
GitHub state except for the one DOM click. This keeps the design
honest: the script's only side effect on GitHub is the click
itself.

**Failure modes the implicit-ack design handles:**

| Failure | Detection | Recovery |
|---|---|---|
| Userscript not installed / browser closed | Marker sits past expires; no state change | Watcher's Step 9 fallback strips marker, prompts user |
| Userscript ran but DOM heuristic for button stale | Action log entry: `red, no-button-found`; Layer A capture | Same Step 9 fallback (watcher sees no state change → asks user) |
| Userscript clicked but GitHub didn't queue review (org-policy issue) | Same — no state change observed | Same Step 9 fallback. This is the original problem the userscript was supposed to solve, so the fact that it falls back here is degenerate / OK |
| Marker survives despite successful click (race: click → strip → another tab acts) | Action log shows the second tab finding marker missing or already acted | Acted-nonce table in localStorage prevents re-action; benign |
| Multiple watchers running (different sessions) | Both post markers; userscript acts on the first; second watcher's strip regex matches only its own `writer` ID, so it cannot strip another watcher's live marker | Watcher strips only markers whose payload contains `writer=<own-id>` — writer uniqueness per session is sufficient; nonce is not required in the strip predicate |

### Status indicator (green/red)

Same colors as v0.x, semantics tightened by the new model:

| State | Color | Tooltip |
|---|---|---|
| Not on a PR page | hidden | (panel removed from DOM) |
| On PR page, no marker present, idle | green | "observing" |
| Marker present, attempting to click | green | "clicking on watcher request" |
| Click succeeded | green | "clicked: nonce=..." |
| Marker present but button not found / unclickable | **red** | "watcher requested click but button missing" |
| Script exception caught | **red** | "exception" |

v1.0 ships **two colors only — green / red.** PR-state detection
moved to the watcher (Step 0a), so the userscript never sees a
marker on a closed/merged PR — it stays green-observing on those.
A "gray = N/A by design" tier was considered for closed/merged
plus the "Copilot not a reviewer" case but was retired because
both are now handled watcher-side: the watcher simply doesn't post
a marker, and the userscript stays correctly green-observing with
nothing to do. Adding the gray tier would require the userscript
to consult the gh API to detect those states — exactly the
brittleness v1.0 retired.

## Trade-offs

**Latency budget.** v0.x: ~12s end-to-end (1.5s push debounce +
10s observation window). v1.0: dominated by the watcher's 3-min
cron interval. Worst case is ~3 min between user push and click.

User accepted this explicitly: "faster is better, but we need it
to work." Lowering the cron interval is a separate decision (each
poll calls 4-6 gh API calls; tightening the interval has API-rate
cost).

**The watcher must be running.** v0.x worked even if the user
never invoked `/goodies-watch` — the script reacted to pushes
directly. v1.0 requires the watcher to be active for the
click to happen. Acceptable because the watcher is part of the
goodies workflow anyway: PRs that need re-trigger are PRs where
the user is actively iterating.

**Marker hygiene.** Watcher must edit PR body without disturbing
the user's content. Strategy: a multiline strip+append. The marker
is a `<details>...</details>` block (3+ lines); strip any such
block whose payload line includes `writer=<WATCHER_ID>`, then
append the new block. WATCHER_ID is passed via env var and
`re.escape()`d before use as a regex literal — not interpolated
into the Python source — to prevent metacharacter injection.
Idempotent for any number of edits. Unit-tested via shell tests
in goodies-watch's bats suite.

**Multi-tab simplification.** v0.x maintained a per-PR
localStorage lock with 30s TTL across all tabs of the same PR to
avoid double-clicks. v1.0 doesn't need it — the click is naturally
idempotent (button vanishes after click), and the acted-(writer,nonce)
record per-tab handles the re-action case. One less concept; one
less brittleness vector.

**Multi-watcher coexistence.** Each watcher instance generates a
unique writer-ID (`writer=<uuid>`) at startup and includes it in
every marker it posts. Strip rules:

- A watcher only strips markers whose `writer` matches its own ID,
  OR whose `expires` is in the past (any watcher cleans up stale
  markers, regardless of who wrote them).
- A watcher never strips another watcher's live marker.

Two watchers running simultaneously will produce two markers per
push round (one each). The userscript clicks on whichever marker
is freshest (closest non-past expires) — the click is idempotent,
so even if both markers are still present, only one click happens.
Each watcher independently observes the resulting state change
(Copilot review_pending or new submitted_at) and strips its own
marker. The other watcher's marker eventually expires naturally
or gets stripped by its own poll loop. No inter-watcher
coordination required.

This makes "multiple `/goodies-watch` sessions on the same PR"
safe by design — the worst case is one stale marker for up to
`expires_in` minutes, which is already the timeout fallback
behavior.

**No PR-creation auto-trigger assumption.** v0.x had a Step 3
that exited green if "PR-creation auto-trigger probably handled
it." v1.0 doesn't assume this — Step 3 = "no review yet" sets
expected_to_act=YES, and the watcher will eventually post the
marker. If GitHub did auto-trigger the initial review, Step 2
catches it (review is pending) and Step 3 never runs.

**Failure modes are observable, not silent.** Layer A action log
in the userscript stays. If the marker is found but the button
isn't, the dot turns red and the log captures details. The user
copies the log into a bug report — same workflow that surfaced
the v0.x bugs.

## Verification

**Unit/static (bats + node --check):**
- Userscript syntax valid (`node --check`)
- Userscript metadata block valid (`@match`, `@version`, name)
- Userscript contains the marker-detection regex
- Userscript does NOT contain the v0.x detection constants
  (`COPILOT_BUSY_MARKERS`, `THREAD_RESOLVED_MARKERS`, etc.) — they
  moved to the watcher
- Watcher SOP file mentions the marker stanza format and includes
  the strip+append shell logic
- All bats tests pass

**Integration (manual, browser):**

Three scenarios in dogfood. Track each via the action log
(`window.__goodiesActionLog({asText: true})` in DevTools, or the
panel's Copy log button).

**Scenario A — happy path on a goodies PR:**
1. Push fix-round commits to a PR where `/goodies-watch` is running.
2. Within 3 min (one watcher cron interval), the watcher posts a
   marker to PR body.
3. Within ~5s (one userscript DOM-poll interval), the userscript
   detects the marker in the rendered PR description's textContent
   and clicks the button. Zero fetches — DOM reads only.
4. Green toast + green dot + log entry `click-attempted`.
5. Watcher's next poll (next cron tick) sees
   Copilot.requested_reviewers became pending; strips the marker.
6. Eventually Copilot review lands.

End-to-end worst case: ~3min 5s (3min cron + 5s DOM poll).

**Scenario B — userscript not installed:**
1. Same setup, but no Tampermonkey.
2. Marker sits past `expires` (10 min).
3. Watcher Step 0j strips the marker and prompts user with the
   familiar [a]/[b]/[c] choice.

**Scenario C — Copilot was already approving (LGTM):**
1. Watcher's Step 5 sees the most recent review had 0 comments.
2. Watcher exits without posting a marker.
3. Userscript dot stays green-observing.
4. PR sits with last LGTM intact; user manually clicks if they
   want a re-review.

**End-to-end:** all three scenarios on a real goodies PR before
landing v1.0.

## Maintenance

**When does this design need attention?**

- **GitHub renames the request-review button.** Same as v0.x —
  the only DOM heuristic the userscript still uses. Update
  `REQUEST_BUTTON_TEXTS`. Layer A action log will show
  `no-button-found` to flag this.
- **Watcher finds the gh API stops returning a field it needs.**
  Watcher's SOP fails the relevant step; user sees the watcher's
  prompt with the failure cause.
- **GitHub adds a new state we haven't accounted for** (a new
  reviewer-pending value, a new review type). Update the watcher's
  decision tree.

The userscript itself is far less likely to need maintenance in
v1.0 because it depends on only one DOM contract: the
request-review button's visible text and clickability. Everything
else is gh API.

**Disposition of v0.x assets:**

- The v0.x script (`copilot-request-review.user.js` at the
  pre-v1.0 commit) is replaced wholesale.
- The v0.x design doc
  (`docs/design/userscripts-copilot-request-review.md`) stays
  as archaeology — the in-browser detection design has lessons
  worth preserving (push markers, timeline observer, sandbox
  scoping). Mark it superseded with a pointer to this doc.
- PR #38 is paused and decided after v1.0 ships:
  - If v1.0 lands cleanly, **close** PR #38 (v1.0 supersedes).
  - If v1.0 development reveals v0.x is a useful stepping stone,
    **merge** #38 first, then layer v1.0 on top.

## Linked context

- `modules/claude/scripts/tampermonkey/copilot-request-review.user.js` — implementation (rewritten in this PR)
- `modules/claude/commands/goodies-watch.md` — watcher SOP (updated in this PR)
- `modules/claude/scripts/tampermonkey/README.md` — user-facing install + verify (updated in this PR)
- `docs/design/userscripts-copilot-request-review.md` — superseded v0.x design (kept for archaeology)
- v0.x in flight: TianyouLi/goodies#38 (paused, awaiting v1.0)
