---
allowed-tools: Bash, CronCreate, CronList, CronDelete
---

Watch the current branch's PR for new Copilot reviews and present findings as they arrive.

1. Source the goodies environment to ensure `GOODIES_SCRIPTS` is set:
   ```
   source ~/.bashrc.d/claude.sh
   ```

2. Get the current branch name:
   ```
   BRANCH=$(git branch --show-current)
   ```

3. Get the repo name:
   ```
   gh repo view --json nameWithOwner -q .nameWithOwner
   ```

4. Find the open PR number for this branch (constrain to same-repo head to avoid fork ambiguity):
   ```
   gh api --paginate repos/<REPO>/pulls --jq '[.[] | select(.head.ref == "<BRANCH>" and .head.repo.full_name == "<REPO>" and .state == "open") | .number] | first // empty'
   ```
   If no PR is found, tell the user "No open PR found for branch <BRANCH>" and stop.

5. Check for an existing watcher on this PR using CronList. If any cron job's prompt contains "Watch PR #<NUMBER>", delete it with CronDelete before proceeding (avoids duplicate polls).

6. Announce: "Watching PR #<NUMBER> on branch <BRANCH> for new Copilot reviews. Polling every 3 minutes."

7. Generate a WATCHER_ID: `w-<first-4-chars-of-a-random-hex>-<next-4-chars>` (e.g. `w-de40-7b3f`). This stays stable for the lifetime of this cron job.

8. Set up a recurring cron using CronCreate (recurring: true, cron: "*/3 * * * *") with this exact prompt, substituting the real values for REPO, NUMBER, and WATCHER_ID:

```
Watch PR #<NUMBER> for new Copilot reviews.

Run the poll script and capture its output:
  source ~/.bashrc.d/claude.sh
  POLL_EXIT=0
  POLL_OUT=$(bash "$GOODIES_SCRIPTS/goodies-watch-poll.sh" "<REPO>" "<NUMBER>" "<WATCHER_ID>" 2>&1) || POLL_EXIT=$?

Dispatch on exit code:

**exit 0** — output nothing, stop.

**exit 1** — parse POLL_OUT as JSON (one line).

  If `action == "findings"`:
    The `comments` array contains unreplied Copilot inline comments, each with `id`, `path`, `line`, `body`.
    If `comments` is empty, a `review_state` field is present instead (e.g. `"CHANGES_REQUESTED"`) — report the review state to the user and ask how to proceed; there are no inline comments to fix.
    If `comments` is non-empty, present each finding to the user with fix/dismiss/defer options. For each decision, state the rationale.
    Batch ALL fixes into a single commit (do NOT push per-finding). Then:
    1. Enforce the 30-second push throttle. Get the GitHub server clock:
         GH_NOW=$(gh api repos/<REPO> --include 2>&1 | grep -i '^date:' | sed 's/^[Dd]ate: //' | python3 -c "import sys,email.utils,datetime; d=email.utils.parsedate_to_datetime(sys.stdin.read().strip()); print(d.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
       Compute elapsed seconds since the later of (last Copilot review completed, last push received). If REMAINING > 0, run `sleep $REMAINING && git push &` in the background; else push foreground. Wait for push to complete and verify exit code.
    2. After confirmed push: reply to each comment via `gh api repos/<REPO>/pulls/<NUMBER>/comments/<ID>/replies -f body="<REPLY>"`. Format: Fix → "Fixed in <sha>. <explanation>." | Dismiss → "Dismissed — <reason>." | Defer → "Deferred — <reason>."
    3. Resolve each thread: paginate `reviewThreads` via GraphQL (cursor-based until hasNextPage=false), build `{databaseId → threadId}` map, call `resolveReviewThread` mutation for each replied comment's thread.

  If `action == "timeout_fallback"`:
    Tell the user: "Watcher posted markers across multiple polls on PR #<NUMBER> but Copilot review hasn't been triggered."
    Offer:
      [a] Tampermonkey userscript not installed → install it and open the PR tab
      [b] Tab not open → open the PR in a browser tab; userscript will pick up on next poll
      [c] Skip this round

**exit 2** — LGTM.
  1. Strip own marker from PR body if present (writer=<WATCHER_ID>):
       OLD_BODY=$(gh api repos/<REPO>/pulls/<NUMBER> --jq .body)
       NEW_BODY=$(printf '%s' "$OLD_BODY" | WATCHER_ID="<WATCHER_ID>" python3 -c '
import sys, re, os
b = sys.stdin.read()
wid = re.escape(os.environ["WATCHER_ID"])
pat = (r"\n*<details><summary>goodies-watch[^<]*</summary>"
       r"\s*goodies-watch:click-request-review nonce=\S+ expires=\S+ writer=" + wid +
       r"\s*</details>\n*")
b = re.sub(pat, "\n", b, flags=re.DOTALL)
sys.stdout.write(b)
')
       if [ "$OLD_BODY" != "$NEW_BODY" ]; then
         gh api --method PATCH /repos/<REPO>/pulls/<NUMBER> -f body="$NEW_BODY"
       fi
  2. Fetch the PR base branch and count commits on top of it:
       BASE_REF=$(gh api repos/<REPO>/pulls/<NUMBER> --jq .base.ref)
       git fetch origin "$BASE_REF"
       COUNT=$(git rev-list --count HEAD ^$(git merge-base HEAD origin/"$BASE_REF"))
     If count == 1, report "Copilot LGTM — no squash needed." and stop.
  3. If count > 1: verify remote hasn't diverged (`git fetch origin <BRANCH>` then `git merge-base --is-ancestor origin/<BRANCH> HEAD`). If diverged, report and stop.
  4. Squash: `git reset --soft $(git merge-base HEAD origin/"$BASE_REF")`, then commit with PR title as subject, changes summary as body, and `Reviewed-by: copilot-pull-request-reviewer <copilot-pull-request-reviewer@github.com>` trailer. Force-push with lease.
  5. Report result. Delete this cron job.

**exit 3** — Fatal. Report POLL_OUT error string to user. Delete this cron job.
```

9. Then immediately run the first check now without waiting for the first cron fire.
