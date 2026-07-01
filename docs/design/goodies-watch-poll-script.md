# goodies-watch: extract polling into shell script — design

Resolves [issue #48](https://github.com/TianyouLi/goodies/issues/48): the
deterministic polling loop currently runs inside a Claude cron prompt, burning
LLM tokens every 3 minutes even when nothing has changed. This design moves all
deterministic logic into a committed Bash script; Claude is invoked only when
actionable findings arrive.

## Problem

`/goodies-watch` creates a CronCreate job whose prompt embeds ~300 lines of
`gh api` logic. Every 3-minute poll re-processes ~160K tokens of accumulated
context just to evaluate deterministic JSON ("is review pending? is push stale?")
and conclude "nothing changed, keep polling." Real-world usage reached $235 in
wasted spend with 160+ identical no-op iterations in a single session.

Two controllable inefficiencies identified in issue #48:
1. LLM used as a deterministic `while` loop — dominant cost driver.
2. Context window bloat from accumulated `gh api` outputs forcing expensive compaction.

This design addresses #1 fully. #2 is eliminated as a consequence (no long-running
Claude session for polling).

## Architecture

```
goodies-watch.md  (Claude prompt — thin)
    │
    ├─ on /goodies-watch invocation:
    │      resolve REPO + PR number
    │      generate WATCHER_ID (w-<prefix>-<random>)
    │      dedup existing cron (CronList → CronDelete if present)
    │      announce: "Watching PR #N on branch B. Polling every 3 minutes."
    │      set up CronCreate (*/3 * * * *, recurring: true)
    │      run first check immediately (don't wait for first cron fire)
    │
    └─ cron prompt (thin — ~55 lines):
           run goodies-watch-poll.sh <REPO> <PR> <WATCHER_ID>
           dispatch on exit code (findings, LGTM squash, fatal)

modules/claude/scripts/goodies-watch-poll.sh  (new)
    ├─ exit 0  → nothing actionable; keep polling silently
    ├─ exit 1  → new findings; JSON written to stdout
    ├─ exit 2  → LGTM; stdout empty
    └─ exit 3  → fatal (PR closed, no access); error string on stdout
```

Claude tokens are consumed only when the script exits 1 or 2. A quiet branch
(no new push, Copilot not done reviewing) costs zero LLM tokens per 3-minute poll.

## `goodies-watch-poll.sh` — logic

Script signature: `goodies-watch-poll.sh <REPO> <PR> <WATCHER_ID>`

All logic is ported from the current `goodies-watch.md` Steps 0–3.
The extraction also includes intentional bug fixes discovered during integration
testing (SIGPIPE from `--paginate | head`, inverted push-vs-review comparison,
comment matching by time window vs exact review ID, wrong squash base branch).

```
Step 0a: PR state
  STATE=$(gh api repos/<REPO>/pulls/<PR> --jq .state)
  closed/merged → strip own marker if present, exit 3 "PR is <STATE>"

Step 0b: Is Copilot a requested reviewer or has ever reviewed?
  COPILOT_REVIEWER=$(gh api repos/<REPO>/pulls/<PR>/requested_reviewers
    --jq '[.users[].login | test("copilot";"i")] | any')
  COPILOT_EVER_COUNT=$(gh api --paginate repos/<REPO>/pulls/<PR>/reviews
    --jq '[.[] | select(.user.login | test("copilot";"i"))] | length' | awk '{s+=$1} END{print s+0}')
  neither → skip to Step 0h (fresh PR, needs first-time request)

Step 0c: Is a review currently pending?
  COPILOT_REVIEWER==true → strip own marker, exit 0

Step 0d: Has Copilot submitted any review?
  COUNT_SUBMITTED=$(... | awk '{s+=$1} END{print s}')
  COUNT_SUBMITTED==0 → expected_to_act=YES, skip to Step 0h

Step 0e: Compare LAST_PUSH vs LAST_REVIEW
  LAST_PUSH > LAST_REVIEW → continue
  else → strip own marker, exit 0

Step 0f: Did last review have inline comments?
  CMT_COUNT_LATEST==0 + APPROVED → strip own marker, exit 2 (LGTM)
  CMT_COUNT_LATEST==0 + non-approval → exit 1 {"action":"findings","comments":[],"review_state":"..."}
  CMT_COUNT_LATEST > 0 → continue

Step 0g: Are all those comments resolved or outdated?
  any open unresolved → continue into Steps 1–3 (surface unreplied comments as findings)
  all dealt with → NEED_REQUEST=true, continue to Step 0h

Step 0h: Request Copilot review (API-first, userscript fallback)
  [same discovery + POST logic as current Step 0h]
  API success → exit 0
  API fail → post Tampermonkey marker in PR body (written once; expires is NOT refreshed on subsequent polls)
    if existing marker's expires has passed (GH_NOW >= expires) →
      write {"action":"timeout_fallback"} to stdout, exit 1
    if existing marker's expires cannot be parsed (malformed) →
      treat as expired: write {"action":"timeout_fallback"}, exit 1
    if no marker yet → write marker (nonce + fixed expires = now + 600s), exit 0
    else (marker valid) → exit 0 (keep waiting for userscript to click)

Step 1: Copilot review pending?
  true → exit 0

Step 2: Find unreplied Copilot inline comments
  [same logic as current Step 2]

Step 3: Staleness + outcome
  COUNT_SUBMITTED==0 → attempt API review request, exit 0
  PUSH_AGE < 180 → exit 0
  PUSH_AGE ≥ 180 + unreplied comments exist:
    write {"action":"findings","comments":[...]} to stdout, exit 1
  PUSH_AGE ≥ 180 + no unreplied comments + review fresh:
    strip own marker, exit 2
```

### Stdout protocol

On **exit 1**, one JSON line to stdout (one of three variants):
```json
{"action": "findings", "comments": [{"id": 123, "path": "...", "line": 42, "body": "..."}]}
```
or, when Copilot submitted a summary-only review with no inline comments:
```json
{"action": "findings", "comments": [], "review_state": "CHANGES_REQUESTED"}
```
or:
```json
{"action": "timeout_fallback"}
```

On **exit 2**: stdout empty (Claude generates the LGTM message).

On **exit 3**: plain error string on stdout.

## Updated `goodies-watch.md` cron prompt

The ~300-line cron prompt is replaced with ~20 lines:

```
Watch PR #<NUMBER> on <REPO>.

Run:
  bash "$GOODIES_SCRIPTS/goodies-watch-poll.sh" <REPO> <NUMBER> <WATCHER_ID>

Capture exit code ($?) and stdout (POLL_OUT=$(...)). Then:

exit 0 → output nothing, stop.

exit 1 → parse POLL_OUT as JSON.
  action == "findings":
    Present each finding with fix/dismiss/defer options.
    Batch all fixes into one commit. Enforce the 30s push throttle
    (compute ELAPSED from GitHub server clock, sleep remaining if > 0).
    After push: reply to each comment, resolve threads.
  action == "timeout_fallback":
    "Watcher posted markers across multiple polls on PR #<NUMBER> but
     Copilot review hasn't been triggered."
    Offer: [a] Tampermonkey not installed — install it
           [b] Tab not open — open PR in browser
           [c] Skip this round

exit 2 → LGTM.
  Strip own marker from PR body if present (writer=<WATCHER_ID>).
  If >1 commit on branch ahead of base: squash + force-push with lease.
  Report result. Delete this cron job.

exit 3 → Report POLL_OUT error string to user. Delete cron job.
```

The reply/resolve/squash logic stays in the Claude prompt — those steps need
LLM judgment (Fix vs Dismiss vs Defer wording, squash commit message composition).

## Script path resolution

`GOODIES_SCRIPTS` is added to `modules/claude/env.sh`, pointing to
`$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")")/scripts`.
Uses `python3 os.path.realpath` instead of `readlink -f` for macOS/BSD
portability. Sourced at shell init via `~/.bashrc.d/claude.sh` (existing
symlink). The cron prompt uses `$GOODIES_SCRIPTS/goodies-watch-poll.sh` — no
hardcoded paths.

## Files changed

| File | Change |
|------|--------|
| `modules/claude/scripts/goodies-watch-poll.sh` | **new** — ~400 lines of bash |
| `modules/claude/commands/goodies-watch.md` | replace cron prompt (~300 lines → ~20 lines) |
| `modules/claude/env.sh` | add `GOODIES_SCRIPTS` export |
| `tests/modules/claude.bats` | add BATS tests for poll script exit codes |

## Testing

New BATS tests in `tests/modules/claude.bats`:
- Script is executable and passes `bash -n` syntax check
- Exit 0 when PR is open, Copilot review pending (mock `gh` returning pending state)
- Exit 1 with findings JSON when unreplied comments exist after stale push
- Exit 2 when no unreplied comments and review is fresh
- Exit 3 when PR is closed/merged
- `timeout_fallback` JSON on stdout when existing marker's `expires` has passed with no state change

## Trade-offs

**Cost:** Near-zero tokens per poll on quiet branches. Claude only wakes for exit 1 (findings) or exit 2 (LGTM + squash). Eliminates the $235 waste pattern from issue #48.

**Behavior changes:** Several bugs were fixed during extraction — SIGPIPE from `--paginate | head`, inverted push-vs-review comparison, comment matching by time window vs exact review ID, and wrong squash base branch. The extraction is not a verbatim port.

**Debuggability:** Script is committed, version-controlled, and BATS-testable. `bash -x goodies-watch-poll.sh REPO PR WATCHER_ID` gives full trace without spawning a Claude session.

**Context bloat (#48 fix #2):** Eliminated as a side-effect — the long-running Claude polling session no longer exists. Each Claude invocation is a fresh, short session processing one exit-1 or exit-2 event.
