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

**Before deciding:** Confirm at least one submitted Copilot review exists (filter out pending reviews where `submitted_at` is null):
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '[.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null)] | length'

If the count is 0, no Copilot review has been submitted yet. Report "No Copilot review found — was it requested? Check the Reviewers sidebar in the GitHub PR interface." and delete this cron job.

**Staleness check:** Determine when Copilot last completed a review by using the latest comment timestamp (primary signal) with review `submitted_at` as fallback for LGTM reviews (no comments). Emit one value per item across pages and compute max in shell (avoids per-page sort issue with `--paginate`):
  LAST_COMMENT=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null) | .created_at' | sort | tail -n 1)
  LAST_REVIEW_SUBMITTED=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null) | .submitted_at' | sort | tail -n 1)
  LAST_REVIEW=$(jq -rn --arg c "${LAST_COMMENT:-1970-01-01T00:00:00Z}" --arg r "${LAST_REVIEW_SUBMITTED:-1970-01-01T00:00:00Z}" '[($c | fromdateiso8601), ($r | fromdateiso8601)] | max | todateiso8601')

Get the last push time from the repo events API (the actual time GitHub received the push — not `committer.date`, which can be set arbitrarily via `--date`). Filter to PushEvents targeting this branch's ref:
  BRANCH=$(gh api repos/<REPO>/pulls/<NUMBER> --jq '.head.ref')
  LAST_PUSH=$(gh api --paginate repos/<REPO>/events --jq '.[] | select(.type == "PushEvent" and .payload.ref == "refs/heads/'"$BRANCH"'") | .created_at' | head -n 1)

If LAST_PUSH is empty or null (events pruned or branch not found), fall back to `committer.date`:
  if [ -z "$LAST_PUSH" ] || [ "$LAST_PUSH" = "null" ]; then
    LAST_PUSH=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/commits --jq '.[].commit.committer.date' | sort | tail -n 1)
  fi

Compare: `echo "$LAST_PUSH $LAST_REVIEW" | jq -R 'split(" ") | (.[0] | fromdateiso8601) > (.[1] | fromdateiso8601)'`. If the result is `true`, the branch has been updated since the last review (note: Step 1 already confirmed no review is pending, so this means the review was never triggered — likely throttled). Get GitHub's server time to measure elapsed time since push (avoids local clock skew):
  GH_NOW=$(gh api repos/<REPO> --include 2>&1 | grep -i '^date:' | sed 's/^[Dd]ate: //' | xargs -I{} date -u -d "{}" +%Y-%m-%dT%H:%M:%SZ)
  PUSH_AGE=$(jq -rn --arg push "$LAST_PUSH" --arg now "$GH_NOW" '($now | fromdateiso8601) - ($push | fromdateiso8601)')

Decide:

1. **PUSH_AGE < 900 (within 15 minutes):** Output nothing and stop — keep polling to give Copilot time.

2. **PUSH_AGE >= 900 (or no review triggered after a previous force-push retry):** Attempt one force-push with lease to re-trigger the push event. Note: `git push --force-with-lease` will report "Everything up-to-date" if the remote already has the same SHA — GitHub only fires a push event when the ref actually changes. To produce a new SHA, amend the tip commit's timestamp first:

       git commit --amend --no-edit --date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
       git push --force-with-lease

   Report: "Push at <LAST_PUSH> did not trigger a Copilot review — retrying with force-push." Then stop and keep polling. Track that a retry was attempted (e.g., compare the current HEAD SHA against the commit SHA recorded in the last review). If the next poll still finds no pending review and no new review after the force-push, report: "Copilot review appears stalled — force-push retry did not trigger a review. The existing review findings still apply." and fall through to Case A/B evaluation using the most recent review data.

**Case A — No pending review + no unreplied inline comments + review is fresh:**
Report "Copilot review complete — no unreplied inline comments. LGTM!" then:
1. Delete this cron job.
2. Check if there are multiple commits on the branch ahead of the base branch. If only one commit exists, there is nothing to squash or force-push — just report LGTM and stop.
3. If multiple commits exist: squash all commits on the current branch into a single commit. Use the PR title as the commit message subject and include a body summarizing the changes. Preserve any `Co-Authored-By` trailers from the squashed commits. Add a `Reviewed-by: copilot-pull-request-reviewer <copilot-pull-request-reviewer@github.com>` trailer. Force-push with lease.
4. Report the result. The user can re-run `/goodies-watch` to start a new watch cycle after pushing further changes.

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

When branch protection rules include Copilot review-on-push, rapid successive pushes (within ~5 minutes of each other) may cause Copilot to skip re-review entirely. This is a GitHub-side rate limit, not configurable.

**Before every push**, ensure at least 5 minutes have passed since the last Copilot review completion. Both timestamps come from GitHub's servers to avoid local clock skew:

1. Get the latest review completion timestamp (comment `created_at` as primary, review `submitted_at` as fallback). Emit one value per item and compute max in shell to avoid per-page sort issues:
  LAST_COMMENT=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null) | .created_at' | sort | tail -n 1)
  LAST_REVIEW_SUBMITTED=$(gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '.[] | select(.user.login | test("copilot"; "i")) | select(.submitted_at != null) | .submitted_at' | sort | tail -n 1)
  LAST_REVIEW=$(jq -rn --arg c "${LAST_COMMENT:-1970-01-01T00:00:00Z}" --arg r "${LAST_REVIEW_SUBMITTED:-1970-01-01T00:00:00Z}" '[($c | fromdateiso8601), ($r | fromdateiso8601)] | max | todateiso8601')

2. Get "now" from GitHub's server clock (avoids local clock skew):
  GH_NOW=$(gh api repos/<REPO> --include 2>&1 | grep -i '^date:' | sed 's/^[Dd]ate: //' | xargs -I{} date -u -d "{}" +%Y-%m-%dT%H:%M:%SZ)

3. Compute seconds elapsed since the last review using GitHub's clock:
  ELAPSED=$(jq -rn --arg ref "$LAST_REVIEW" --arg now "$GH_NOW" '($now | fromdateiso8601) - ($ref | fromdateiso8601)')
  REMAINING=$((300 - ELAPSED))

4. If REMAINING is greater than 0, report: "Waiting $REMAINING seconds before pushing to avoid Copilot throttle..." then run the delayed push in the background and capture the PID:

       sleep $REMAINING && git push &
       PUSH_PID=$!

   This keeps the conversation responsive — if the user requests additional changes during the wait, amend the pending commit before the background push fires.

5. If REMAINING is 0 or negative, push immediately (foreground) and capture exit code directly:

       git push
       PUSH_EXIT=$?

6. **Wait for push completion before replying/resolving.** Verify the push succeeded before proceeding to the "Replying to comments" and "Resolving review threads" steps:

       # For background push (step 4):
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
- Always enforce the 5-minute gap from the last Copilot review completion (using GitHub's server clock for "now"). This ensures the push doesn't land in Copilot's throttle window.
- Run the delay + push in the background so the assistant stays available for interaction during the wait.
- Never reply to comments or resolve threads until the push has been verified successful.
```

7. Then immediately run the first check now without waiting for the first cron fire.
