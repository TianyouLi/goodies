# Layer 1: problem

**The question this layer answers:** Is the stated problem meaningful, general,
in-scope for the project, and not already solved (new vs. legacy, prior art
consulted)?

> Sources named inline below are listed in full in
> [references.md](../references.md#problem-layer).

## Patterns (what good looks like)

**P1. The problem is observable from the outside.**
The problem statement describes a failure mode or absence that someone can
witness without the author's help. A reviewer can point to a concrete instance
— a conversation that cycled, a bug that escaped, a task that couldn't be
completed — without needing the PR body to explain why it qualifies. Reviewers
should be able to say "yes, I've seen that" before reading the solution.
Symptom of this pattern being present: the commit message or issue body links
to or names a real incident, ticket, or observable artifact. Test: can a
reviewer witness the failure mode without the author explaining why it counts?

**P2. The problem is scoped to a class, not an instance.**
"PR #42 was reviewed at the wrong layer" names an instance. "Reviewers
consistently jump to implementation before settling architecture" names the
class the PR is solving. Class-level problems justify shared infrastructure;
instance-level problems justify one-off fixes. Per requirements engineering
practice (IEEE 830 / Wiegers [1]), a well-formed problem statement is traceable
to a stakeholder need that recurs, not a one-time event. Symptom of this pattern
being present: the statement names the recurring stakeholder need behind the
instance, not just the instance. Test: would this problem exist if the cited
incident had never happened?

**P3. The problem names who is harmed, in what situation, and with what
consequence.**
A problem without a named harm is a work item without a valued outcome —
pure waste by Reinertsen's "The Principles of Product Development Flow" [2] definition.
The JTBD format [3] makes this concrete: situation + motivation + desired outcome.
"Developers who review multi-file refactors lose architectural context midway
through a thread and re-raise the same questions across multiple sessions" is
a well-formed harm. "Review quality could be better" is not. Symptom of this
pattern being present: the statement names a specific actor, the situation that
triggers the harm, and the cost they bear — not a generic quality aspiration.
Test: can a new team member read the problem statement and understand why the
current state is costing someone something?

**P4. The problem statement survives the simplest alternative.**
Before accepting a problem as stated, ask: would a checklist, a label, a
one-paragraph team norm, or a five-minute conversation already solve this? If
yes, the problem statement must either explain why the simpler approach doesn't
hold, or be narrowed to the residual that simpler approaches can't cover. This
corresponds to the "appetite" framing in Shape Up (Basecamp) [4]: a problem worth
building infrastructure for must be worth more than the cost of the simplest
possible response. A problem that dissolves under the first alternative was
never well-formed. Symptom of this pattern being present: the statement names
the simplest plausible response and explains the residual it fails to cover.
Test: has the author shown why a checklist, a label, or a team norm would not
already resolve the harm?

**P5. Non-goals are explicit and show the boundary was considered.**
A tight non-goal list demonstrates that adjacent problems were evaluated and
consciously deferred rather than missed. It also protects the solution from
scope creep: once the boundary is named, a reviewer can flag when a proposed
solution crosses it. Per specification-by-example practice (BDD / Cucumber) [5],
a problem without a stated boundary tends to accumulate undeclared assumptions
that surface only during implementation. Symptom of this pattern being present: the PR or
design doc contains a "non-goals" or "out of scope" section with at least one
entry that a casual reader might have assumed was in scope. Test: does the
problem statement name at least one adjacent problem it consciously declines
to solve?

**P6. The problem statement addresses system structure, not just symptoms.**
Meadows ("Thinking in Systems") [6] shows that solutions targeting symptoms while
ignoring underlying structure produce new problems at the same rate they solve
old ones. A problem statement that names only the surface event — "tests are
slow" — without pointing at the structural cause — "the test suite serializes
work that is embarrassingly parallel" — will produce fixes that don't hold.
A strong problem layer identifies the constraint (Goldratt, "The Goal") [7]:
the one bottleneck whose removal produces the largest downstream improvement.
Symptom of this pattern being present: the statement points past the surface
event to the structural cause that keeps producing it. Test: does the problem
statement name a structural cause, or only a recurring symptom?

**P7. The problem is general enough to justify the audience it will reach.**
Per Moore's "Crossing the Chasm," [8] a problem scoped only to early adopters may
not justify infrastructure that ships to the mainstream. If the PR introduces
a shared mechanism, the problem must be demonstrated to affect more than the
author's immediate workflow. Symptom of this pattern being present: the problem statement shows evidence of
recurrence across other people, repos, or teams — not just the author's own
experience. Test: if the author left the project
tomorrow, would this problem still exist and still be worth solving?

**P8. The problem is demonstrable via at least one concrete example.**
Specification by example (BDD practice) [5] requires that any abstract claim be
grounded in at least one instance that can be run or replayed. In a PR context
this means the problem statement either links to a concrete case — a review
thread, a failing test, a reported incident — or provides a minimal constructed
example that any reviewer can follow. Problems with no concrete instance are
unfalsifiable: there is no way to verify that a proposed solution actually
addresses them. Symptom of this pattern being present: the statement links to a
runnable case, a review thread, or a minimal reproduction. Test: can a reviewer
point at one concrete instance of the problem without the author's narration?

**P9. The problem statement includes an appetite — how much solving it is worth.**
Shape Up's appetite framing [4] requires not just naming the harm but bounding how
much effort is justified to address it. A problem worth a one-week fix is
different from a problem worth a quarter-long investment, even if the harm
description is identical. Without an appetite, every solution that addresses
the harm looks equally valid regardless of cost. Symptom of this pattern being
present: the problem statement or PR body contains an explicit signal of scale
— "this affects every PR review cycle" vs. "this arises once a month" — that
a reader can use to sanity-check the proposed solution's scope before evaluating
it. Test: can a reviewer use the problem statement alone to rule out solutions
that are clearly over-engineered or clearly too small?

**P10. The problem distinguishes the whole-product gap from the feature gap.**
Moore's "Whole Product" model [8] observes that most real adoption failures are
ecosystem gaps — missing integrations, missing conventions, missing tooling
around a feature — not the feature itself. A problem statement that names only
a missing feature ("no structured review layers") may misdiagnose an ecosystem
gap ("existing review tooling doesn't surface architectural decisions early
enough, so teams build conventions that erode under contributor turnover"). The
whole-product framing asks: what surrounding ecosystem conditions are required
for this solution to actually stick? A problem statement that ignores those
conditions will produce a solution that works in isolation but fails in context.
Symptom of this pattern being present: the statement distinguishes the missing
capability from the surrounding ecosystem conditions needed for it to stick.
Test: does the problem statement name the surrounding conditions (conventions,
integrations, adoption) required for any solution to actually hold?

**P11. The problem statement establishes whether the problem is new or
pre-existing.**
A problem that has existed since the project's inception is different from one
introduced by a recent change, and the two demand different framing: the former
must explain why it is being addressed now and not before, the latter should
point at the regression that surfaced it. Distinguishing new from legacy guards
against re-litigating a deliberate past tradeoff as if it were a fresh defect
(Chesterton's Fence, via Chesterton, "The Thing": do not remove a fence until
you know why it was put there) [9]. A strong problem statement also distinguishes
the genuinely new from the merely newly-noticed. Symptom of this pattern being
present: the statement says when the problem began and what changed. Test: does
the problem statement say whether this is new behavior, a long-standing gap, or
a deliberate prior decision now being revisited?

**P12. The problem statement cites prior art and explains why it is insufficient.**
A problem worth solving has usually been hit before — internally (past tickets,
prior PRs, team BKMs) or externally (libraries, papers, established practice) —
and a strong statement surveys those existing solutions and workarounds before
proposing new infrastructure (Hunt, Thomas, "The Pragmatic Programmer": "Don't
Repeat Yourself" applies to solution design, not just code; reinventing a solved
problem duplicates knowledge that already exists) [10]. The statement should name the
nearest existing solution and the specific gap that makes it inadequate here,
rather than asserting novelty by silence. This is the problem-layer prior-art
entry (parallel to direction D12, design DS12, tradeoff T12, implementation I12):
before framing the problem as unsolved, survey what already exists and say why it
falls short. Symptom of this pattern being present:
the statement references at least one prior attempt, workaround, or external
approach and explains precisely where it falls short. Test: has the author named
the closest existing solution (internal or external) and said why it does not
already resolve the harm?

## Anti-patterns (signs the layer is unsettled)

**AP1. Problem stated as a solution.**
"We don't have a way to categorize review threads by layer" is a solution
posture in disguise. The real problem is the downstream harm — architectural
questions that resurface across sessions, reviews that block on style while
design is still open. Thread categorization is one possible mechanism; it is
not the problem. Symptom: the problem statement contains nouns like
"mechanism," "feature," "tool," or "system" before any harm is established.
Test: can the author restate the problem without naming any artifact that could
be built?

**AP2. Problem is underspecified — no harm named.**
"Review quality could be better" is not a problem. It names a direction, not
a harm. A problem statement that omits who is harmed, in what situation, and
with what consequence leaves every solution looking equally valid and makes the
PR unevaluable for fit. Reinertsen's principle [2] applies: work without a traceable
valued outcome is waste. Symptom: the statement names a direction or aspiration
("better," "cleaner," "faster") with no actor, situation, or measurable cost
attached. Test: what does someone fail to do, ship, or learn as a direct result
of this problem existing today?

**AP3. Problem scope is personal, not general.**
"I find multi-PR juggling hard" is a personal friction report. It may point
at a real class-level problem, but the problem layer must establish that the
pain generalizes — across people, teams, or repos — before it justifies shared
infrastructure. Per Moore [8], infrastructure for one person's workflow is a
productivity hack, not a product feature. Symptom: first-person framing
("I always," "I never"), no evidence of recurrence beyond the author's own
experience, and no attempt to name other stakeholders who share the job.
Test: can the author name a second person, team, or repo that hits this same
problem independently?

**AP4. "We should" framing substitutes for problem description.**
"We should have structured review layers" is a normative claim, not a problem
statement. It tells a reviewer what the author wants to build, not what is
currently broken. Solutions follow from problems, not from norms. This framing
is especially dangerous because it sounds like a design decision when the
problem layer hasn't been settled yet — reviewers may find themselves debating
the merits of the solution before agreeing on what is being solved. Symptom:
the statement is phrased as "we should/need/want X" with no preceding sentence
describing what is broken without X. Test: strip every "we should" clause — does
any description of a current harm remain?

**AP5. Treating a complex problem as merely complicated.**
The Cynefin framework (Snowden) [11] distinguishes complicated problems (cause and
effect are discoverable by experts) from complex ones (cause and effect are only
apparent in retrospect). A problem statement that presents a complex sociotechnical
issue — e.g., review culture degrading over time — as if it has a single
diagnosable root cause will produce a solution that is confident but fragile.
Symptom: the problem statement uses causal language ("the reason reviews fail
is X") for a phenomenon that has been observed to recur despite previous fixes,
or that varies significantly across teams. Test: has a confident single-cause
fix for this same problem been tried before and failed to make it stay solved?

**AP6. The problem statement is circular — it assumes its own conclusion.**
"We need structured reviews because unstructured reviews are bad" re-states the
conclusion as the premise. A circular problem statement cannot be falsified and
therefore cannot be evaluated. Wiegers (requirements engineering) [1] calls this
an ambiguous requirement: a statement whose truth depends on accepting the
solution framing. Symptom: the harm clause and the proposed-solution clause are
restatements of each other with the polarity flipped. Test: can a skeptical
reviewer construct a world where the stated harm exists but the proposed solution
does not follow? If not, the problem statement has smuggled in the solution.

**AP7. The problem is validated only against the innovator's own use, not the
mainstream's.**
Christensen's "Competing Against Luck" [12] warns that problems validated exclusively
through the inventor's own experience tend to be real for early adopters but
absent for the mainstream. A PR that frames a problem based solely on the
author's past cases — without any signal from the broader audience who will
consume the solution — risks building infrastructure that solves a job nobody
else is trying to get done. Symptom: all cited instances come from the author
or a single closely allied collaborator, with no attempt to ask whether the job
recurs for the intended audience. Test: has anyone outside the author's
immediate context confirmed they face this job and that the current alternative
is inadequate?

**AP8. The problem statement conflates frequency with severity.**
A problem that occurs rarely but catastrophically (a deploy that corrupts
production data once a quarter) is not the same as one that occurs constantly
but cheaply (a linter nit on every PR). Reinertsen's cost-of-delay framing [2]
requires that both dimensions be stated. A problem statement that reports only
frequency ("this happens on every review") without severity ("causing N hours
of rework per cycle") leaves the reader unable to weigh it against competing
priorities. Conversely, a rare but severe problem may be understated if only
frequency is reported. Symptom: the statement reports one dimension in isolation
— how often it happens, or how bad it is when it does — but never both. Test:
does the problem statement give enough information to rank this work item against
other known problems in the backlog?

**AP9. Reinventing a solved problem with no prior-art search.**
A problem statement that asserts novelty without surveying internal tickets,
prior PRs, team BKMs, or external libraries and practice risks rebuilding
something that already exists — duplicating effort and forking the conventions
the team already relies on (Hunt, Thomas, "The Pragmatic Programmer": duplicated
knowledge, not just duplicated code, is the cost of skipping the search) [10]. The
inverse error is also common: dismissing the problem as "already solved
elsewhere" without checking whether the existing solution actually fits this
context. Symptom: the statement contains no reference to any prior attempt or
existing approach — neither "we tried X and it failed" nor "library Y is close
but lacks Z." Test: did the author search for prior art (internal and external)
and either cite the nearest existing solution with its gap, or document that the
search came up empty?

**AP10. The problem's premise has gone stale.**
A problem statement can be well-formed yet describe a world that no longer
exists: the failing case was fixed by an unrelated change, the workflow it
indicts was deprecated, or the team it harmed was reorganized away. Building on
a stale premise wastes effort on a harm nobody still bears, and prior-art search
(AP9) is what surfaces it — the "existing solution" may be a change that already
landed. This is distinct from re-litigating a deliberate prior decision (P11):
here the problem was once real but has since evaporated. Symptom: the cited
incident, ticket, or reproduction predates a known fix or migration, and no one
has confirmed the failure still reproduces on current main. Test: has the author
confirmed the problem still reproduces today, rather than citing only historical
instances?
