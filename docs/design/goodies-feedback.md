# goodies-feedback — design

## Problem

The goodies commands (`goodies-review`, `goodies-watch`, `goodies-distill`,
`goodies-bkm`, …) are used daily, but there was no in-flow way to report that a
command itself is wrong or rough — a bug, a confusing prompt, a missing case.
Friction noticed mid-task ("watch pr doesn't actually trigger Copilot") was lost
unless the user stopped, switched context, and filed an issue by hand.

Two further constraints make a naive "add a `--feedback` section to each command"
approach inadequate:

1. **It must be available everywhere, automatically.** When a *new* goodies
   command is added later, feedback reporting should work for it with **nothing
   to remember** — no per-command wiring that someone forgets to copy.
2. **It must not pile up duplicates.** Repeated reports of the same rough edge
   should accrue signal on one issue (a vote + a comment), not spawn N issues.

## Design

### One shared mechanism, namespace-triggered

- **`/goodies-feedback`** (a single command spec) is the only place the
  feedback mechanics live: gather context → draft → de-dup → vote/comment or
  create → confirm-and-post. No command re-implements any of this.
- **An always-loaded trigger**, installed into the user-global
  `~/.claude/CLAUDE.md` by the claude module, routes to `/goodies-feedback`
  whenever a `goodies-*` command is involved. It is keyed off the **`goodies-*`
  namespace, not a fixed command list**, so a command added in the future is
  covered the moment it exists.
- **The installer is the enforcement point.** `modules/claude/install.sh`
  symlinks every `commands/goodies-*.md` by glob (not a hand-maintained list),
  so adding a command file is all it takes for that command — and its feedback
  availability — to install.

This is why feedback is "automatic for new commands": the trigger matches a
namespace, and the installer matches a glob. Neither references a specific
command.

### Triggers

1. **Explicit `--feedback [note]`** on any `goodies-*` command, or
   `/goodies-feedback` directly — deterministic.
2. **Natural-language dissatisfaction** during/after a `goodies-*` run — the
   runtime notices and auto-drafts, then confirms before posting. This is
   **LLM-judgment, best-effort**: a terse gripe may be missed (the explicit flag
   is always available), and a passing complaint shouldn't be filed without the
   user's confirm. The confirm step is what makes the eager interpretation safe.

### Context captured

Required (auto): the target command, the goodies repo commit SHA (which version
the user runs), the user's verbatim words, and a one-to-two-line note on what the
command was doing. Optional: the user's edits to the draft before posting. Kept
deliberately lean — no transcript dumps, tokens, or repo contents; the user sees
and can trim the draft.

### De-duplication: vote + comment

Before creating, search open issues labelled `feedback` + `cmd:<name>` and
LLM-judge similarity:
- **match** → add a 👍 reaction (the vote) and a comment with this user's
  context — the report gains weight and detail without a duplicate;
- **no match** → create a new labelled issue (`feedback`, `cmd:<name>`), title
  `[<cmd>] <summary>`.

Labels are created idempotently on first use.

### Confirm before posting

Feedback is outward-facing (a public issue / comment). Nothing is ever posted
without an explicit `(y)es` at the draft confirm — `(n)o` discards, `(e)dit`
revises. Consistent with the goodies-review interactive contract.

## Trade-offs

**Shared command + namespace trigger vs. per-command `--feedback` sections.**
Per-command sections would be self-contained but violate constraint #1 — a new
command needs the section copied in, and copies drift. The namespace trigger +
glob installer make availability automatic at the cost of the trigger being a
prose rule in CLAUDE.md (LLM-followed) rather than code.

**CLAUDE.md injection vs. symlink.** The other goodies artifacts are symlinked,
but `~/.claude/CLAUDE.md` may be co-owned by the user (their own global
instructions), so it can't be a symlink. The installer instead injects an
idempotent marked block (`<!-- BEGIN/END goodies-feedback -->`), replaced in
place on re-install and preserving the user's surrounding content.

**NL trigger reliability.** Detecting dissatisfaction is not deterministic.
Accepted: the explicit `--feedback` flag is the reliable path; the NL trigger is
a convenience layer, and the confirm step bounds its downside (it can't file
something the user didn't approve).

**settings.json was not viable** for the trigger: it is Claude Code config
(model, plugins, statusline), with no field for an always-loaded behavioral
rule — hence CLAUDE.md.

## Verification

- BATS (`tests/modules/claude.bats`): installer symlinks every `goodies-*.md`
  by glob; the CLAUDE.md trigger block installs, is idempotent across re-installs,
  and preserves pre-existing content; `goodies-feedback.md` carries its required
  anchors (gh issue create, reactions vote, `cmd:` label, confirm prompt).
- Manual: `/goodies-feedback` against a real goodies command files a labelled
  issue, and a near-duplicate report votes + comments on the existing one.

## Linked context

- Command spec: `modules/claude/commands/goodies-feedback.md`
- Trigger install: `modules/claude/install.sh` (`install_feedback_trigger`)
