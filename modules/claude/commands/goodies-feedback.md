---
allowed-tools: Bash, AskUserQuestion
description: Report a bug or suggestion about a goodies-* command as a GitHub issue on the goodies repo
---

# goodies-feedback

Report feedback **about a `goodies-*` command itself** — a bug, a rough edge, a
suggestion — as a GitHub issue on the goodies repo. This is the single,
shared mechanism every goodies command delegates to; commands never re-implement
feedback handling.

This is **not** for feedback about the *code under review* or the *PR* a command
is operating on — it is about the goodies tooling. ("watch pr doesn't actually
trigger Copilot" is feedback; "this PR's design is wrong" is not.)

## When this runs

Two triggers, both routing here (see the always-loaded rule the claude module
installs into `~/.claude/CLAUDE.md`):

1. **Explicit:** the user passes `--feedback [note]` to any `goodies-*` command,
   or invokes `/goodies-feedback` directly.
2. **Natural-language (best-effort):** while (or just after) a `goodies-*`
   command runs, the user expresses dissatisfaction with the command's behavior
   — e.g. "watch pr doesn't work", "this distill output is useless". The runtime
   notices and routes here, building a draft immediately (then confirms before
   posting — see below). This is LLM-judgment, not deterministic: a terse gripe
   may be missed, in which case the user can always type `--feedback`.

In both cases **nothing is posted without an explicit confirmation** — feedback
is outward-facing (it creates/comments on a public issue).

## Step 1: Identify the target command and the note

- **Target command** (`<cmd>`): the `goodies-*` command the feedback is about.
  If invoked via another command's `--feedback`, that command is the target. If
  invoked directly with no obvious target, ask: "which goodies command is this
  about? (goodies-review / goodies-watch / goodies-distill / goodies-bkm / …)".
- **Note** (`<note>`): the user's own words — the `--feedback` argument, or the
  dissatisfaction phrase that triggered this. If empty, ask: "what's the
  feedback? (one or two sentences)".

## Step 2: Gather required context

These are captured automatically and included in the issue so a maintainer knows
*what* and *which version*:

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# The goodies repo SHA — which version of the command the user is running.
# Resolve through the command's own symlink so it's the installed checkout.
# Use readlink + dirname (no python3 dependency): the command file lives at
# <goodies>/modules/claude/commands/goodies-feedback.md, so the repo root is
# four directories up from the symlink target. The installer symlinks to an
# ABSOLUTE path, so plain `readlink` (one hop, portable to macOS where
# `readlink -f` doesn't exist) already yields that absolute target; fall back to
# the literal link path only if it isn't a symlink.
CMD_LINK=~/.claude/commands/goodies-feedback.md
CMD_REAL=$(readlink "$CMD_LINK" 2>/dev/null || echo "$CMD_LINK")
GOODIES_DIR=$(dirname "$(dirname "$(dirname "$(dirname "$CMD_REAL")")")")
GOODIES_SHA=$(git -C "$GOODIES_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
```
(Plain `readlink` works on both Linux and macOS because the installed link
points at an absolute path — one hop resolves to the real checkout. The
fallback (`CMD_REAL` = the link path) only applies if the command isn't a
symlink at all, in which case the SHA is best-effort and may be `unknown`.)

Context block to embed in the issue body:
- **command:** `<cmd>`
- **goodies version:** `<GOODIES_SHA>`
- **what the user was doing:** the invocation (args/subject) and what the command
  was doing when the feedback was raised — one or two lines, no transcript dump.
- **the user's words:** `<note>` verbatim.

Keep it lean. Do **not** paste full conversation transcripts, tokens, or repo
contents — the user reviews the draft and can trim anything.

## Step 3: Show the draft, allow edits

Compose the draft issue:

```
title: [<cmd>] <short summary of the feedback>

**Command:** <cmd>   **goodies @** <GOODIES_SHA>

**Feedback**
<note>

**Context**
<what the user was doing — 1-2 lines>

<!-- filed via /goodies-feedback -->
```

Show it and ask **`(y)es, (n)o, (e)dit?`**:
- `y` → proceed to dedup + post (Step 4);
- `n` → don't file; stop;
- `e` → let the user revise the title/body, then re-present.

The optional user edits in Step 3 are the "optional user edits" layer on top of
the required auto-context.

## Step 4: Dedup — vote + comment, or create

Search existing open feedback issues for the same command before creating a new
one, so similar reports don't pile up:

```bash
REPO=TianyouLi/goodies
# Open issues labelled feedback for this command. cmd:<name> label scopes it.
gh issue list --repo "$REPO" --state open --label feedback --label "cmd:<cmd>" \
  --json number,title,body --limit 100
```

If that returns nothing (label may not exist yet on older setups), fall back to
a broader search:
```bash
gh issue list --repo "$REPO" --state open --label feedback --search "<cmd>" \
  --json number,title,body --limit 100
```

**Judge similarity** (LLM): does an existing issue describe substantially the
same problem/suggestion? Render a confidence note for the match.

- **Similar issue #N found** → do NOT create a duplicate. Instead register a
  **vote** (a 👍 reaction) and add the user's context as a **comment**:
  ```bash
  # Vote: 👍 reaction on the issue (the "+1" signal).
  gh api repos/$REPO/issues/<N>/reactions -f content="+1" \
    -H "Accept: application/vnd.github.squirrel-girl-preview+json"
  # Comment: this user's note + context, so the report accrues detail.
  gh api repos/$REPO/issues/<N>/comments -f body="<comment body: note + context>"
  ```
  Tell the user: "this matches existing feedback #N — added your 👍 and a comment
  rather than opening a duplicate: <issue url>."

- **No similar issue** → create a new one, ensuring the labels exist first
  (label creation is idempotent; ignore "already exists" errors):
  ```bash
  gh label create feedback --repo "$REPO" --color FBCA04 \
    --description "Feedback about a goodies command" 2>/dev/null || true
  gh label create "cmd:<cmd>" --repo "$REPO" --color C5DEF5 \
    --description "Feedback scoped to <cmd>" 2>/dev/null || true
  gh issue create --repo "$REPO" --title "[<cmd>] <summary>" \
    --label feedback --label "cmd:<cmd>" --body "<draft body>"
  ```
  Report the new issue URL.

## Step 5: Confirm outcome

Print what happened (created #N / voted+commented on #N) with the URL. If the
feedback was raised mid-run of another `goodies-*` command, return control to
that command so the user's original task continues uninterrupted.

## Notes / edge cases

- **No `gh` auth:** report the draft to the user and say "couldn't reach GitHub
  (run `gh auth login`); here's the feedback I would have filed" so nothing is
  lost.
- **Not in / can't find the goodies checkout:** still file the issue; record
  `goodies version: unknown`.
- **Private/declined:** if the user answers `n` at the confirm, nothing is
  posted — feedback is never filed silently.
- **Scope guard:** if the "feedback" is actually about the PR/code under review
  rather than the command, say so and suggest the right channel
  (e.g. `/goodies-review` for PR discussion) instead of filing a tooling issue.
