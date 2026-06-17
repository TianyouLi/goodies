---
allowed-tools: Bash, Read, Write, AskUserQuestion
description: Structured human-expert collaboration on PR direction, design, and trade-offs (NOT code review)
---

# goodies-review

A slash command for human-expert PR collaboration. **Not a code-review bot** —
code-level findings are Copilot's job. This tool helps you discuss whether the
*problem* and *approach* are right, before debating code.

Design contract: see `docs/design/goodies-review.md` in the goodies repo.

## Internal design vs. what the user sees

This spec uses internal machinery the **user must never see**: layer
pattern/anti-pattern codes (`DS5`, `AP2`, `T1`, `P12` …) from the layer files,
`[n]` citation markers, and the mode flags (`--engage`, `--reopen`,
`--new-thread`). The runtime *reasons* with these — to load catalogs, ground
claims, and route — but **translates everything to plain language before it
reaches the screen.**

- **Internal (keeps codes):** `docs/design/goodies-review.md`, the
  `layers/*.md` catalogs, `references.md`, and the routing logic in this file.
  Each catalog code has a meaningful *title* — that title (or a short paraphrase)
  is what the user sees, never the code.
- **User-facing (plain words only):** every prompt, option, proposed topic,
  statusline, and drafted comment. No `DS5`, no `[3]`, no `--engage`, no
  internal scenario ids. When the runtime cites a catalog match, it uses the
  entry's plain name (e.g. "one class doing too many jobs", not "DS5").

This rule is load-bearing for the whole UX; every section below assumes it.

## A note on confidence (LLM-generated content)

This command's runtime is an LLM — me, when invoked. Many outputs (thread
categorization, proposed topics, gatekeeper verdicts, reply drafts, dedupe
matches) are LLM-generated judgments, not deterministic computations. Each such
judgment is annotated with a three-level confidence so it stays checkable.

**Internally** the levels are `high` / `medium` / `low` with this discipline:
`high` requires a *citable artifact* (a line in a doc, content of a thread,
observable behavior) — without one, the label is `medium` at best; `medium`
means "willing to defend, but here's the uncertainty"; `low` means "flagged for
expert review."

**To the user** these render as a plain leading tag — `(high)` / `(medium)` /
`(low)` — on each item, with a short footnote legend (see "Landing view"). No
`[confidence: …]` syntax on screen.

---

## When invoked

Parse arguments (these flags are an *internal* entry shortcut; the normal user
never types them — they fall out of the conversational routing below):

- Bare number (`125`) → use the cwd's git remote as the repo.
- Qualified form (`<owner>/<repo>#<num>` or alias `optibot#125`) → split on `#`.
- Full PR URL → extract `<owner>/<repo>` and number.
- No args → resume the last-active context from
  `~/.cache/goodies-review/active-context.json`'s `current`. If none, say:
  "no active discussion yet — give me a PR to look at."
- `--list` → show all active contexts across PRs (no PR identifier needed); see
  "Active contexts list" in Step 5.
- `--status` → show the statusline for the current context only (no PR
  identifier needed); see "Status" in Step 5.
- `--show-purpose` → force-display the first-time banner (Step 0.1), regardless
  of the banner count.

(`--list` / `--status` / `--show-purpose` are resolved before PR resolution, so
they never try to resolve a PR.)

Internal mode targets (never surfaced to the user as such) and their CLI-flag
shortcut forms: summary/landing (no flag), engage a thread
(`--engage [--layer <name>]`), reopen a resolved thread (`--reopen <thread-id>`),
start a new thread (`--new-thread [--layer <name>]`). The conversational routing
in "Session entry flow" maps the user's plain-language intent onto one of these
— the user picks a numbered item or talks, never types a flag — but the flags
remain valid internal entry points (and are how the design contract names the
sub-flows).

Layers (internal taxonomy; shown to the user as the plain words themselves):
`problem`, `direction`, `design`, `tradeoff`, `implementation`. The one allowed
abbreviation is `impl` for `implementation` in the fixed-width statusline
counter row (Step 4), where the full word would overflow the box; everywhere
else the layer is spelled out in full.
Statuses: `open`, `proposing`, `resolved`, `deferred`.

## The governing rule

> **No new thread unless the topic is really new. Always prefer continuing an
> existing discussion.**

Before creating any new top-level thread — from a proposed topic, a
user-supplied topic, or an off-topic aspect split out mid-reply — the runtime
checks every existing thread (open AND resolved) for a matching
`(layer, aspect)`. If one exists, it routes the user to **continue** that
thread (a reply), or to **reopen** it if it's resolved — never opens a
duplicate. A new thread is created **only** when no existing thread, open or
resolved, is about this `(layer, aspect)`.

A second, related rule — **one topic per top-level comment**: each top-level
comment holds exactly one `(layer, aspect)`; all discussion of it is threaded
replies. The runtime refuses to draft a comment carrying two topics (it splits
them) and refuses to fold an off-topic aspect into a reply (it holds it and
routes it per the governing rule above).

Both rules are **enforced, not advisory** — see Step 5 for the enforcement
points in each flow.

## Session entry flow

Every interaction is the same cycle:

> **The command *supplies*, the user *reviews* and *provides input*, that input
> *forms* the comment or reply, and the user *confirms* before anything posts.**
> The command never authors-and-posts on its own — it proposes, the human
> shapes and approves.

The tool's voice is **conversational, not a mode picker.** A session opens by
*surveying what's already there* and inviting discussion — the user talks or
picks a number; the runtime infers where that routes.

**Order of operations at entry:**

1. **Survey the existing discussion** (Step 2 fetch → Step 3 categorize →
   Step 4 counts), **excluding Copilot-authored threads** (see Step 3) — those
   are code review, not our lane.
2. **Scan for proposed topics** (only if useful): read the grounding artifacts
   (Step 2.5) against the layer catalogs and surface candidate topics —
   **pre-filtered** to genuinely new ground (drop anything already covered by an
   existing thread, per the governing rule).
3. **Render the landing view** (Step 5 → Landing view): two groups (existing
   discussion / proposed topics), each sorted high→low by confidence, unified
   numbering across both, one tight line per item.
4. **Invite input.** The user types a number (→ that item's detail) or talks
   freely (→ runtime infers the route and says which, so the user can redirect).

The internal routing targets:

- a number in **existing discussion** → continue it (reply), or reopen it if
  it's resolved (gatekeeper);
- a number in **proposed topics** → open it as a new thread (after the
  governing-rule check);
- **prose** → the runtime infers: does it pick up an existing thread, reopen a
  resolved one, or raise new ground? It states the inferred route in plain
  words ("sounds like a new design topic — …") before drafting, so the user can
  correct it.

**What an "aspect" is.** A discussion topic stated as *(which layer) + (the
specific concern/flaw it raises)* — grounded in a layer-catalog entry
*internally*, surfaced by that entry's plain name. Never a vague "could be
better." Crucially (see Step 5 → new thread), an aspect must be a genuine
higher-layer discussion point — **not a code-level defect relabeled.** If a
candidate reduces to "a line that throws / a missing await / an unindexed
column / a null check," it is Copilot's lane and is dropped, no matter how it's
labeled.

## Step 0: Ensure state directory exists

Before any read/write under `~/.cache/goodies-review/`:
```bash
mkdir -p ~/.cache/goodies-review
```
This holds `banner-count`, `active-context.json`, and working draft files.
Idempotent — safe on every invocation.

## Step 0.1: First-time banner

Read `~/.cache/goodies-review/banner-count` (create with `0` if missing).

If count < 3 OR `--show-purpose` was passed:

```
*** goodies-review is for human-expert collaboration on PR direction,    ***
*** design, and trade-offs -- NOT code review. Code-level findings are   ***
*** Copilot's job. Settle higher layers first.                           ***
*** Layers: problem -> direction -> design -> tradeoff -> implementation ***
```

Increment the count unless `--show-purpose` was passed (forced displays don't
count against the budget).

## Step 1: Resolve repo and PR

If the user passed a bare number:
```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
```
If that fails (cwd isn't a git repo), error: "no PR identifier and not in a git
repo; pass `<owner>/<repo>#<num>` or `<url>`."

Verify the PR exists and capture head SHA + body (Step 2.5 fetches linked
design docs at the PR-head ref and parses the body):
```bash
PR_INFO=$(gh api "repos/$REPO/pulls/$PR" --jq '{number, state, title, base: .base.ref, head: .head.ref, head_sha: .head.sha, body}')
PR_HEAD_SHA=$(echo "$PR_INFO" | jq -r '.head_sha')
PR_TITLE=$(echo "$PR_INFO" | jq -r '.title')
PR_STATE=$(echo "$PR_INFO" | jq -r '.state')
PR_BODY=$(echo "$PR_INFO" | jq -r '.body // ""')
```
(`PR_BODY` defaults to empty string when null so downstream scans don't error.)

The REST `state` field is **lowercase** (`open`/`closed`) — unlike GraphQL's
uppercase. If the PR is closed/merged (state != "open"), warn but allow
read-only (landing view) to proceed; refuse posting (engage/reopen/new thread).

## Step 2: Fetch threads and review state

Pull all top-level review comments and replies (paginated):
```bash
gh api --paginate "repos/$REPO/pulls/$PR/comments" --jq '.[]'
```
(With `--paginate`, `--jq '.[]'` streams one object per line across all pages;
collect with `jq -s '.'` when an array is needed.)

Pull review-thread metadata (resolved status). Derive owner/repo-name from
`$REPO`:
```bash
OWNER="${REPO%/*}"
REPO_NAME="${REPO#*/}"
gh api graphql -f query='{ repository(owner: "'"$OWNER"'", name: "'"$REPO_NAME"'") { pullRequest(number: '"$PR"') { reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 100) { pageInfo { hasNextPage endCursor } nodes { databaseId body author { login } createdAt } } } } } } }'
```

**Paginate the outer `reviewThreads`** with `reviewThreads(first: 100, after:
"<cursor>")` until `pageInfo.hasNextPage` is false (handles >100 threads).
**Also paginate the inner `comments(first: 100)`** when a thread's
`comments.pageInfo.hasNextPage == true` — a long discussion can hide the
resolution comment past the first 100, which would misclassify status.

Pull general PR comments (top-level discussion, not inline-review):
```bash
gh api --paginate "repos/$REPO/issues/$PR/comments" --jq '.[]'
```

## Step 2.5: Fetch grounding context

The gatekeeper, status inference, topic scan, and reply drafting all reason
against the project's stated contracts — otherwise the LLM judges only from the
PR's local content. Fetch:

1. **The target repo's CLAUDE.md** — try conventional locations, first hit wins:
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
   Path is under the state directory (not `/tmp` — symlink-clobber + concurrent-
   run safety). Best-effort: if none exists, continue without it; note "no
   CLAUDE.md in target repo" in the footer. Pinned to `$PR_HEAD_SHA` so grounding
   matches the branch under review.

2. **Linked design docs in the PR body.** Scan `$PR_BODY` for repo-relative
   `docs/design/[A-Za-z0-9_/-]+\.md` paths, plus same-repo blob URLs
   `https://github.com/$REPO/blob/[^/]+/docs/design/[^ )]+\.md` (reduce a matched
   URL to its repo-relative `docs/design/...` path before fetching). Only
   same-repo docs are supported — the fetch uses `repos/$REPO/contents/<path>`,
   so a cross-repo `github.com/<other>/<other>/blob/...` URL cannot be resolved;
   skip such URLs (note them in the footer) rather than fetching them from the
   wrong repo. Deduplicate, then fetch each at the PR-head ref:
   ```bash
   SLUG=$(echo "<path>" | tr '/' '_')
   DESIGN_OUT=~/.cache/goodies-review/design-${REPO_SLUG}-${PR}-${SLUG}
   if gh api "repos/$REPO/contents/<path>?ref=$PR_HEAD_SHA" --jq '.content' 2>/dev/null \
        | python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" > "$DESIGN_OUT" 2>/dev/null \
      && [ -s "$DESIGN_OUT" ]; then
     : # kept — fetch succeeded and file is non-empty
   else
     rm -f "$DESIGN_OUT"   # drop empty/failed fetch so later steps don't treat it as grounding
   fi
   ```
   Mirror the CLAUDE.md fetch: only keep the file if the fetch succeeded and the
   content is non-empty; otherwise remove it, so a 404/auth/network failure can't
   leave an empty file that the topic scan or gatekeeper mistakes for real
   grounding. If `$PR_BODY` is empty, this whole step is a no-op.

3. **Design docs added by *this* PR** (files under `docs/design/`) — treat as
   the design contracts the PR establishes.

4. **The layer pattern catalogs.** Both the proposed-topics scan and engaging a
   thread need the layer catalogs (named patterns + anti-patterns) so claims are
   grounded in recognized practice, not ad-hoc opinion. The files live alongside
   this command; resolve the path through the command's own symlink so it works
   regardless of where goodies is checked out. Whitelist the layer name first —
   it can come from user input and is interpolated into a path, so only the five
   known layers are valid (blocks traversal like `../../../etc/passwd`):
   ```bash
   case "<layer>" in
     problem|direction|design|tradeoff|implementation) ;;
     *) echo "unknown layer '<layer>' (expected: problem|direction|design|tradeoff|implementation)"; exit 1 ;;
   esac
   CMD_REAL=$(python3 -c "import os; print(os.path.realpath(os.path.expanduser('~/.claude/commands/goodies-review.md')))")
   LAYER_FILE="$(dirname "$CMD_REAL")/goodies-review/layers/<layer>.md"
   if [ -f "$LAYER_FILE" ]; then
     cat "$LAYER_FILE"
   else
     # Best-effort degradation: emit an explicit marker so the runtime can note
     # it in the footer instead of producing silent empty output.
     echo "no pattern guidance for <layer> layer (missing $LAYER_FILE)"
   fi
   ```
   Load the layer(s) in play (all five at the landing-view scan; the engaged
   layer when continuing a thread). Hold the catalog **internally** — its codes
   (`DS5`, `AP2`, …) ground the runtime's reasoning but are translated to the
   entry's plain title before anything reaches the user (see "Internal design vs.
   what the user sees"). If a file is missing (older checkout), note "no pattern
   guidance for <layer> layer" in the footer and continue without named grounding.

Hold all fetched content as *grounding context*. Citations the runtime makes
(CLAUDE.md section X, design-doc line Y) refer to this content and are checkable
by the expert in seconds.

## Step 3: Categorize each thread

**First, filter out Copilot.** This tool is human-expert collaboration, not code
review. Exclude any thread whose first-comment author login matches the
case-insensitive substring/regex `copilot` — i.e. `login | test("copilot"; "i")`,
the same predicate goodies-watch uses — so bot variants like `Copilot` and
`github-copilot[bot]` are all caught (not an exact-equality check). Apply the
filter to the survey, the counts, the routing options, and the topic scan. Copilot's
code-review threads are never surfaced for engagement. (Keep a single quiet
footer line noting how many were set aside, e.g. "3 Copilot code-review threads
set aside — that's Copilot's lane.")

For every *remaining* (human) thread:

1. **Read the first comment's body.** Look for a tool-emitted tag at the top:
   ```
   <layer> / <status> — <short headline>
   ```
   If present, capture the claimed layer + status as a *primary* signal — but
   verify (step 1.5). Parse the **status as the first token after `/`**, and
   treat anything after a ` · ` as an annotation, not part of the status — a
   reopen-over-override comment carries the variant
   `<layer> / open · override: gatekeeper rejected — <headline>`, where the
   status is still `open`. (Older comments may carry a legacy
   `[review-pr / layer / status]` header; still parse it, but the tool no longer
   emits that form — see Step 5 and "Comment header reference".)

1.5. **Tag-vs-content mismatch check.** If a tag is present, also infer the layer
   from the body (step 2). If they differ:
   - surface the mismatch in the listing: `(tag says <X>, reads as <Y>)`;
   - render confidence `(low)` with rationale "tag/content mismatch; expert
     review recommended";
   - use the tag's claim by default (author's stated intent) but keep the
     inconsistency visible for override.

2. **If no tag, infer.** From the body decide:
   - **Layer:** problem? direction? a specific design choice? a trade-off?
     code-level (typos/naming/off-by-one/missing fields)? Default unclear to
     `implementation`.
   - **Status:** last reply settling it (`resolved`)? proposing a resolution
     (`proposing`)? still asking (`open`)? participant-deferred (`deferred`)?

   If GitHub's `isResolved` is true, force `resolved`. Mark provenance
   `(inferred)`. **Render confidence** citing the load-bearing evidence; `high`
   only with a quotable element.

3. **Detect cross-layer references.** If the body includes
   `-> ref: <layer> / <status> thread #N`, record the dependency (used by the
   gatekeeper's wrong-layer detection).

4. **Build the layer-counter map.** For each of the 5 layers, count `resolved`
   vs `open|proposing` threads (Copilot already excluded).

## Step 4: Counts and statusline

ASCII boxed, interior width from the title row (`<repo>#<PR> -- <title>`, capped
~78 chars). Counter per layer is `<resolved>/<active>`, where the second number
is the count of `open` + `proposing` threads (i.e. everything not yet resolved
or deferred — matching the `open|proposing` grouping in Step 3), NOT just
`open`. Real integers at runtime; the `<r>/<o>` in the diagram below is
spec-only shorthand. Copilot threads are NOT counted.

```
+- <repo>#<PR> -- <title> --------------------------------------------+
| <context line>                                                      |
| problem <r>/<o> * direction <r>/<o> * design <r>/<o> * tradeoff <r>/<o> * impl <r>/<o> |
+---------------------------------------------------------------------+
```

The `<context line>` is `looking together — <M> human threads, <K> Copilot set
aside` at the landing view, or `<layer> · thread #<id>` when inside a thread.

## Interactive flow (shared contract)

Every prompt below follows this one contract, so the vocabulary stays consistent
across flows. Token matching is case-insensitive and whitespace-trimmed.

### Navigation model: levels, and `(n)o` goes back

The session is a **level hierarchy**, not a flat set of commands:

```
landing view (the numbered list)
  -> item detail (you picked a number -- the full picture)
       -> draft (a reply/comment shown for confirmation)
```

`(n)o` means **back up one level** — it is *not* a terminal abort. From a draft,
`no` returns to the item detail; from the detail, back to the list; from the
list, out of the session. The user climbs out by choosing `no` repeatedly.
**There is no `quit`/`q` token.**

### Prompt archetypes

- **Confirm `(y)es, (n)o, (e)dit?`** — shown after a drafted reply/comment.
  `y`/`yes` posts; `n`/`no` backs up a level without posting; `e`/`edit` enters
  the edit loop. (Render the shortcut letter parenthesized in the word, exactly
  as `(y)es, (n)o, (e)dit?`, so the single-key answer is self-evident.)
- **Confirm `(y)es, (n)o?`** — a yes/no gate with no draft to edit (e.g. "add
  this to the existing thread?"). `y` proceeds; `n` backs up.
- **Disposition `(revise/override)`** — the gatekeeper verdict prompt. `revise`
  re-collects the user's prose and retries; `override` proceeds despite the
  verdict (with the override marker).
- **Prose** — free-form input (a position, a reopen reason, a topic). No token
  list. The way back from a prose prompt is **empty input (just Enter)** — it
  carries no content, so it can't collide with a real answer, and it means
  "never mind, back up a level."
- **Selection** — pick from a fixed set (a numbered landing item; the
  multi-select topic triage). May use `AskUserQuestion` (see below); the user
  may also just type the number, or talk.

### Input mechanics (widget vs. text)

`AskUserQuestion` is used **only** for selection from a fixed set — chiefly the
multi-select topic triage, and optional disambiguation when the user's prose is
genuinely ambiguous. It is **not** the front door: the default entry is the
conversational landing view + open invitation to talk. Everything that is
free-form (positions, reasons, topics) stays text; the simple confirms stay
text tokens. `AskUserQuestion` always offers an "Other" escape, so a selection
never traps the user. When the tool is unavailable (headless), every selection
falls back to a numbered text prompt (type the number(s)).

### Edit loop

On `edit`, prompt for the revised text, replace the working draft with it
(rewriting the draft file — see below), and re-present the *same* confirm
prompt. A draft is **never** posted without an explicit `y`.

### Working drafts live on disk (context-lean)

The runtime is the LLM, so an "in-session" draft would otherwise sit in the
conversation window and bloat it across a long multi-thread session. Instead,
the working draft is **externalized**:

- On draft creation/edit: Write it to
  `~/.cache/goodies-review/draft-<repo-slug>-<pr>-<thread-or-new>.txt`
  (`<repo-slug>` replaces `/` with `_`).
- `(n)o` (back) from a draft: the file **persists**; returning to that item
  reads it back, so edits aren't lost within the session.
- On successful post, or session end: delete the draft file.

The draft file is the single source of truth for an in-progress draft (this also
covers the old network-failure rescue case); context holds it only while it's on
screen.

### Unrecognized input

At a token prompt (not prose), input matching no token is re-prompted once,
echoing the valid options. A second unrecognized response falls back to the
**non-mutating** default — `(n)o`/back at a confirm prompt, don't-reopen at a
gatekeeper prompt. Unrecognized input is never treated as `y`, so a typo can
never post or resolve.

## Step 5: Behavior by flow

### Landing view (the default — survey + invite)

After Step 4, render the two groups. **Never interleave them**; each is a
labeled block, each sorted **high→low by confidence**, with **unified continuous
numbering** running through both (existing discussion first, then proposed
topics). One tight, aligned line per item; the full description appears only
when the user picks the number.

```
Let's look at <repo>#<PR> — "<title>" — together.

Existing discussion
  1  (high)    direction · @marcus · proposing — <short headline>
  2  (medium)  problem   · @priya  · open        — <short headline>
  3  (medium)  tradeoff  · @priya  · open        — <short headline>

Proposed topics (new ground not yet discussed)
  4  (medium)  design    · new                   — <short headline>

  how sure:  (high) checked, holds up · (medium) worth raising, uncertain ·
             (low) a hunch, your call

(3 Copilot code-review threads set aside — that's Copilot's lane.)

Type a number to dig in, or just say what's on your mind:
```

Notes:
- Each headline follows the **violation + impact + what's-now** shape, compressed
  to one line (see "Topic/headline formula" under new thread).
- "Proposed topics" is **pre-filtered** to new ground: drop any candidate whose
  `(layer, aspect)` matches an existing thread (open or resolved) — the two
  groups are disjoint by construction. If the scan finds nothing new, say so:
  "nothing new beyond what's already being discussed."
- The proposed-topics scan obeys the no-laundering rule (no code-level defects
  reframed as aspects) and the no-codes rule (plain names, never `DS5`).
- Then write active context to `~/.cache/goodies-review/active-context.json`:
  ```json
  {"current": {"repo": "<owner>/<repo>", "pr": <PR>, "thread": null, "layer": null},
   "recent": [...]}
  ```
  (`recent`: append `{repo, pr, last_seen: <ISO ts>}`, dedupe by `repo+pr`, keep
  10 most recent.)

**Picking a number** opens that item's detail (item detail level):
```
> 4

  Proposed topic · design · new ground                     (how sure: medium)

  <full plain-language description: the violation, why it costs something,
   and what the current design commits to>

  Open this as a new discussion?   (y)es, (n)o, (e)dit?
```
(`yes` → draft via the new-thread flow; `no` → back to the list; `edit` → adjust
the angle, then re-present.)

**Talking instead** routes by inference: the runtime states the route it
inferred in plain words and proceeds, e.g. "sounds like a new design topic — let
me draft it" or "that's @priya's open tradeoff thread (#3) — let me take you
there." The user can redirect before any draft is shown.

### Continue an existing thread (engage)

Entered by picking an open/proposing existing-discussion item (or inferred from
prose).

**Layer-resistance soft-warn (per the design contract).** Before engaging a
thread, if any *lower-numbered* layer (problem → … → implementation) still has
an open thread, surface a one-line warning — e.g. "the problem layer still has
an open question; settling lower layers first usually goes better — continue at
design anyway? (y)es, (n)o?" This is a soft warn, not a block: `y` proceeds, `n`
backs up to the landing view. It preserves the hierarchy discipline while
respecting the expert's judgment.

For the chosen thread:

1. Show the context: original comment, all replies, current state; the file/line
   if it's an inline review comment.
2. If the thread matches a named catalog pattern, surface it **by plain name**
   ("this reads like the 'problem stated as a solution' concern"), never a code.
3. Ask **(prose):** "what's your position?" Empty input backs up a level.
4. **Enforce topic scope (the governing rule).** Before drafting, check whether
   the user's input raises an aspect *different* from this thread's. If it does:
   - **exclude** the off-topic part from the reply (don't merely flag it) — the
     reply stays scoped to this thread's one aspect;
   - **hold** the off-topic aspect, and route it per the governing rule: if it
     matches an existing thread, offer to continue that one; only if it's
     genuinely new ground does it become a new thread. Surface this in plain
     words, e.g. "the TTL point belongs with @priya's open tradeoff thread —
     I'll offer it there after we post this."
5. Draft the on-topic reply. If a catalog pattern applies, cite it **by name**.
   Write the draft to the draft file.
6. **Show the draft, ask `(y)es, (n)o, (e)dit?`** (confirm archetype). On `y`,
   post by thread kind (tracked in Step 2):
   - **Inline review-comment thread** (`/pulls/$PR/comments`, has `path`/`line`):
     ```bash
     gh api repos/<repo>/pulls/<PR>/comments/<thread-comment-id>/replies -f body="<draft>"
     ```
   - **General PR comment thread** (`/issues/$PR/comments`, no inline anchor):
     no reply endpoint; post a new comment that tags + quotes the parent so it
     reads as threaded and the categorizer can parse it:
     ```bash
     TAG="<layer> / <status> — <short headline>"
     PARENT_QUOTE=$(echo "<parent-body>" | head -3 | sed 's/^/> /')
     BODY=$(printf '%s\n\n%s\n\n%s' "$TAG" "$PARENT_QUOTE" "<reply-body>")
     gh api repos/<repo>/issues/<PR>/comments -f body="$BODY"
     ```
     The full `<layer> / <status> — <short headline>` tag is the first line (same
     format as every other tool-emitted comment — see "Comment header reference")
     so future runs parse and summarize it consistently.
7. After a successful post, delete the draft file. Optionally resolve the thread
   (inline review-comment threads only):
   ```bash
   gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<THREAD_ID>"}) { thread { isResolved } } }'
   ```
8. If an aspect was held in step 4, now act on its route (continue the matching
   thread, or — only if truly new — open a new one). Update active-context's
   `current` to the engaged thread + layer.

### Reopen a resolved thread

Entered by picking a *resolved* existing-discussion item (or inferred). The user
gives a numeric thread id internally mapped to the GraphQL opaque id via the
`reviewThreads` query from Step 2 (match first-comment `databaseId`). If no
match: "thread #<N> not found in this PR's review threads." If the thread isn't
resolved: "thread #N is already open; no reopen needed."

Print the resolution context (original, replies, resolution comment). Ask
**(prose):** "what's your reason for reopening?"

**Adjacent-not-reopen check first.** If the reason isn't about the resolved
question but an adjacent concern, route per the governing rule: prefer an
existing thread if one matches; otherwise "that's separate — open a new
discussion under <layer>?" `(y)es, (n)o?`

**Run the gatekeeper.** Evaluate the reason against three buckets:

1. **New evidence** — a real instance, later commit, downstream consequence, or
   new linked artifact the prior thread couldn't have considered.
2. **Internal inconsistency** — a conflict between the resolution and another
   part of the project (CLAUDE.md, design docs, another resolved thread).
3. **Wrong layer** — the thread was resolved at the wrong hierarchy level.

Render one verdict:

- **Holds** — "reason holds — basis: <which bucket>." Draft the reopen with the
  full first-line tag `<layer-of-original> / open — <short headline>` (the same
  canonical form as every tool-emitted comment — don't omit the headline);
  include the reason, reference the prior resolution. Show draft,
  `(y)es, (n)o, (e)dit?`
- **Doesn't hold** — "doesn't yet hold — <specific feedback>" (e.g. "restates a
  preference the resolution already addressed at line Y; you'd need <missing
  element>"). Then disposition `(revise/override)`.
- **Borderline** — "borderline — path to acceptance: <next step>." Default:
  don't reopen. Disposition `(revise/override)`.

**Override marker** (when overriding doesn't-hold/borderline):
```
<layer> / open · override: gatekeeper rejected — <short headline>

The gatekeeper rejected this reopen as "<basis>", but I'm overriding because
[user's reason]. Others welcome to weigh in.

[user's full reason]

Reference: thread #<N>'s resolution at <date>.
```
Show draft, `(y)es, (n)o, (e)dit?`, post as a reply to the thread root. Note the
two endpoints take **different identifiers** (don't confuse them):
- the REST replies endpoint takes the **root review comment's numeric
  `databaseId`** (the `#discussion_r<N>` value the user passed to reopen) —
  call it `<root-comment-databaseId>`;
- the GraphQL mutation takes the **opaque thread id** (`PRRT_…`) — call it
  `<thread-node-id>` — mapped from that numeric id via the Step 2 query.
```bash
gh api repos/<REPO>/pulls/<PR>/comments/<root-comment-databaseId>/replies -f body="<COMMENT>"
```
**Then actually unresolve** (else the UI + categorizer still see it closed):
```bash
gh api graphql -f query='mutation { unresolveReviewThread(input: {threadId: "<thread-node-id>"}) { thread { isResolved } } }'
```
Verify `isResolved: false`; if not, tell the user the comment posted but the
thread didn't reopen. Delete the draft file on success.

### Start a new thread (only for genuinely new ground)

Reached when the governing-rule check confirms no existing thread covers the
`(layer, aspect)`. Two ways the topic arrives:

**User supplied a topic.** Ask **(prose):** "what's the topic?" The runtime scans
the grounding artifacts + the relevant layer catalog and supplies its
observations (the layer, the named concern) for the user to react to.

**Command proposed it.** From the landing view's "proposed topics" the user
picked (or asked to be shown candidates). The scan reads the artifacts against
the layer catalogs and surfaces candidates as a **multi-select** triage
(`AskUserQuestion`, or numbered text fallback), each line `(confidence) layer —
short headline`, sorted high→low. Two hard rules on the scan:
- **No laundering** (the no-Copilot-aspect rule): if a candidate reduces to a
  code-level defect, drop it — it's Copilot's lane. Never reference Copilot as a
  contrast in a candidate; needing "distinct from Copilot's X" is the tell it's
  laundered.
- **Pre-filter to new ground:** drop any candidate already covered by an existing
  thread (governing rule). The proposed list therefore clusters at the gap
  layers (those with no threads yet).

Multiple checks **queue** (they do not bundle into one comment — one-topic rule):
the runtime walks the checked topics one at a time, opening a separate comment
for each, showing "topic N of M". `(n)o` between topics backs out; not-yet-opened
ones are reported as remaining.

**Topic/headline formula (violation + impact + what's-now, SHORT).** The
headline names: (1) the violation — the concern/flaw; (2) the impact — why it
costs something; (3) what's-now — the current design state being challenged —
compressed to one scannable line. The full prose goes in the body. Example
headline: *"TokenService bundles 5 roles; cleanup can break rotation."* Body
then expands the violation, the impact, and what the doc currently commits to.

**Enforce one-topic-per-comment.** If the supplied topic bundles two+ aspects,
do not draft a multi-topic comment: name each, ask which single one to open now;
the rest are offered as follow-ups.

Draft the top-level comment with first-line tag `<layer> / open — <short
headline>` then the body (and optional `-> ref: <layer> / <status> thread #N`
line if it depends on a settled higher-layer thread — validate the ref is a real
resolved thread at a higher layer). Write to the draft file. Show, `(y)es, (n)o,
(e)dit?`, post:
```bash
gh api repos/<repo>/issues/<PR>/comments -f body="<draft>"
```
Delete the draft file on success; update active-context's `current`.

### Active contexts list (`--list`)

Internal/optional. Read `active-context.json`; for each `recent` entry (≤10)
refetch thread state (Copilot-filtered) and print, marking `current` with `*`,
"last seen" as relative time. Same `<resolved>/<active>` counters as the
statusline (the second number is `open` + `proposing`, per Step 4). If none: "no
active discussions yet — give me a PR to look at."

### Status (`--status`)

Internal/optional. Print the statusline for `current` only. If none: "no active
discussion yet."

## Comment header reference

Tool-emitted comments lead with a **plain tag** — no `review-pr` prefix:

```
<layer> / <status> — <short headline>
```

With a cross-layer reference:
```
design / open — <short headline>
-> ref: problem / resolved thread #N
```

With an override marker:
```
<layer> / open · override: gatekeeper rejected — <short headline>
```

Layers: `problem`, `direction`, `design`, `tradeoff`, `implementation`.
Statuses: `open`, `proposing`, `resolved`, `deferred`. The headline carries
violation + impact + what's-now (short); detail goes in the body. Copilot and
free-form human comments need no tag — inference handles them. (Legacy
`[review-pr / layer / status]` headers are still parsed on read for back-compat,
but never emitted.)

## Worked example

```
$ /goodies-review acme/api#214

Let's look at acme/api#214 — "feat(auth): add refresh-token rotation" — together.

Existing discussion
  1  (high)    direction · @marcus · proposing — rotation-every-use vs sliding-expiry; mobile flakiness weighed?
  2  (medium)  problem   · @priya  · open        — is replay the real threat model, or a hypothetical?
  3  (medium)  tradeoff  · @priya  · open        — 30-day TTL × rotation grows token families without bound

Proposed topics (new ground not yet discussed)
  4  (medium)  design    · new                   — TokenService bundles 5 roles; cleanup can break rotation

  how sure:  (high) checked, holds up · (medium) worth raising, uncertain ·
             (low) a hunch, your call

(3 Copilot code-review threads set aside — that's Copilot's lane.)

Type a number to dig in, or just say what's on your mind:
> 2

  Existing discussion · problem · open                       (how sure: medium)

  @priya: "is replay actually our threat model, or are we solving a hypothetical?"
  (no replies yet)

  What's your position?
> replay is real — we had the token-leak incident in March. (also the 30-day
  TTL makes the family-growth problem worse than the doc admits)

  Two aspects in there. This thread is about the problem, so the reply stays on
  that; the TTL point is @priya's open tradeoff thread (#3) — I'll offer it there
  after we post.

  +- draft reply * problem / open -- replay is real: March token-leak incident -+
  | Replay isn't hypothetical -- the March token-leak incident is a concrete     |
  | instance, and it's the harm the problem statement was missing. Suggest we    |
  | name it explicitly and treat the problem as settled.                         |
  +------------------------------------------------------------------------------+

  Post this reply?   (y)es, (n)o, (e)dit?
> y
  [posted ✓]

  The held TTL point belongs with @priya's open tradeoff thread (#3). Add it
  there?   (y)es, (n)o?
```

This shows the spine: Copilot threads filtered; two-group landing with unified
numbering; conversational entry; the on-topic reply stays scoped while the
off-topic aspect is held and routed to its *existing* thread (governing rule);
plain tags with violation-impact headlines; `(y)es, (n)o, (e)dit?` confirms.

## Error and edge cases

- **Closed/merged PR:** landing view proceeds; posting refuses.
- **Empty PR (no human threads):** all layers `0/0`; landing offers proposed
  topics from the doc scan, or "nothing on the PR yet — want me to surface
  topics from the design doc?"
- **All threads are Copilot's:** existing-discussion group is empty; say "only
  Copilot code-review threads here — those are Copilot's lane. Want me to
  surface higher-layer topics from the design doc?"
- **Draft interrupted (back-out or network failure):** the draft file persists;
  returning to that item resumes it. Deleted on successful post or session end.
- **GraphQL pagination:** always paginate; >100 threads must work.
- **gh auth not configured:** error with a hint to run `gh auth login`.
- **State files missing:** banner-count → create `0`; active-context → no recent
  contexts.
