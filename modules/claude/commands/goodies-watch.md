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

**Before deciding:** Confirm at least one Copilot review exists:
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/reviews --jq '[.[] | select(.user.login | test("copilot"; "i"))] | length'

If the count is 0, no Copilot review has been submitted yet. Report "No Copilot review found — was it requested? Check the Reviewers sidebar in the GitHub PR interface." and delete this cron job.

**Case A — No pending review + no unreplied inline comments:**
Report "Copilot review complete — no unreplied inline comments. LGTM!" then:
1. Delete this cron job.
2. Check if there are multiple commits on the branch ahead of the base branch. If only one commit exists, there is nothing to squash or force-push — just report LGTM and stop.
3. If multiple commits exist: squash all commits on the current branch into a single commit. Use the PR title as the commit message subject and include a body summarizing the changes. Preserve any `Co-Authored-By` trailers from the squashed commits. Add a `Reviewed-by: copilot-pull-request-reviewer <copilot-pull-request-reviewer@github.com>` trailer. Force-push with lease.
4. Report the result. The user can re-run `/goodies-watch` to start a new watch cycle after pushing further changes.

**Case B — No pending review + unreplied inline comments exist:**
Notify the user "Copilot review has inline findings on PR #<NUMBER>!" and fetch the unreplied top-level comment details (exclude replies):
  gh api --paginate repos/<REPO>/pulls/<NUMBER>/comments --jq '[.[] | select(.user.login | test("copilot"; "i")) | select(.in_reply_to_id == null)] | .[] | {id, path, line, body}'

Filter to only unreplied ones, then present each finding with fix/dismiss/defer options. For each decision, state the rationale — why the fix was made or why the finding doesn't apply.

## Replying to comments

After the user decides on each finding (fix, dismiss, or defer), post a reply to that Copilot comment on GitHub using:
  gh api repos/<REPO>/pulls/<NUMBER>/comments -f body="<REPLY>" -f in_reply_to=<COMMENT_ID>

Reply format:
- **Fix**: "Fixed in <commit-sha>. <brief explanation of the change>."
- **Dismiss**: "Dismissed — <reason why it doesn't apply>."
- **Defer**: "Deferred — <reason>. Tracking in <issue-url if created>."
```

7. Then immediately run the first check now without waiting for the first cron fire.
