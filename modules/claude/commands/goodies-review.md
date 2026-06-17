---
allowed-tools: Bash, Read, Write
description: Structured human-expert collaboration on PR direction, design, and trade-offs (NOT code review)
---

# goodies-review

A slash command for human-expert PR collaboration. **Not a code-review bot** —
code-level findings are Copilot's job. This tool helps you discuss whether the
*problem* and *approach* are right, before debating code.

Design contract: see `docs/design/goodies-review.md` in the goodies repo.

## A note on confidence (LLM-generated content)

This command's runtime is an LLM — me, when invoked. Many outputs (thread
categorization, gatekeeper verdicts, reply drafts, dedupe matches) are
LLM-generated judgments, not deterministic computations. To make those
judgments checkable rather than opaque, every LLM-generated artifact is
annotated with a three-level qualitative confidence label and a one-sentence
rationale:

```
[confidence: high — <one-sentence checkable rationale>]
[confidence: medium — <what I'm uncertain about; what would resolve it>]
[confidence: low — <what's missing; flagged for expert review>]
```

**Discipline rule:** I do not output `[confidence: high]` without naming a
*citable artifact* (a line in a doc, content of a thread, observable
behavior in the index). If I cannot cite, the label is `medium` at best.
This makes the confidence checkable in seconds, not theatrical.

Three levels (not five, not numeric percent) because LLM judgment doesn't
support finer granularity honestly. `high` means "I checked the
load-bearing evidence and it holds up." `medium` means "I'm willing to
defend this, but here's what I'm not sure about." `low` means "this needs
expert review before being acted on."

The expert reads `low` and knows: spend the cycle here. Reads `high` with
a checkable rationale and knows: spend the cycle elsewhere.

---

## When invoked

Parse arguments:
- Bare number (`125`) → use the cwd's git remote as the repo.
- Qualified form (`<owner>/<repo>#<num>` or alias `optibot#125`) → split on `#`.
- Full PR URL → extract `<owner>/<repo>` and number.
- No args → resume from `~/.cache/goodies-review/active-context.json`'s `current` field, then *automatically run `--engage` on it* (default: lowest-numbered layer with open threads). Equivalent to `/goodies-review <last-active-PR> --engage`. If no `current` context exists, output: "no active context. Try /goodies-review <PR> to start one."
- `--list` → show all active contexts (see "Modes / list" below). No PR needed.
- `--status` → show statusline only for current context. No other action.
- `--show-purpose` → force-display the first-time banner.

Modes (parsed after the PR identifier):
- (no flag) → summary mode.
- `--engage [--layer <name>]` → walk open threads at a layer.
- `--reopen <thread-id>` → gatekeeper-mediated reopen.
- `--new-thread --layer <name>` → start a new top-level thread.

Layers: `problem`, `direction`, `design`, `tradeoff`, `implementation`.
Statuses: `open`, `proposing`, `resolved`, `deferred`.

## Step 0: Ensure state directory exists

Before any read/write under `~/.cache/goodies-review/`:
```bash
mkdir -p ~/.cache/goodies-review
```
This holds `banner-count`, `active-context.json`, and any draft files. Without
the parent dir, the first run fails when attempting to create them. Idempotent
— safe on every invocation.

## Step 0.1: First-time banner

Read `~/.cache/goodies-review/banner-count` (create file with `0` if missing).

If count < 3 OR `--show-purpose` was passed:

```
*** goodies-review is for human-expert collaboration on PR direction,    ***
*** design, and trade-offs -- NOT code review. Code-level findings are   ***
*** Copilot's job. Settle higher layers first.                           ***
*** Layers: problem -> direction -> design -> tradeoff -> implementation ***
```

Increment the count if `--show-purpose` was *not* passed (forced displays
don't count against the budget).

## Step 1: Resolve repo and PR

If the user passed a bare number:
```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
```
If that fails (cwd isn't a git repo), error: "no PR identifier and not in a git repo; pass `<owner>/<repo>#<num>` or `<url>`."

Verify the PR exists *and capture the head SHA + body* (used by Step 2.5 to
fetch linked design docs at the exact PR-head ref and to parse the body for
design-doc references):
```bash
PR_INFO=$(gh api "repos/$REPO/pulls/$PR" --jq '{number, state, title, base: .base.ref, head: .head.ref, head_sha: .head.sha, body}')
PR_HEAD_SHA=$(echo "$PR_INFO" | jq -r '.head_sha')
PR_TITLE=$(echo "$PR_INFO" | jq -r '.title')
PR_STATE=$(echo "$PR_INFO" | jq -r '.state')
PR_BODY=$(echo "$PR_INFO" | jq -r '.body // ""')
```
Bind `PR_HEAD_SHA`, `PR_TITLE`, `PR_STATE`, `PR_BODY` for use in subsequent
steps. (`PR_BODY` defaults to empty string when null so downstream
regex/scan operations don't error on missing-body PRs.)

The REST `state` field is **lowercase** (`open` / `closed`) — different
from GraphQL's uppercase `OPEN`/`CLOSED`. Compare accordingly. If the PR
is closed/merged (state != "open"), warn the user but allow read-only
modes (summary, list, status) to proceed; refuse `--engage` / `--reopen`
/ `--new-thread` (no point posting on a closed PR).

## Step 2: Fetch threads and review state

Pull all top-level review comments and replies (paginated):

```bash
gh api --paginate "repos/$REPO/pulls/$PR/comments" --jq '.[]'
```

(With `--paginate`, `--jq '.[]'` streams one object per line across all pages.
Collect into an array in the shell when needed: `... | jq -s '.'`)

Pull review-thread metadata (resolved status). Derive owner/repo-name from
`$REPO` (which is `<owner>/<repo>` from Step 1) so the GraphQL query has real
values, not literal placeholders:

```bash
OWNER="${REPO%/*}"
REPO_NAME="${REPO#*/}"
gh api graphql -f query='{ repository(owner: "'"$OWNER"'", name: "'"$REPO_NAME"'") { pullRequest(number: '"$PR"') { reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 100) { pageInfo { hasNextPage endCursor } nodes { databaseId body author { login } createdAt } } } } } } }'
```

**Paginate the *outer* `reviewThreads` connection** with
`reviewThreads(first: 100, after: "<cursor>")` until `pageInfo.hasNextPage`
is false. This handles PRs with >100 threads.

**Also paginate the *inner* `comments(first: 100)` connection** when any
thread's `comments.pageInfo.hasNextPage == true`. A long discussion within
a single thread can exceed 100 comments, and silently truncating the inner
connection means later replies (often the *resolution* comment) are
missing — which would cause the categorizer to misclassify status. Per
thread that paginates: re-query that thread's comments with `comments(first:
100, after: "<inner-cursor>")` and merge the additional pages into the
thread's comment list before categorization.

Pull general PR comments (top-level discussion, not inline-review):

```bash
gh api --paginate "repos/$REPO/issues/$PR/comments" --jq '.[]'
```

(Same `--paginate` streaming pattern — collect with `jq -s '.'` if an array is needed.)

## Step 2.5: Fetch grounding context

The gatekeeper, status inference, and reply drafting all need to reason
against the project's stated contracts — otherwise the LLM is making
judgments based only on the PR's local content, missing the project-wide
conventions that should constrain it.

Fetch:

1. **The target repo's CLAUDE.md** — try the conventional locations in order
   and take the first that exists. Different projects store Claude guidance
   under different paths; honoring all of them prevents grounding from being
   silently skipped on repos using the alternate locations:

   ```bash
   REPO_SLUG=$(echo "$REPO" | tr '/' '_')
   CLAUDE_MD_OUT=~/.cache/goodies-review/claude-md-${REPO_SLUG}-${PR}.txt
   for candidate in CLAUDE.md .claude/CLAUDE.md claude.md; do
     if gh api "repos/$REPO/contents/$candidate?ref=$PR_HEAD_SHA" 2>/dev/null \
          --jq '.content' | python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" > "$CLAUDE_MD_OUT" 2>/dev/null \
        && [ -s "$CLAUDE_MD_OUT" ]; then
       break
     fi
     rm -f "$CLAUDE_MD_OUT"
   done
   ```
   Path is under the already-created state directory `~/.cache/goodies-review/`
   (Step 0), not `/tmp` — fixed `/tmp` paths are vulnerable to symlink
   clobbering on multi-user systems and collide on concurrent runs. Best-
   effort: if none of the candidates exists, continue without grounding;
   note "no CLAUDE.md in target repo" in the statusline footer. Fetch is
   pinned to `$PR_HEAD_SHA` so the grounding reflects what's on the branch
   under review (master may have moved or even diverged).

2. **Linked design docs in the PR body.** Scan `$PR_BODY` (captured in Step
   1) for `docs/design/<area>/<name>.md` paths and full URLs to such files.
   Suggested regex: `docs/design/[A-Za-z0-9_/-]+\.md` for repo-relative paths
   plus `https://github.com/[^/]+/[^/]+/blob/[^/]+/docs/design/[^ )]+\.md` for
   absolute URLs. Deduplicate before fetching. For each match, derive a safe
   filename slug by replacing all `/` with `_` in the path component (e.g.,
   `docs/design/foo/bar.md` → `design-docs_design_foo_bar.md`), then fetch
   and save in one pipeline:
   ```bash
   SLUG=$(echo "<path>" | tr '/' '_')
   DESIGN_OUT=~/.cache/goodies-review/design-${REPO_SLUG}-${PR}-${SLUG}
   gh api "repos/$REPO/contents/<path>?ref=$PR_HEAD_SHA" --jq '.content' \
     | python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" \
     > "$DESIGN_OUT" 2>/dev/null || true
   ```
   If `$PR_BODY` is empty (no PR
   description), this step is a no-op — that's fine; the gatekeeper falls
   back to CLAUDE.md + project-conventions grounding only.

3. **Design docs added by *this* PR.** If the PR introduces files under
   `docs/design/`, treat those as design contracts the PR is establishing.
   The gatekeeper grounds against the doc's content + project conventions.

Read all fetched content and hold it as the *grounding context* for
subsequent steps. When the gatekeeper renders a verdict citing CLAUDE.md
section X or design-doc line Y, those citations refer to the fetched
content and are checkable by the expert in seconds.

## Step 3: Categorize each thread

For every thread (review-thread node from GraphQL or general PR comment):

1. **Read the first comment's body.** Look for a header at the top in the form:
   ```
   [review-pr / <layer> / <status>]
   ```
   If found, capture the author's claimed layer + status as a *primary*
   signal — but do not blindly trust it (see step 1.5).

1.5. **Header-vs-content mismatch check.** If a header is present, also infer
   the layer from the comment body using the heuristic in step 2 below. If
   the inferred layer differs from the header's claim:
   - **Surface the mismatch in the categorized output** with annotation
     `[via header · MISMATCH: header says <X>, content reads as <Y>]`.
   - **Render a confidence label** for the categorization:
     `[confidence: low — header-content mismatch detected; expert review
     recommended]`.
   - **Use the header's claim as the categorized layer** by default (the
     author's stated intent), but make the inconsistency visible so a human
     can correct it via override.

   This is what makes the loose format a *safety valve* not a blind trust
   zone: a misleading header (intentional or accidental) doesn't silently
   misclassify the thread.

2. **If no header, infer.** Read the comment body and decide:
   - **Layer:** is this about whether the *problem* is right? the *direction*? a
     specific *design* choice? a *trade-off* between alternatives? *code-level*
     concerns (typos, naming, off-by-one, missing fields)? Default unclear cases
     to `implementation` since most code-review bot output lands there.
   - **Status:** is the thread's last reply settling it (`resolved`)? proposing
     a resolution awaiting agreement (`proposing`)? still asking (`open`)?
     marked deferred by the participants (`deferred`)?

   If GitHub's `isResolved` is true, force status to `resolved` regardless of
   inference. Mark provenance `[inferred]`.

   **Render a confidence label per inference**, citing the load-bearing
   evidence. Examples:
   - `[confidence: high — explicit "fixed in <sha>" resolution + file:line
     context match implementation-layer pattern]`
   - `[confidence: medium — body mentions both architectural and
     implementation concerns; could be design layer or implementation]`
   - `[confidence: low — short comment with no clear layer signal; expert
     review recommended]`

   Per the "no high without citable artifact" rule (see top of doc), `high`
   is reserved for cases where the rationale points to a specific quotable
   element of the comment. Pure pattern-match without a citable artifact is
   `medium` at best.

3. **Detect cross-layer references.** If the comment includes
   `-> ref: [<layer> / <status>] thread #N`, record the dependency. Used in
   the gatekeeper's "wrong layer of resolution" detection.

4. **Build the layer-counter map.** For each of the 5 layers, count threads
   in `resolved` status and threads in `open|proposing` status.

## Step 4: Print the statusline

ASCII boxed format. Determine the maximum interior width from the title row
content (`<repo>#<PR> -- <PR title>`, capped at ~78 chars total to fit a
typical terminal). Pad rows accordingly.

Counter format: `<resolved>/<open>` per layer — both are non-negative
integers (e.g. `3/8` means 3 resolved, 8 open). Always emit the actual
counts; never emit literal `R/O` in real output (the placeholder is
spec-only, replaced at runtime).

```
+- <repo>#<PR> -- <title> -----+
| <current layer> * thread #<id>          |
| problem <r>/<o> * direction <r>/<o> * design <r>/<o> * tradeoff <r>/<o> * impl <r>/<o> |
+--------------------------------+
```

Concrete worked example with real numbers (note: `<r>/<o>` placeholders
become numerals at runtime):
```
+- intel-sandbox/os.linux.pnp.optibot#125 -- B9 design -----+
| design layer * thread #3411232637                          |
| problem 0/0 * direction 2/0 * design 3/8 * tradeoff 0/0 * impl 13/0 |
+------------------------------------------------------------+
```

For summary mode (no `--engage`), the second row instead reads:
```
| summary view -- 5 layers, <M> threads total                              |
```

## Step 5: Mode-specific behavior

### Summary mode (no `--engage`/`--reopen`/`--new-thread`)

After the statusline, print the categorized thread list:

```
PROBLEM (1 thread, 1 open)
  [open]   #thread-id by @user [inferred] -- "is this really the right problem to solve given X"
DIRECTION (3 threads, 2 resolved, 1 open)
  [resolved] #thread-id by @user [via header] -- "predicate language vs fixed schema"
  [resolved] #thread-id by @user [inferred]   -- "free-form transform_class vs enum"
  [open]   #thread-id by @user [via header] -- "should optimize-postmortem be sealed?"
DESIGN (8 threads, 8 resolved)
  ...
TRADEOFF (0 threads)
IMPLEMENTATION (13 threads, 13 resolved)
  ... (Copilot findings, all addressed)
```

Threads are listed in the order: layer (problem → implementation), then status
(open → proposing → resolved → deferred), then chronological. Each entry shows
thread id, author, provenance (header or inferred), and a short title (first
sentence or ~80 chars of the body).

After the listing, write the active context to
`~/.cache/goodies-review/active-context.json`:

```json
{
  "current": {"repo": "<owner>/<repo>", "pr": <PR>, "thread": null, "layer": null},
  "recent": [...]
}
```
(`recent` is updated by appending the current `{repo, pr, last_seen: <ISO ts>}`,
deduplicating by `repo + pr`, keeping the most recent 10.)

End the summary mode output with a hint:
```
Hint: /goodies-review <PR> --engage to walk open threads.
```

### `--engage [--layer <name>]` mode

Determine the engagement layer:
- If `--layer` was passed, use it.
- Otherwise, default to the lowest-numbered layer with at least one open thread.

**Layer-resistance check.** Before engaging at the determined layer, count
open threads at lower-numbered layers. If any exist:

```
NOTE: layer 1 (problem) has 1 open thread; engaging at layer 3 (design) anyway.
The hierarchy suggests settling lower layers first. Confirm to proceed (y/n)?
```

If user types anything other than 'y' or 'yes', stop. Otherwise continue.

For each open or proposing thread at the engagement layer:

1. Show the thread context: original comment, all replies, current state.
2. Show the file/line if it's an inline review comment (`<path>:<line>`).
3. Ask: "what's your position on this thread?" — open-ended; user types prose.
4. Drafts a reply using the user's prose, with header
   `[review-pr / <layer> / <status>]` where `<status>` is the user's claim
   (ask if unclear: "is this `proposing` a resolution, or keeping it `open`?").
5. **Show the draft** and ask "post this reply (y/n/edit)?":
   - `y`: post — but the API endpoint depends on the thread's *kind*,
     which we tracked when fetching in Step 2:
     - **Inline review-comment thread** (originated from
       `/pulls/$PR/comments` — has `path`/`line` + a `pull_request_review_id`):
       reply via the review-comment replies endpoint:
       ```bash
       gh api repos/<repo>/pulls/<PR>/comments/<thread-comment-id>/replies -f body="<draft>"
       ```
     - **General PR comment thread** (originated from
       `/issues/$PR/comments` — top-level discussion, no inline anchor):
       the review-comment replies API does not apply. Post a new general
       comment that quotes the original to anchor the conversation
       visually:
       ```bash
       # Header first (so the categorizer finds it at the top), then a
       # blockquote of the parent's first ~3 lines to anchor context,
       # then the reply body. GitHub renders this as a threaded
       # conversation in the issue-comment timeline.
       HEADER="[review-pr / <layer> / <status>]"
       PARENT_QUOTE=$(echo "<parent-body>" | head -3 | sed 's/^/> /')
       BODY=$(printf '%s\n\n%s\n\n%s' "$HEADER" "$PARENT_QUOTE" "<reply-body>")
       gh api repos/<repo>/issues/<PR>/comments -f body="$BODY"
       ```
       Note: this isn't a true reply (issue comments have no native
       threading), but the header-first + quote + chronological order
       keeps the conversation legible and categorizer-parseable. The
       `[review-pr / layer / status]` header is at the very top so
       future invocations parse it correctly — placing it after the
       blockquote would break header detection.
   - `n`: skip, move to next thread.
   - `edit`: let user revise; loop back to step 5.

After posting, optionally resolve the thread (only applies to inline
review-comment threads, since general PR comments have no resolve state):

```bash
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<THREAD_ID>"}) { thread { isResolved } } }'
```

Update the active-context file's `current` field with the engaged thread id +
layer.

### `--reopen <thread-id>` mode

**Identifier semantics.** The user passes the *visible numeric* thread id
(the one shown in `--engage` output and in URLs like
`https://github.com/<repo>/pull/<PR>#discussion_r3411232637` — the
`databaseId` of the thread's first comment). The command maps it
internally to the GraphQL opaque thread `id` (`PRRT_kwDO...`) needed for
the `resolveReviewThread` and reopen mutations. The mapping uses the
same `reviewThreads` query already fetched in Step 2: walk the threads
list, find the one whose first-comment `databaseId` matches the
user-supplied numeric id, take its `id` field. If no match, error:
"thread #<N> not found in PR #<PR>'s review threads. Did you pass the
right number? Look for `#discussion_r<N>` in the GitHub URL."

The thread must currently be `resolved`. If not, error: "thread #N is already
open; no reopen needed."

Print the thread's resolution context: original comment, replies, the
resolution comment(s).

Ask: "you're requesting to reopen this resolved thread. What's your reason?"
User types prose.

**Run the gatekeeper.** Evaluate the user's reason against three buckets:

1. **New evidence.** Does the reason cite a real instance, subsequent commit,
   downstream consequence, or new linked artifact (issue/doc/external) that
   the prior thread couldn't have considered?

2. **Internal inconsistency.** Does the reason point to a conflict between
   the resolution and another part of the project (CLAUDE.md, design docs,
   another resolved thread)?

3. **Wrong layer.** Does the reason argue the thread was resolved at the
   wrong hierarchy level (e.g. resolved at implementation when the issue is
   at design)?

Render one verdict:

- **Holds.** Output: "reason holds — bucket: <which one>." Draft the reopen
  comment with header `[review-pr / <layer-of-original> / open]`, include the
  user's reason, reference the prior resolution. Show draft, ask y/n/edit.

- **Doesn't hold.** Output: "reason doesn't yet hold — <specific feedback>."
  Examples of feedback:
  - "your reason restates preference X that thread #N's resolution already
    addressed at line Y; for a reopen you'd need [concrete missing element]."
  - "the cited evidence isn't new — it appears in thread #N's resolution
    comment."
  - "this is an authority appeal ('PM said'); the gatekeeper evaluates the
    architectural argument, not the source. What's the architectural issue?"

  Ask: "revise reason and retry, or override (drop the gatekeeper's decision
  and post anyway)?" If revise, loop. If override, proceed to draft with
  override marker (see below).

- **Borderline.** Output: "borderline — partial argument. Path to acceptance:
  <concrete next step>." Default disposition: don't reopen. Ask: "revise, or
  override?"

**Adjacent-not-reopen detection.** Before rendering the verdict, check
whether the user's reason is actually about the resolved question or
adjacent. If adjacent, output: "your reason isn't about thread #N's
resolution — it's a separate concern. Open a new thread under [Layer]?"
(suggest `--new-thread --layer <X>`).

**Override and record.** If the user overrides a "doesn't hold" or
"borderline" verdict:

```
[review-pr / <layer> / open * override: gatekeeper rejected]

The gatekeeper rejected this reopen as "<bucket-failure>", but I'm overriding
because [user's reason]. Other participants are welcome to weigh in.

[user's full reason]

Reference: thread #<N>'s resolution at <date>.
```

Show draft, ask y/n/edit, post on confirmation as a reply to the thread's
root comment:
```bash
gh api repos/<REPO>/pulls/<PR>/comments/<thread-id>/replies -f body="<COMMENT>"
```
(`<thread-id>` is the numeric `databaseId` of the first comment in the thread —
the same value the user supplied to `--reopen`. This keeps the reopen inside
the existing review thread rather than posting it as a top-level issue comment.)

**After posting, actually unresolve the GitHub thread.** A reopen comment
that leaves the GitHub-side thread marked `isResolved: true` is misleading
— the next reviewer's UI will still show it as a closed conversation, and
the categorizer's GitHub `isResolved` short-circuit (Step 3 step 2) would
keep classifying it as `resolved` even though the conversation is open.
Call the GraphQL mutation:

```bash
gh api graphql -f query='mutation { unresolveReviewThread(input: {threadId: "<THREAD_ID>"}) { thread { isResolved } } }'
```

`<THREAD_ID>` is the GraphQL opaque id mapped from the user-supplied
numeric id (see "Identifier semantics" above). Verify the response shows
`isResolved: false`; if not, surface the error to the user — the comment
posted but the thread didn't actually reopen, which they need to know.

### `--new-thread --layer <name>` mode

Ask: "what's the discussion topic at the <layer> layer? (full prose)"

Optional: ask for a cross-layer reference if the new thread depends on a
settled higher-layer thread. If user provides one, validate it (must be a
real thread id with status `resolved` at a higher-numbered layer than the
new thread's layer; warn otherwise).

Draft the new thread's top-level comment with header
`[review-pr / <layer> / open]` (and optional `-> ref: ...` line). Show
draft, ask y/n/edit, post via:

```bash
gh api repos/<repo>/issues/<PR>/comments -f body="<draft>"
```
(General PR comment, not inline review — new threads are top-level.)

After posting, update active-context's `current` to the new thread.

### `--list` mode

Read `~/.cache/goodies-review/active-context.json`. For each entry in
`recent` (up to 10), refetch the PR's thread state and print:

Counter format is the same as the statusline: `<resolved>/<open>` per
layer, with actual integers at runtime (the `<r>/<o>` placeholders below
are spec syntax, never emitted literally):

```
+- goodies-review * active contexts -------------------------------------+
|                                                                         |
| * <repo>#<PR> * <title>                                  [last: 2m ago]|
|   problem <r>/<o> * direction <r>/<o> * design <r>/<o> * tradeoff <r>/<o> * impl <r>/<o> |
|                                                                         |
|   ...                                                                   |
|                                                                         |
+- * = current * switch via /goodies-review <repo>#<pr> -----------------+
```

Concrete worked example with real numbers:
```
+- goodies-review * active contexts -------------------------------------+
|                                                                         |
| * optibot#125 * B9 optimization loop design          [last: 2m ago]    |
|   problem 0/0 * direction 2/0 * design 3/8 * tradeoff 0/0 * impl 13/0  |
|                                                                         |
|   goodies#42 * --feedback flag                       [last: 1h ago]    |
|   problem 0/1 * direction 0/0 * design 0/2 * tradeoff 0/0 * impl 0/0   |
|                                                                         |
+- * = current * switch via /goodies-review <repo>#<pr> -----------------+
```

Mark the `current` entry with `*`. "last seen" is rendered as relative time.

If active-context.json doesn't exist or has no recent entries, output:
"no active contexts. Try /goodies-review <PR> to start one."

### `--status` mode

Read active-context. Print the statusline for `current` (without summary
listing). If no current, output: "no active context. Try /goodies-review
<PR> to start one."

## Worked example

Walking through optibot#125 (a real PR's discussion shape):

```
$ /goodies-review optibot#125

[banner — first invocation]

+- intel-sandbox/os.linux.pnp.optibot#125 -- docs(optimization): B9 ... -+
| summary view -- 5 layers, 23 threads total                              |
| problem 0/0 * direction 0/0 * design 0/0 * tradeoff 0/0 * impl 23/23   |
+-------------------------------------------------------------------------+

PROBLEM (0 threads)
DIRECTION (0 threads)
DESIGN (0 threads)
TRADEOFF (0 threads)
IMPLEMENTATION (23 threads, 23 resolved)
  [resolved] #3411232501 by @Copilot [inferred] -- "Flow A's Workload.score events..."
  [resolved] #3411232525 by @Copilot [inferred] -- "Flow E's Workload.score events..."
  ... (21 more, all Copilot inline findings, all addressed)

Hint: PROBLEM/DIRECTION/DESIGN/TRADEOFF have no threads. The PR's discussion
has been entirely at the implementation layer (Copilot findings). For a
broader review on direction or design, /goodies-review optibot#125 --new-thread
--layer <name>.
```

The hint surfaces what the hierarchy reveals: this PR has had no
human-expert engagement at the higher layers. That's a fact, not a judgment
— but it's the kind of fact that's useful to see at a glance before merging
a major design-doc PR.

### Worked example: gatekeeper at work

```
$ /goodies-review optibot#125 --reopen 3411232637

[statusline]

Thread #3411232637's resolution context:
  Original (Copilot): "expected_delta type inconsistency..."
  Resolution (Tianyou): "Fixed in 78462a6. Picked one representation:
                        expected_delta is object<string, number>..."

What's your reason for reopening?
> The number-only constraint is too strict — what if a metric needs a
  range (e.g. 'IPC delta in [+0.2, +0.5]')?

Gatekeeper evaluating...

VERDICT: doesn't hold.
  Bucket failure: this is speculation without instances. The reason cites a
  hypothetical ("what if a metric needs..."), not a real workload that
  requires range-typed deltas. The original thread's resolution explicitly
  rejected ranges as untestable; for a reopen, you'd need a concrete
  workload where range-typed deltas would be honest *and* testable.

Path to acceptance: cite a workload (real or about-to-ship) where
range-typed deltas are necessary and the testability concern can be met.

Revise reason, or override (drop the gatekeeper's decision and post anyway)?
> revise

What's your revised reason?
> ...
```

The gatekeeper's job is to surface what's missing. Override is always
available; the rejection is a prompt to think, not a wall.

## Loose-format header reference

Tool-emitted comment headers:

```
[review-pr / <layer> / <status>]
```

With cross-layer reference:

```
[review-pr / design / open] -> ref: [problem / resolved] thread #N
```

With override marker:

```
[review-pr / <layer> / <status> * override: gatekeeper rejected]
```

Layers: `problem`, `direction`, `design`, `tradeoff`, `implementation`.
Statuses: `open`, `proposing`, `resolved`, `deferred`.

Other tools (Copilot, free-form human comments) need not include the header —
the inference fallback handles them.

## Error and edge cases

- **Closed/merged PR:** read-only modes proceed; mutating modes refuse.
- **Empty PR (no comments yet):** all layers show `0/0`. `--engage` outputs
  "no open threads to engage." `--new-thread` works normally.
- **Network failure mid-engagement:** save the user's drafted reply to
  `~/.cache/goodies-review/draft-<repo-slug>-<pr>-<thread>.txt` (where
  `<repo-slug>` replaces `/` with `_`, e.g. `owner_repo`) so they can retry.
- **GraphQL pagination:** always paginate; PRs with >100 threads must work.
- **gh auth not configured:** error with a hint to run `gh auth login`.
- **Banner state file missing:** create with `0`, treat as first invocation.
- **Active-context state file missing:** treat as no recent contexts.
