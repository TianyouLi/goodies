---
allowed-tools: Bash, CronCreate, CronList, CronDelete
---

Watch the current branch's PR for new Copilot reviews and present findings as they arrive.

1. Get the current branch name:
   ```
   BRANCH=$(git branch --show-current)
   ```

2. Get the repo name:
   ```
   gh repo view --json nameWithOwner -q .nameWithOwner
   ```

3. Find the open PR number for this branch (constrain to same-repo head to avoid fork ambiguity):
   ```
   gh api --paginate repos/<REPO>/pulls --jq '.[] | select(.head.ref == "<BRANCH>" and .head.repo.full_name == "<REPO>" and .state == "open") | .number' | head -1
   ```
   If no PR is found, tell the user "No open PR found for branch <BRANCH>" and stop.

4. Check for an existing watcher on this PR using CronList. If any cron job's prompt contains "Watch PR #<NUMBER>", delete it with CronDelete before proceeding (avoids duplicate polls).

5. Announce: "Watching PR #<NUMBER> on branch <BRANCH> for new Copilot reviews. Polling every 3 minutes."

6. Set up a recurring cron using CronCreate (recurring: true, cron: "*/3 * * * *") with this exact prompt, substituting the real values for REPO and NUMBER:

```
Watch PR #<NUMBER> for new Copilot reviews.

## Step 0: Maybe trigger Copilot review

This step decides whether to request a Copilot review BEFORE the existing review-watching logic runs. It uses a two-tier strategy:

1. **Primary: API request** — discover Copilot's exact reviewer login (from currently requested reviewers, past review history, or repo assignees), then call the requested_reviewers endpoint directly. This requires no browser, no userscript, no markers in the PR body.
2. **Fallback: Tampermonkey userscript handshake** — if the API request fails (403, permission error, or org policy blocks it), fall back to the marker-based handshake described in `docs/design/userscripts-copilot-watch-handshake.md`.

### Watcher identity

On the FIRST poll of a watcher session, generate a writer-ID once and remember it for all subsequent posts on this same watcher cron. Use a derivative of the cron-job-ID + a timestamp:
  WATCHER_ID="w-<cron-job-id-prefix>-<short-random>"

For example: `w-de40-7b3f`. This must stay stable for the lifetime of the cron job. Subsequent polls re-use the same WATCHER_ID. (If the cron job is restarted via /goodies-watch, a new WATCHER_ID is generated — that's correct, the new job is a separate watcher.)

### Decision tree

```
Step 0a: Read PR state.
  STATE=$(gh api repos/<REPO>/pulls/<NUMBER> --jq .state)
  Closed/merged → strip our marker if present, exit Step 0.

Step 0b: Is Copilot a requested reviewer?
  COPILOT_REVIEWER=$(gh api repos/<REPO>/pulls/<NUMBER>/requested_reviewers --jq '[.users[].login | test("copilot"; "i")] | any')
  And does Copilot show up at all in the PR's reviewer history?
  Important: with `--paginate`, jq filters that emit one boolean per page produce a multi-line "true"/"false" string under shell capture, not a single boolean. Stream the logins and grep across all pages instead:
  COPILOT_EVER_COUNT=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '.[].user.login' | grep -ic '^copilot' || true)
  COPILOT_EVER=$([ "$COPILOT_EVER_COUNT" -gt 0 ] && echo true || echo false)

  If neither current-reviewer nor ever-reviewed → skip directly to Step 0h
  (this is a fresh PR that needs Copilot requested for the first time).

Step 0c: Is a review currently pending?
  If COPILOT_REVIEWER==true (still in pending/in-flight state) → strip our marker (auto-trigger handled it; userscript click is no longer needed), exit Step 0.

Step 0d: Has Copilot ever submitted a review?
  COUNT_SUBMITTED=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '[.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null)] | length' | awk '{s+=$1} END{print s}')

  If COUNT_SUBMITTED == 0:
    → expected_to_act=YES (no review yet; we should request)
    → skip directly to Step 0h (post marker — no prior review means
       no comments to check for resolution in Steps 0e–0g)

Step 0e: Compare LAST_PUSH vs LAST_REVIEW.
  (Use the same LAST_PUSH / LAST_REVIEW computation as Step 3's staleness check, but compute now in Step 0 so we can decide whether to trigger.)

  If LAST_PUSH <= LAST_REVIEW (no new push since the last review):
    → review is fresh; nothing to trigger. Strip our marker if present, exit Step 0.

Step 0f: Did the last review have any inline comments at all?
  Find the latest Copilot review's submitted_at. Count Copilot inline comments authored within ±1 hour of that timestamp. Use jq's epoch arithmetic via `fromdateiso8601` — string-concatenating "-1H"/"+1H" onto an ISO timestamp is NOT valid ISO8601 and the comparison would silently misbehave.
  TARGET_REVIEW_AT="$LAST_REVIEW"
  Important: with `--paginate`, `gh ... --jq` runs the filter PER PAGE, so a per-page `| length` would emit one count per page (multi-line shell capture). Aggregate by streaming raw `created_at` values across all pages and counting in shell. Also: `gh api`'s `--jq` builtin doesn't accept `--arg`, so pipe through standalone `jq` with the variable instead.
  CMT_COUNT_LATEST=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments \
    --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null) | .created_at' \
    | jq -rR --arg target "$TARGET_REVIEW_AT" '
        ($target | fromdateiso8601) as $t |
        select((. | fromdateiso8601) >= ($t - 3600)) |
        select((. | fromdateiso8601) <= ($t + 3600))
      ' | wc -l | awk '{print $1}')

  If CMT_COUNT_LATEST == 0 → last review was LGTM. STOP — only the user can decide to ask again.
  Strip our marker if present, exit Step 0.

  If CMT_COUNT_LATEST > 0 → continue.

Step 0g: Are all those comments resolved or outdated?
  GraphQL paginate reviewThreads, count Copilot-author threads where isResolved==false AND isOutdated==false. If any open → user hasn't finished addressing. Strip our marker if present, exit Step 0.

  If all dealt with → expected_to_act=YES, continue.

Step 0h: Request Copilot review (API-first with userscript fallback).

  **Primary path: direct API request**

  First, discover Copilot's exact reviewer login (the name varies —
  `copilot-pull-request-reviewer[bot]`, `Copilot`, etc. — so we resolve
  it dynamically rather than hardcoding). Try three sources in order:

  1. Currently requested reviewers on this PR:
    COPILOT_LOGIN=$(gh api repos/<REPO>/pulls/<NUMBER>/requested_reviewers \
      --jq '.users[].login' 2>/dev/null | grep -i 'copilot' | head -1 || true)

  2. Past review history (login used in submitted reviews):
    if [ -z "$COPILOT_LOGIN" ]; then
      COPILOT_LOGIN=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews \
        --jq '.[].user.login' | grep -i 'copilot' | head -1 || true)
    fi

  3. Repo-level assignable users, or fall back to the known common name:
    if [ -z "$COPILOT_LOGIN" ]; then
      COPILOT_LOGIN=$(gh api --paginate repos/<REPO>/assignees --jq '.[].login' 2>/dev/null \
        | grep -i 'copilot' | head -1 || true)
    fi
    if [ -z "$COPILOT_LOGIN" ]; then
      COPILOT_LOGIN="copilot-pull-request-reviewer[bot]"
    fi

  Now request the review (wrapped to prevent set -e from aborting on
  expected failures like 403/404 — the fallback path must always run):
    if API_RESPONSE=$(gh api repos/<REPO>/pulls/<NUMBER>/requested_reviewers \
      -X POST -f "reviewers[]=$COPILOT_LOGIN" 2>&1); then
      API_EXIT=0
    else
      API_EXIT=$?
    fi

  Check success: exit code 0 AND response contains a requested_reviewers
  entry with a login matching "copilot" (case-insensitive). Default to
  "false" if jq fails (e.g. non-JSON error response from gh):
    API_SUCCESS=$(echo "$API_RESPONSE" | jq -r \
      '[.requested_reviewers[]?.login | test("copilot"; "i")] | any' 2>/dev/null || echo "false")

  If API_EXIT == 0 AND API_SUCCESS == "true":
    → Report (only on FIRST successful request of a session):
      "Requested Copilot review on PR #<NUMBER> via API (reviewer: $COPILOT_LOGIN)."
    → Exit Step 0.

  **Fallback path: Tampermonkey userscript handshake**

  If the API request failed (non-zero exit, 403, 422, or response doesn't
  confirm Copilot in requested_reviewers), fall back to the marker-based
  userscript handshake. Report (once per session): "API review request
  failed (likely org policy); falling back to userscript handshake."

  Post a FRESH marker (always — replace any of OUR existing). We never
  strip markers written by other watchers — they're independent requests,
  and the userscript clicks once per (writer, nonce) so parallel watchers
  stay coordinated naturally.

  EXPIRES should come from GitHub's clock to avoid drift when the
  watcher machine's local clock differs from the browser's clock.
  The userscript compares `expires` against Date.now() directly
  (no skew compensation — the 10-min validity window absorbs
  normal browser-clock drift). Use GH_NOW (derived from the
  GitHub response Date header) to compute EXPIRES:
    GH_NOW=$(gh api repos/<REPO> --include 2>&1 | grep -i '^date:' | sed 's/^[Dd]ate: //' | python3 -c "import sys,email.utils,datetime; d=email.utils.parsedate_to_datetime(sys.stdin.read().strip()); print(d.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")

    NONCE=$(openssl rand -hex 4 2>/dev/null || head -c 8 /dev/urandom | xxd -p)
    EXPIRES=$(jq -rn --arg now "$GH_NOW" '($now | fromdateiso8601) + 600 | todateiso8601')
    MARKER_PAYLOAD="goodies-watch:click-request-review nonce=$NONCE expires=$EXPIRES writer=$WATCHER_ID"
    MARKER_BLOCK=$(printf '<details><summary>goodies-watch handshake (writer=%s)</summary>\n\n%s\n</details>' "$WATCHER_ID" "$MARKER_PAYLOAD")

    OLD_BODY=$(gh api repos/<REPO>/pulls/<NUMBER> --jq .body)
    # Strip ONLY our own marker blocks (matched by writer=$WATCHER_ID).
    # WATCHER_ID is passed via env var so special chars can't corrupt Python.
    NEW_BODY=$(printf '%s' "$OLD_BODY" | WATCHER_ID="$WATCHER_ID" python3 -c '
import sys, re, os
b = sys.stdin.read()
wid = re.escape(os.environ["WATCHER_ID"])
pat = r"\n*<details><summary>goodies-watch[^<]*</summary>\s*goodies-watch:click-request-review nonce=\S+ expires=\S+ writer=" + wid + r"\s*</details>\n*"
b = re.sub(pat, "\n", b, flags=re.DOTALL)
sys.stdout.write(b)
')
    NEW_BODY=$(printf '%s\n\n%s\n' "$NEW_BODY" "$MARKER_BLOCK")
    gh api --method PATCH /repos/<REPO>/pulls/<NUMBER> -f body="$NEW_BODY"

  Report (only on FIRST post of a session, not every refresh):
    "Posted userscript marker on PR #<NUMBER>. The userscript will click within ~10s if installed and the PR tab is open. The marker refreshes each poll until Copilot goes pending."

  On subsequent polls where the gates still say "act", refresh
  silently (don't spam the user every 3 min).

Step 0i: Implicit ack via gh API state change.
  Each subsequent poll re-evaluates Step 0a–0g. Both paths (API and
  handshake) converge here: Step 0c sees Copilot pending and exits.

Step 0j: Timeout fallback (only for userscript handshake path).
  If the API path succeeded, this step is skipped entirely.

  If we've posted markers across multiple polls (>= 3 polls = ~9 min)
  and the gates STILL say "act" (no pending, no new review), the
  userscript probably isn't getting through. Surface to the user:

  "Watcher posted markers across multiple polls on PR #<NUMBER> but Copilot review hasn't been triggered. Two likely causes:
    [a] Tampermonkey userscript not installed → click 'Request review' on Copilot manually in the GitHub UI
    [b] Tab not open → open the PR in a browser tab; userscript will pick up on next poll
    [c] Skip this round (don't trigger)
   Which?"

  Track poll-count-since-first-post per PR via a session-local
  counter (or by reading the existing marker's writer/nonce — if
  the watcher's WATCHER_ID has 3+ different nonces visible in the
  recent body history without a state change, surface).
```

After Step 0 returns, continue to Step 1 below.

## Step 1: Check if Copilot review is pending

Run:
  gh api repos/<REPO>/pulls/<NUMBER>/requested_reviewers --jq '[.users[].login | test("copilot"; "i")] | any'

If the result is `true`, a review is pending (Copilot hasn't finished yet). Output nothing and stop — keep polling.

## Step 2: Find unreplied Copilot inline review comments

Fetch all top-level Copilot inline review comment IDs on the PR (exclude replies):
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '[.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null) | .id]'

Fetch all reply target IDs in a single call:
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '[.[] | .in_reply_to_id] | map(select(. != null))'

A Copilot comment is "unreplied" if its `id` does not appear in the reply target list.

Note: This only covers inline review comments (`/pulls/<NUMBER>/comments`), not review-level summaries (`/pulls/<NUMBER>/reviews`). Summary-only reviews with no inline comments are treated as LGTM.

## Step 3: Decide outcome

**Before deciding:** Confirm at least one submitted Copilot review exists (filter out pending reviews where `submitted_at` is null). Aggregate per-page lengths to get a single integer (--paginate runs jq per page):
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '[.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null)] | length' | awk '{s+=$1} END{print s}'

If the count is 0, no Copilot review has been submitted yet (note: Step 1 already exits if Copilot is pending, so reaching this point means no review is in flight). Attempt to request review via API (one-shot, no userscript fallback). Discover COPILOT_LOGIN first (check review history, then hardcoded fallback):
  COPILOT_LOGIN=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews \
    --jq '.[].user.login' | grep -i 'copilot' | head -1 || true)
  if [ -z "$COPILOT_LOGIN" ]; then
    COPILOT_LOGIN="copilot-pull-request-reviewer[bot]"
  fi
  if API_RESPONSE=$(gh api repos/<REPO>/pulls/<NUMBER>/requested_reviewers \
    -X POST -f "reviewers[]=$COPILOT_LOGIN" 2>&1); then API_EXIT=0; else API_EXIT=$?; fi
If API_EXIT == 0, keep polling. If it fails, check the error: if the response contains "Not Found" or "Forbidden", report "Could not request Copilot review — no write access. Ask a repo maintainer to request review manually." and delete this cron job. For other errors (network, rate limit), report the actual error and keep polling (transient failure).

**Staleness check:** Determine when Copilot last completed a review by using the latest comment timestamp (primary signal) with review `submitted_at` as fallback for LGTM reviews (no comments). Emit one value per item across pages and compute max in shell (avoids per-page sort issue with `--paginate`):
  LAST_COMMENT=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null) | .created_at' | sort | tail -n 1)
  LAST_REVIEW_SUBMITTED=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null) | .submitted_at' | sort | tail -n 1)
  LAST_REVIEW=$(jq -rn --arg c "${LAST_COMMENT:-1970-01-01T00:00:00Z}" --arg r "${LAST_REVIEW_SUBMITTED:-1970-01-01T00:00:00Z}" '[($c | fromdateiso8601), ($r | fromdateiso8601)] | max | todateiso8601')

Get the last push time from the repo events API (the actual time GitHub received the push — not `committer.date`, which can be set arbitrarily via `--date`). Filter to PushEvents targeting this branch's ref:
  BRANCH=$(gh api repos/<REPO>/pulls/<NUMBER> --jq '.head.ref')
  LAST_PUSH=$(gh api --paginate repos/<REPO>/events --jq '.[] | select(.type == "PushEvent" and .payload.ref == "refs/heads/'"$BRANCH"'") | .created_at' | head -n 1)

If LAST_PUSH is empty or null (events pruned or not yet indexed), fall back to the PR's `created_at` (GitHub-sourced timestamp, avoids local clock skew from `committer.date`):
  if [ -z "$LAST_PUSH" ] || [ "$LAST_PUSH" = "null" ]; then
    LAST_PUSH=$(gh api repos/<REPO>/pulls/<NUMBER> --jq '.created_at')
  fi

Compare: `echo "$LAST_PUSH $LAST_REVIEW" | jq -R 'split(" ") | (.[0] | fromdateiso8601) > (.[1] | fromdateiso8601)'`. If the result is `true`, the branch has been updated since the last review (note: Step 1 already confirmed no review is pending, so this means the review was never triggered — likely throttled). Get GitHub's server time to measure elapsed time since push (avoids local clock skew):
  GH_NOW=$(gh api repos/<REPO> --include 2>&1 | grep -i '^date:' | sed 's/^[Dd]ate: //' | python3 -c "import sys,email.utils,datetime; d=email.utils.parsedate_to_datetime(sys.stdin.read().strip()); print(d.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  PUSH_AGE=$(jq -rn --arg push "$LAST_PUSH" --arg now "$GH_NOW" '($now | fromdateiso8601) - ($push | fromdateiso8601)')

Decide:

1. **PUSH_AGE < 180 (within 3 minutes):** Output nothing and stop — keep polling to give Copilot time. (Reduced from 15 min: the API request in Step 0h triggers review immediately, so 3 min is sufficient for Copilot to process.)

2. **PUSH_AGE >= 180:** The push didn't draw a review within 3 minutes. Step 0 should have already requested review (via API or userscript fallback).

   - **If Step 0's API request succeeded on a prior poll:** Copilot was requested but hasn't responded. This is unusual — surface to the user:

     "Copilot was requested via API but hasn't started reviewing PR #<NUMBER> after >3 min. This may indicate a transient GitHub-side delay.
       [a] Re-request — try the API call again
       [b] Wait — keep polling without re-requesting (review may still arrive)
      Which?"

     On [a], re-run the API request. On [b], continue polling without surfacing this prompt again until a new push lands.

   - **If Step 0 fell back to the userscript handshake:** check the PR body for our WATCHER_ID's marker. If markers have been posted across >= 3 polls (~9 min) without state change, trigger Step 0j's timeout fallback prompt.

   - **If Step 0 decided NOT to request** (e.g. because Step 0f detected last review was LGTM, or Step 0g found open threads): the push age alone isn't a problem; a fresh push without comments-to-address-yet is the user's normal flow. Output nothing.

**Case A — No pending review + no unreplied inline comments + review is fresh:**
Report "Copilot review complete — no unreplied inline comments. LGTM!" then:
1. If the userscript fallback was used, strip ONLY our own marker block (writer=$WATCHER_ID) from the PR body if present (handshake hygiene — leaves the body clean for merge). If the API path was used (no marker was ever posted), skip this step. Other watchers' markers survive untouched:
   ```
   OLD_BODY=$(gh api repos/<REPO>/pulls/<NUMBER> --jq .body)
   NEW_BODY=$(printf '%s' "$OLD_BODY" | WATCHER_ID="$WATCHER_ID" python3 -c '
import sys, re, os
b = sys.stdin.read()
wid = re.escape(os.environ["WATCHER_ID"])
pat = r"\n*<details><summary>goodies-watch[^<]*</summary>\s*goodies-watch:click-request-review nonce=\S+ expires=\S+ writer=" + wid + r"\s*</details>\n*"
b = re.sub(pat, "\n", b, flags=re.DOTALL)
sys.stdout.write(b)
')
   if [ "$OLD_BODY" != "$NEW_BODY" ]; then
     gh api --method PATCH /repos/<REPO>/pulls/<NUMBER> -f body="$NEW_BODY"
   fi
   ```
2. Delete this cron job.
3. Check if there are multiple commits on the branch ahead of the base branch. If only one commit exists, there is nothing to squash or force-push — just report LGTM and stop.
4. If multiple commits exist: first verify the remote branch hasn't diverged (prevents overwriting other contributors' commits). Only abort when the remote contains commits not reachable from HEAD (i.e., true divergence — not simply being behind):

       git fetch origin $BRANCH
       if ! git merge-base --is-ancestor origin/$BRANCH HEAD; then
         echo "Remote branch has diverged — aborting squash to avoid overwriting others' commits. Please rebase first."
         # Do NOT squash or force-push. Report the divergence and stop.
         return
       fi

   If the check passes, squash all commits on the current branch into a single commit. Use the PR title as the commit message subject and include a body summarizing the changes. Preserve any `Co-Authored-By` trailers from the squashed commits. Add a `Reviewed-by: copilot-pull-request-reviewer <copilot-pull-request-reviewer@github.com>` trailer. Force-push with lease.
5. Report the result. The user can re-run `/goodies-watch` to start a new watch cycle after pushing further changes.

**Case B — No pending review + unreplied inline comments exist:**
Notify the user "Copilot review has inline findings on PR #<NUMBER>!" and fetch the unreplied top-level comment details (exclude replies):
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '[.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null)] | .[] | {id, path, line, body}'

Filter to only unreplied ones, then present each finding with fix/dismiss/defer options. For each decision, state the rationale — why the fix was made or why the finding doesn't apply.

**Important: batch all fixes into a single push.** Do NOT push after each individual fix. Instead:
1. Present all findings to the user at once.
2. Fix/dismiss/defer each finding (making code changes as needed).
3. Stage all changes into a single commit.
4. Start the push-delay check (see "Push timing" below). During the wait, remain responsive — if the user requests additional changes, amend the commit before the push fires.
5. Once the delay has elapsed, push.
6. Then reply to all comments and resolve all threads.

This avoids triggering Copilot's push-throttle and maximizes the content of each push.

## Replying to comments

After all fixes are committed and pushed (so the commit SHA is available for Fix replies), post a reply to each Copilot comment:
  gh api repos/<REPO>/pulls/<NUMBER>/comments/<COMMENT_ID>/replies -f body="<REPLY>"

Reply format:
- **Fix**: "Fixed in <commit-sha>. <brief explanation of the change>."
- **Dismiss**: "Dismissed — <reason why it doesn't apply>."
- **Defer**: "Deferred — <reason>. Tracking in <issue-url if created>."

## Resolving review threads

After replying to comments, resolve the corresponding review threads so they collapse in the GitHub UI.

Fetch all thread IDs and their first-comment database IDs in one paginated GraphQL call, then filter client-side to unresolved threads:

  OWNER=$(echo "<REPO>" | cut -d/ -f1)
  REPO_NAME=$(echo "<REPO>" | cut -d/ -f2)

Paginate with cursors until `hasNextPage` is false. Loop structure (uses two query forms to handle `after: null` on first iteration):

    CURSOR=""
    ALL_THREADS="[]"
    while true; do
      if [ -z "$CURSOR" ]; then
        QUERY='{ repository(owner: "'"$OWNER"'", name: "'"$REPO_NAME"'") { pullRequest(number: <NUMBER>) { reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }'
      else
        QUERY='{ repository(owner: "'"$OWNER"'", name: "'"$REPO_NAME"'") { pullRequest(number: <NUMBER>) { reviewThreads(first: 100, after: "'"$CURSOR"'") { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }'
      fi
      RESULT=$(gh api graphql -f query="$QUERY" --jq '.data.repository.pullRequest.reviewThreads')
      ALL_THREADS=$(echo "$ALL_THREADS" "$RESULT" | jq -s '.[0] + ([.[1].nodes[] | select(.isResolved == false)])')
      HAS_NEXT=$(echo "$RESULT" | jq -r '.pageInfo.hasNextPage')
      [ "$HAS_NEXT" = "true" ] || break
      CURSOR=$(echo "$RESULT" | jq -r '.pageInfo.endCursor')
    done

Build a map of `{comment_databaseId → thread_id}` from `ALL_THREADS` (already filtered to unresolved).

For each replied comment, look up the thread ID from the map and resolve it:
  gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<THREAD_ID>"}) { thread { isResolved } } }'

Skip if the comment ID is not in the map (thread already resolved or comment deleted). This approach handles PRs with >100 review threads by paginating.

## Push timing (throttle prevention)

When branch protection rules include Copilot review-on-push, pushing too soon after the last Copilot review or the last push (whichever is later) can cause Copilot to skip re-review entirely. We enforce a short gap to stay clear of that window. The gap is **30 seconds** — in practice the earlier 5-minute gap was far more conservative than necessary, and a 30s spacing has been enough to let the re-review trigger reliably while keeping the fix→push loop fast.

**Before every push**, ensure at least 30 seconds have passed since the later of (last Copilot review completion, last push received by GitHub). All timestamps come from GitHub's servers to avoid local clock skew:

1. Get the latest review completion timestamp (comment `created_at` as primary, review `submitted_at` as fallback). Emit one value per item and compute max in shell to avoid per-page sort issues:
  LAST_COMMENT=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null) | .created_at' | sort | tail -n 1)
  LAST_REVIEW_SUBMITTED=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null) | .submitted_at' | sort | tail -n 1)
  LAST_REVIEW=$(jq -rn --arg c "${LAST_COMMENT:-1970-01-01T00:00:00Z}" --arg r "${LAST_REVIEW_SUBMITTED:-1970-01-01T00:00:00Z}" '[($c | fromdateiso8601), ($r | fromdateiso8601)] | max | todateiso8601')

2. Get the last push time from the repo events API (actual time GitHub received the push). Fall back to the PR's `created_at` if no push event exists (events pruned or not yet indexed) — this is when the PR was opened (typically shortly after the first push), serving as a conservative GitHub-sourced lower bound:
  BRANCH=$(gh api repos/<REPO>/pulls/<NUMBER> --jq '.head.ref')
  LAST_PUSH=$(gh api --paginate repos/<REPO>/events --jq '.[] | select(.type == "PushEvent" and .payload.ref == "refs/heads/'"$BRANCH"'") | .created_at' | head -n 1)
  if [ -z "$LAST_PUSH" ] || [ "$LAST_PUSH" = "null" ]; then
    LAST_PUSH=$(gh api repos/<REPO>/pulls/<NUMBER> --jq '.created_at')
  fi

3. Determine the reference time — use whichever is later (review or push):
  REF_TIME=$(jq -rn --arg r "$LAST_REVIEW" --arg p "$LAST_PUSH" '[($r | fromdateiso8601), ($p | fromdateiso8601)] | max | todateiso8601')

4. Get "now" from GitHub's server clock (avoids local clock skew):
  GH_NOW=$(gh api repos/<REPO> --include 2>&1 | grep -i '^date:' | sed 's/^[Dd]ate: //' | python3 -c "import sys,email.utils,datetime; d=email.utils.parsedate_to_datetime(sys.stdin.read().strip()); print(d.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")

5. Compute seconds elapsed since the reference time using GitHub's clock:
  ELAPSED=$(jq -rn --arg ref "$REF_TIME" --arg now "$GH_NOW" '($now | fromdateiso8601) - ($ref | fromdateiso8601)')
  REMAINING=$((30 - ELAPSED))

6. If REMAINING is greater than 0, report: "Waiting $REMAINING seconds before pushing to avoid Copilot throttle..." then run the delayed push in the background and capture the PID:

       sleep $REMAINING && git push &
       PUSH_PID=$!

   This keeps the conversation responsive — if the user requests additional changes during the wait, amend the pending commit before the background push fires.

7. If REMAINING is 0 or negative, push immediately (foreground) and capture exit code directly:

       git push
       PUSH_EXIT=$?

8. **Wait for push completion before replying/resolving.** Verify the push succeeded before proceeding to the "Replying to comments" and "Resolving review threads" steps:

       # For background push (step 6):
       wait $PUSH_PID
       PUSH_EXIT=$?

       # For either path:
       if [ $PUSH_EXIT -ne 0 ]; then
         echo "Push failed (exit $PUSH_EXIT). Aborting reply/resolve."
         # Do NOT reply to comments or resolve threads if push failed
       fi

   Only proceed to reply and resolve threads after confirming the push completed successfully. This ensures commit SHAs cited in replies actually exist on the remote.

**Rules:**
- Always batch fixes into a single commit/push (see Case B above).
- Never push incrementally per finding.
- Always enforce the 30-second gap from the later of (last review, last push) using GitHub's server clock for "now". This ensures the push doesn't land in Copilot's throttle window regardless of whether the review arrived quickly or slowly.
- Run the delay + push in the background so the assistant stays available for interaction during the wait.
- Never reply to comments or resolve threads until the push has been verified successful.
```

7. Then immediately run the first check now without waiting for the first cron fire.
