# goodies-review — design

A slash command for human-expert collaboration on PR review. Not a code-review
bot — code-level findings are Copilot's job. This tool helps experts discuss
whether the *problem* and *approach* are right, before debating code.

## Problem

Multi-PR review at scale has three failure modes the existing tooling doesn't
address:

1. **Code reviewers cargo-cult the layer.** Reviewers jump to implementation
   nits before settling whether the problem is in scope, the direction is
   sound, or the design choices are right. Resolving an implementation thread
   doesn't mean the larger architectural questions are settled.

2. **Resolved threads get reopened by fiat.** A new participant arrives,
   restates a preference the original thread already heard, and the discussion
   ping-pongs without convergence. There's no enforced bar for "what makes
   reopening a resolved thread justified."

3. **Multi-PR juggling loses thread state.** A reviewer paged into one PR
   often comes back later and can't remember what was settled, what's open,
   and which categories of discussion never started. PR comment streams are
   chronological, not categorized.

`goodies-review` addresses these by structuring the discourse: hierarchical
review layers, a small gatekeeper for thread reopens, persistent context
across invocations, and a loose comment-format that incrementally adopts.

### Non-goals

- **Code review.** Copilot, code-reviewer agents, and other static-analysis
  tools cover the implementation layer. This tool defers to them.
- **Authority enforcement.** The gatekeeper evaluates the *argument*, not the
  *arguer*. Project managers, authors, and reviewers all face the same bar.
- **Merge automation.** This tool never merges, never requests reviews,
  never approves or requests-changes, never modifies the PR's
  *review-decision* state (approval / changes-requested / dismissal).
  What the tool *does* do, with confirmation every time: post comments,
  resolve threads when a `resolved`-status reply is posted, and
  unresolve threads when `--reopen` is used. Thread resolve/unresolve
  is a *conversation-mechanics* operation (it's how GitHub records
  "this discussion is settled"); it is not a review-decision and is
  legitimately part of the tool's job. Without it, the GitHub UI's
  resolved-state would diverge from the conversation's actual state,
  showing stale resolution markers.
- **Automatic posting.** Drafts are always shown to the user for confirmation
  before any `gh api` call lands a comment, resolves a thread, or
  unresolves a thread.

## Design

### The 5-layer hierarchy

Review proceeds in layers, lowest-numbered first:

| # | Layer | The question this layer answers |
|---|-------|--------------------------------|
| 1 | `problem` | Is the stated problem meaningful, general, in-scope for the project? |
| 2 | `direction` | Given the problem, is the chosen direction sound? Are alternatives ruled out for the right reasons? |
| 3 | `design` | Given the direction, are the architectural choices (carve, contracts, extension points) right? |
| 4 | `tradeoff` | Are the rejected alternatives properly considered? Are the costs being paid the right ones? |
| 5 | `implementation` | Code-level concerns. Largely deferred to Copilot and other code-review tools. |

The hierarchy is enforced *softly*: when a user engages at layer N while a
lower-numbered layer has open threads, the tool warns ("layer 1 has 1 open
thread; engaging at layer 3 anyway"), but does not block. The expert decides;
the tool reminds.

### The 4-status thread vocabulary

| Status | Meaning |
|--------|---------|
| `open` | The question is unsettled; needs argument or evidence. |
| `proposing` | A participant is offering a resolution; awaiting agreement or counter-argument. |
| `resolved` | The thread is settled; no further discussion absent strong reason (see gatekeeper). |
| `deferred` | The question matters but is out of scope for this PR; tracked elsewhere. |

`proposing` is what differentiates "I'm still asking" from "I think this
resolves it." Without it, threads never converge — every reply is treated as
either an attack or a deflection. With it, a participant can say "I'm
proposing X resolves this" and others can say "I agree" (move to `resolved`)
or "I disagree because Y" (back to `open` with a counter).

### Loose comment format (optional first-line tag)

Tool-emitted comments lead with a single plain-language tag on the first line:

```
<layer> / <status> — <short headline>
```

The tag is markdown-readable, copy-paste-stable, and machine-parseable. Slots:

- `<layer>` — one of the 5 hierarchy values.
- `<status>` — one of the 4 status values (the first token after `/`, before
  any ` · ` marker — see the override variant below).
- `<short headline>` — a plain summary in the violation + impact + what's-now
  shape; carries no codes (see "Interactive flow → internal vs. user-facing").

The meaningless `review-pr` provenance prefix used by earlier versions is
**dropped** — the tool no longer emits it. For back-compat the parser still
recognizes the legacy `[review-pr / <layer> / <status>]` form on read, but never
emits it.

**Override variant.** A reopen posted over a gatekeeper rejection carries an
override marker after the status, set off by ` · `:

```
<layer> / open · override: gatekeeper rejected — <short headline>
```

A tag parser must take the status as the first token after `/` and treat
anything after a ` · ` as an annotation, not part of the status — otherwise
`open · override: …` looks like an invalid status and the thread fails to
categorize/reopen.

When `goodies-review` reads a PR's comment threads:

1. **Parse the header if present** — author's claim is the primary signal.
2. **Fall back to LLM-inference for headerless comments** — content reveals
   layer + likely status. Less reliable, but workable for comments produced
   without the tool.
3. **Distinguish the two sources in output** — `[via header]` vs `[inferred]`,
   so the human can correct misclassifications.
4. **Flag header-vs-content mismatches** — if a header says `problem` but the
   content reads as implementation, surface the inconsistency rather than
   trusting the wrong metadata.

Atomic comments (one layer per comment) for v1 — enforced (see "Interactive
flow → governing rule"). A comment that genuinely spans two layers is split.
Multi-layer tags (`design,problem / open — <short headline>`) are a v2 extension
if the constraint pinches in practice.

#### Cross-layer references

When a lower-layer comment depends on a settled higher-layer thread, a reference
line follows the tag:

```
design / open — bracket-predicate grammar exceeds the v1 commitment
-> ref: problem / resolved thread #123

The Problem layer settled on "any workload-supplied predicate." This Design
choice of bracket-syntax predicates assumes a richer grammar than the v1
commitment...
```

This anchors the new thread to the constraint that should bound it. The
gatekeeper uses these references to detect when a later thread implicitly
challenges a settled higher-layer thread (which would require the reopen
flow, not a new thread at the lower layer).

### The reopen gatekeeper

A user attempting to reopen a resolved thread provides a *reason*. The
LLM evaluates the reason against the resolved thread's content and the
project's design context, and renders a verdict.

#### Three buckets that meet the bar

A reopen reason is "strong enough" if it presents new information the prior
thread couldn't have considered:

1. **New evidence the prior thread couldn't have considered.** A real instance
   that breaks the resolution; a subsequent commit that contradicts a stated
   assumption; a downstream consequence visible only after the resolution was
   applied; a new linked design doc, ticket, or external discussion.

2. **Internal inconsistency exposed.** The resolution conflicts with another
   part of the project's stated contracts (CLAUDE.md, design docs, another
   resolved thread). The contracts say X but the resolution implies Y.

3. **Wrong layer of resolution.** The thread was resolved at the
   implementation layer when the issue actually lives at the design or
   problem layer. Resolution at the wrong level doesn't settle the right
   question.

#### What does not meet the bar

- **Restated preferences.** "I still don't like this" — if the prior thread
  heard this argument and resolved against it, repetition isn't new.
- **Authority appeals.** "The PM says we should reopen" — the gatekeeper
  evaluates the *argument*, not the *arguer*. Surface the request back:
  "what's the architectural argument?"
- **Aesthetic re-litigation.** "It would be cleaner if..." needs a concrete
  failure mode, not a feeling.
- **Speculation without instances.** "What if some future workload needs..."
  needs at minimum a plausible instance, not pure hypothetical.

#### Verdicts

The gatekeeper renders one of three:

1. **Reason holds.** Drafts the reopen comment tagged
   `<layer> / open — <short headline>`, includes the reason, references the prior
   thread's resolution. Awaits confirmation before posting.

2. **Reason doesn't yet hold.** Specific feedback: "your reason restates the
   preference X that thread #123's resolution addressed at line Y; for a
   reopen you'd need to show [concrete missing element]." User can revise and
   retry.

3. **Borderline.** Default disposition: don't reopen, but state the path to
   acceptance clearly. The principle is discipline — a borderline argument
   shouldn't get the same status as a strong one.

#### Override and record

The user can override any verdict (this is a collaboration tool, not a
permission system). When they do, the posted comment carries an override
marker visible to all participants:

```
design / open · override: gatekeeper rejected — <short headline>

The gatekeeper rejected this reopen as "restated preference," but I'm
overriding because [reason]. Other participants are welcome to weigh in on
whether the override is justified.
```

This preserves the architectural-not-social property while respecting human
agency. Other participants see the gatekeeper's verdict, the override, and
the user's stated reason — they can support or challenge.

#### "Reopen" vs "new thread"

If the user's reason isn't actually about the resolved question but adjacent,
the gatekeeper suggests `--new-thread` instead. Same override-and-record
pattern. This prevents the gatekeeper from becoming a wedge for sneaking new
discussions into closed threads.

#### Coverage feedback loop

The gatekeeper's bucket criteria are themselves iterable. If reviewers
report that valid reopen reasons are being rejected (or weak ones accepted),
the criteria can be refined in this design doc and the command. Per the
"command shapes reviewer behavior" property, the rules are not external
policy — they're the tool's own contract.

### Statusline (ASCII boxed)

Every `goodies-review` invocation prints a compact context strip identifying
which PR and thread the user is engaging on:

```
+- optibot#125 -- feat: B9 optimization loop design ----------------------+
| design layer * thread #3411232637                                        |
| problem 1/0 * direction 2/0 * design 3/8 * tradeoff 0/0 * impl 13/0      |
+--------------------------------------------------------------------------+
```

Layout:
- Title row: `<repo>#<PR> -- <PR title>`
- Context row: `<current layer> * thread #<id>`
- Counter row: `<layer> <resolved>/<open>` for all 5 layers (always shown,
  including `0/0` so empty layers are visible).

ASCII characters only (`+ - | *`). No Unicode. Renders consistently across
terminals and Claude Code clients.

### Multi-PR `--list` view

For an expert juggling multiple PRs, `--list` shows all active contexts:

```
+- goodies-review * active contexts -------------------------------------+
|                                                                         |
| * optibot#125 * feat: B9 optimization loop design       [last: 2m ago] |
|   problem 1/0 * direction 2/0 * design 3/8 * tradeoff 0/0 * impl 13/0  |
|                                                                         |
|   goodies#42 * feat: review-pr command                  [last: 1h ago] |
|   problem 0/1 * direction 0/0 * design 0/2 * tradeoff 0/0 * impl 0/0   |
|                                                                         |
+- * = current * switch via /goodies-review <repo>#<pr> -----------------+
```

`*` marks the current PR; switching is one invocation away.

### Persistent context file

`~/.cache/goodies-review/active-context.json` tracks the user's current focus
and recent PRs. On a no-args invocation, the tool resumes the last-active
context (with a banner saying so). The `--list` mode reads this file.

Schema:
```json
{
  "current": {
    "repo": "intel-sandbox/os.linux.pnp.optibot",
    "pr": 125,
    "thread": 3411232637,
    "layer": "design"
  },
  "recent": [
    {"repo": "intel-sandbox/os.linux.pnp.optibot", "pr": 125, "last_seen": "..."},
    {"repo": "TianyouLi/goodies", "pr": 35, "last_seen": "..."}
  ]
}
```

### First-time banner

The tool's nature is non-obvious. First 3 invocations show a banner shouting
the principle:

```
*** goodies-review is for human-expert collaboration on PR direction,    ***
*** design, and trade-offs -- NOT code review. Code-level findings are   ***
*** Copilot's job. Settle higher layers first.                           ***
*** Layers: problem -> direction -> design -> tradeoff -> implementation ***
```

After 3 invocations the banner suppresses. `--show-purpose` forces it to
re-display (useful for sharing with collaborators or self-reminder).

State file: `~/.cache/goodies-review/banner-count`. Single integer.

### Grounding

The tool fetches the *target repo's* CLAUDE.md and any linked design docs in
the PR body for review grounding. Goodies's own CLAUDE.md is irrelevant for a
PR being reviewed in another repo — only the target's grounds the review.

When the PR adds files under `docs/design/`, those are themselves treated as
design contracts (the PR is introducing the doc; the gatekeeper grounds
against the doc + project's existing patterns).

### Invocation and internal routing targets

The default interface is **conversational, not a mode picker** (see "Interactive
flow" below). The normal invocation opens the landing view; the user types a
number or talks, and the runtime routes to one of the sub-flows. The mode flags
still exist as *internal/optional shortcuts* into the same sub-flows — they are
not the primary interface and are never surfaced to the user as something to
choose.

| Invocation | Behavior |
|------------|----------|
| `/goodies-review <PR>` | **Default — conversational landing view:** survey existing discussion (Copilot threads excluded) + proposed topics as two groups; invite a numbered pick or free prose; route from there. |
| `/goodies-review` (no args) | Resume the last-active context and open its landing view. If none: "no active discussion yet — give me a PR to look at." |
| `/goodies-review <PR> --engage [--layer <X>]` | Internal shortcut: jump straight to continuing open threads at a layer. |
| `/goodies-review <PR> --reopen <thread-id>` | Internal shortcut: gatekeeper-mediated reopen of a resolved thread. |
| `/goodies-review <PR> --new-thread [--layer <X>]` | Internal shortcut: start a new thread (with topic, or propose topics). Subject to the governing rule (no duplicate of an existing thread). |
| `/goodies-review --list` | Show all active contexts across PRs. |
| `/goodies-review --status` | Show the statusline for the current context. |

`<PR>` accepts a bare number (current repo), a qualified form (`optibot#125` or
`<owner>/<repo>#<num>`), or a full PR URL.

### Interactive flow

One interaction cycle underlies every flow:

> **The command supplies, the user reviews and provides input, that input forms
> the comment/reply, and the user confirms before anything posts.** The command
> never authors-and-posts autonomously — it proposes, the human shapes and
> approves.

**Internal vs. user-facing (the boundary).** The runtime reasons with internal
codes — layer catalog entries (`DS5`, `AP2`, …), `[n]` citations, the mode
targets — but translates everything to plain language before it reaches the
screen. Catalog entries are surfaced by their meaningful title, never the code;
the design doc and `layers/*.md` keep the codes (they are the internal scheme).
Nothing the user sees contains a code.

**Conversational, survey-first entry.** The tool is not a mode picker. A session
opens by surveying what's already on the PR and inviting discussion. The survey
**excludes Copilot-authored threads** (code review is Copilot's lane, not this
tool's). The landing view shows two disjoint groups — *existing discussion* and
*proposed topics* (doc-scan candidates) — each sorted high→low by confidence,
with unified continuous numbering and one tight line per item (detail on pick).
The user types a number or talks freely; the runtime infers the route (continue
/ reopen / new topic) and states it in plain words before drafting.

**Governing rule: no new thread unless really new.** Before any new top-level
thread, the runtime checks every existing thread (open and resolved) for a
matching `(layer, aspect)` and prefers continuing/reopening it over a duplicate.
Proposed topics are pre-filtered to genuinely new ground, so the two landing
groups are disjoint by construction. The companion **one-topic-per-comment**
rule is also enforced: the runtime refuses to draft a multi-topic comment
(splits it) and refuses to fold an off-topic aspect into a reply (holds it and
routes it per the governing rule). An *aspect* is *(layer) + (named concern)*,
grounded in a catalog entry internally — and explicitly **not** a code-level
defect relabeled (those stay Copilot's).

**Navigation: levels, `(n)o` is back.** The session is a level hierarchy
(landing → item detail → draft). `(n)o` backs up one level rather than aborting;
there is no `quit`. Confirms render as `(y)es, (n)o, (e)dit?`. Prose prompts back
out on empty input. Unrecognized token input re-prompts once, then defaults to
the non-mutating choice — a typo never posts or resolves.

**Drafts live on disk.** Because the runtime is the LLM, an in-context draft
would bloat a long multi-thread session. Working drafts are externalized to
`~/.cache/goodies-review/draft-*.txt`: written on create/edit, persisted across
a back-out so edits survive, deleted on successful post or session end. The draft
file is the single source of truth (also covering the network-failure rescue);
context holds a draft only while it is on screen.

**Comment headers carry meaning, not jargon.** Posted comments lead with a plain
tag `<layer> / <status> — <short headline>`, where the headline states
*violation + impact + what's-now* compressed to one line. The meaningless
`review-pr` prefix is dropped (legacy headers are still parsed on read).

**Widget vs. text (why hybrid).** `AskUserQuestion` is used only for selection
from a fixed set — chiefly the multi-select topic triage and optional
disambiguation — never as the front door (the front door is the conversational
landing view). Free-form input (positions, reasons, topics) and the simple
confirms stay text. The tool is additive and falls back to a numbered text
prompt when unavailable, which is why `AskUserQuestion` joins `Bash, Read, Write`
in `allowed-tools`.

## Trade-offs

**Loose format vs strict format.** A required header would make
categorization trivial but fragments the discussion: people who use the tool
produce structured comments, people who don't produce free-form, and the tool
has to handle both anyway. Loose format with LLM-inference fallback means
incremental adoption works.

**Soft-warn vs hard-block on layer discipline.** Hard-blocking would enforce
the hierarchy mechanically but fight users who genuinely have reason to
discuss a higher layer first. Warning preserves the principle while
respecting expertise.

**Widgets vs. text prompts (hybrid).** Pure-text prompts work everywhere and
need no extra tool, but force the user to recall flags and type numbers to pick
from a list. Pure-widget would be slick but can't carry free-form prose
(positions, reopen reasons) — the bulk of real input. The hybrid uses
`AskUserQuestion` only for the two genuinely enumerable choices (entry router,
aspect triage) and text for everything else, with a numbered-list text fallback
when the tool is absent. This buys the checkbox/menu ergonomics where they fit
without losing prose or headless operation.

**Grand rule enforced vs advisory.** Unlike layer discipline (soft-warn above),
the one-topic-per-comment rule is hard-enforced: the value of the whole
categorizer + statusline model depends on each comment carrying exactly one
`(layer, aspect)`, so a bundled comment corrupts every downstream view. The
refusal is still non-punitive — the user picks one aspect to open now and the
rest are offered as follow-up threads.

**Gatekeeper override-and-record vs no override.** No override would make
the rule decorative once disagreed with. Override-with-record keeps the
gatekeeper's voice in the discussion (others see the verdict was rejected)
without making the tool a tyrant.

**Per-PR state vs single global state.** Per-PR state would scale to many
PRs without conflict. Single global state is simpler. With multi-PR
juggling explicitly in scope, the persistent context file holds *recent*
PRs, not just *current* — getting the per-PR-state benefit cheaply.

**Coverage feedback loop vs frozen rules.** Frozen rules would be more
predictable. Iterable rules acknowledge the gatekeeper might miscategorize
in practice; the user can update the bucket criteria in this doc + the
command's prompt as data accumulates.

**Always-show-all-5-layers vs skip-empty-layers.** Showing `0/0` for empty
layers is informative — it surfaces "trade-offs were never discussed" as a
visible fact, which is itself a hierarchy-discipline signal. The cost is
slight visual clutter; the benefit is making absent discussion visible.

**ASCII vs Unicode rendering.** Unicode box-drawing characters render
beautifully in modern terminals but garble in minimal SSH sessions or
non-Unicode locales. ASCII is universal. The aesthetic loss is small.

## Deferred to follow-up PRs

Several capabilities have been designed but are deliberately out of this
PR's scope, sequenced afterward as their own PRs (one PR, one intent). The
list is here so a wider-audience reviewer of just this doc sees the
architectural roadmap, not just the framework's first commit:

- **Per-layer pattern + anti-pattern guidance** — five separate PRs, one
  per layer (`problem`, `direction`, `design`, `tradeoff`, `implementation`).
  Each adds a `goodies-review/layers/<layer>.md` file with 3-5 patterns
  and 3-4 anti-patterns following a uniform skeleton. Loaded on-demand by
  the command when `--engage --layer X` is invoked. Sequenced one at a
  time because each layer's patterns deserve their own review cycle —
  bundling produces shallow review.
- **LLM-side anti-pattern detection during inference** — the categorizer
  (Step 3) and header-mismatch check (Step 1.5) extended to flag possible
  anti-patterns with confidence labels, plus an optional 4th gatekeeper
  bucket for "anti-pattern in resolution" reopen reasons. Depends on the
  five layer files existing.
- **`--feedback` flag on every goodies-* command** — drafts a GitHub
  issue capturing user feedback, with substance/scope gating, semantic
  dedupe + weight-counting, and a frustration-aware elicitation guide for
  emotional/general inputs. Independent of the patterns work; can
  interleave.

These follow-ups extend the same infrastructure this PR establishes; per
the project's stacked-PR rule, they wait for this PR to merge first.

## Verification

- `tests/modules/claude.bats` — bats assertion that the command file
  installs (consistent with existing claude-module tests).
- Manual end-to-end on a real PR: invoke `--list` (empty), invoke against
  optibot#125 to see the summary view, optionally invoke `--engage` to
  walk an open thread.
- The gatekeeper's bucket criteria are validated against three test
  scenarios documented inline in the command's worked-example section:
  a clear "holds" reason (new evidence), a clear "doesn't hold" reason
  (restated preference), and a borderline reason.

## Linked context

- `modules/claude/commands/goodies-watch.md` — sibling command for Copilot
  re-review polling. Different concern (reviewer-bot watching) but shares
  the slash-command + post-via-`gh api` pattern.
- `modules/claude/commands/goodies-distill.md` — sibling command pattern.
- The CLAUDE.md "Copilot Review Workflow" section — describes how Copilot
  review and human review compose. `goodies-review` is the human side.
