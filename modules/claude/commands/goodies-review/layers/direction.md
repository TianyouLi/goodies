# Layer 2: direction

**The question this layer answers:** Given the problem, is the chosen direction
sound? Are alternatives ruled out for the right reasons?

> Sources named inline below are listed in full in
> [references.md](../references.md#direction-layer).

## Patterns (what good looks like)

**D1. Direction is stated as a thesis, not a feature list.**
A direction is an approach — "structure review discourse as a layer hierarchy
with gated reopens" — not a list of what will be built. The thesis can be
wrong; a feature list can't. A direction that's a thesis invites productive
disagreement at the right level of abstraction. Symptom of this pattern being
present: the direction section states a claim that a skeptic could argue
against, not a list of deliverables. Test: can a reviewer disagree with the
direction without disagreeing with any individual feature?

**D2. At least two credible alternatives were considered.**
A direction chosen without alternatives is a default, not a decision (Nygard,
"Documenting Architecture Decisions" [1]: an ADR records the decision *and* the
options rejected). The direction layer should name the runner-up(s) and state
specifically why the chosen direction beats them *for this problem*. "We
considered X but chose Y because Z" with an articulated reason demonstrates
decision quality. Symptom of this pattern being present: at least one rejected alternative is
stated in a form its strongest proponent would recognize, with the specific
reason the chosen direction beats it. Test: is at least one rejected
alternative stated in a form its strongest proponent would recognize?

**D3. The chosen direction is falsifiable.**
A sound direction implies a failure mode: circumstances under which it would
break down or prove wrong (Duke, "Thinking in Bets" [2]: make the bet explicit, name
the odds, state what would update it). Stating those makes the choice honest and
tells reviewers what to look for in future evaluation. Symptom of this pattern being present: the direction names the circumstances
under which it would break down or prove wrong. Test: what
observation, if it occurred, would tell us this direction was the wrong call?

**D4. Direction separates policy from mechanism.**
A direction states *what policy governs the system* — not *how it will be
implemented* (Raymond, "The Art of Unix Programming" [3]: separate policy from
mechanism; Martin, "Clean Architecture" [4] frames the same split as policy vs.
detail). "Reviews are structured as a layer hierarchy" is policy; "we use a YAML
header to encode layer status" is mechanism. Conflating the two closes off design
options prematurely and makes the direction harder to evaluate on its own
terms. Symptom of this pattern being present: the direction can be stated at the
policy level — what governs the system — without naming any specific mechanism. Test: can you state the
direction without naming any specific data structure, file format, or API?

**D5. Direction holds under the realistic spread of problem instances.**
A robust direction should work across the class of problem instances, not just
the prototype case that motivated the PR. If the problem is "reviewers skip
layers," a direction that relies on reviewers already agreeing on layer
boundaries is fragile. Symptom of this pattern being present: the direction is
argued against the hardest plausible instance, not just the motivating one.
Test: does this direction still hold if the problem instance is harder, rarer,
or handled by a less-experienced practitioner?

**D6. Direction names which type of response is being taken.**
Ackoff [5] identified four treatments of a problem: dissolve (redesign so the
problem no longer arises), solve (optimize for the best outcome), resolve
(satisfice with a good-enough fix), or absolve (ignore and accept the
consequences) (Ackoff, "The Art of Problem Solving" [5]). A direction that names
which treatment it is avoids scope creep and false expectations. Symptom of
this pattern being present: the direction names whether it is a permanent fix or
a temporary patch, and stakeholders agree on that framing. Test: is this
direction dissolving, solving,
resolving, or absolving the problem, and does everyone agree on which?

**D7. Direction accounts for adoption cost.**
A direction that requires high-adoption behavior change from users fails earlier
in the adoption curve than anticipated (Rogers, "Diffusion of Innovations" [6]:
adoption cost is a direction-level concern, not a rollout detail). If the
direction depends on all reviewers consistently following a new protocol, that
dependency should be stated and the adoption strategy sketched. Symptom of this pattern being present: the
direction names the behavior change it requires and sketches the adoption
strategy, including what happens if adoption is only partial. Test: what behavior change does this direction require, and
what is the plan if adoption is partial?

**D8. Direction is calibrated to the evolutionary stage of its components.**
Directing engineering investment at a commodity component (generic diff
display, off-the-shelf linter) is wasteful; directing it at a genesis component
requires exploration, not commitment (Wardley Mapping [7]: match investment strategy
to component stage). A direction that treats a commodity as custom-built, or
commits a big-bet architecture to a genuinely uncertain space, is suspect at the
direction layer. Symptom of this pattern being present: for each component the direction invests
in, the investment level matches its evolutionary stage — exploration for
genesis, reuse for commodity (Snowden, Cynefin framework [8]: a safe-to-fail
probe for the genuinely uncertain parts).
Test: for each component this direction invests in, is it genesis, custom,
product, or commodity — and does the investment level match?

**D9. Direction is matched to the disruption profile of the change.**
An incumbent-improving direction and a disruptive direction have different risk
profiles and require different success criteria (Christensen, "The Innovator's
Solution" [9]: conflating sustaining and disruptive directions leads to applying the
wrong evaluation framework). A direction that improves an existing process should
be judged on efficiency and adoption; a direction that displaces an existing
process should be judged on whether the new value proposition is reachable from
the current foothold. Symptom of this pattern being present: the direction is explicitly classified
as sustaining or disruptive, and is judged by the criteria appropriate to that
type. Test: is this direction sustaining or disruptive,
and are we judging it by the criteria appropriate to that type?

**D10. Direction identifies which outcome levers it moves.**
A direction should state which measurable delivery or quality outcomes it
expects to shift — lead time, deployment frequency, change-fail rate, MTTR
(Forsgren, Humble, Kim, "Accelerate" [10]: the four key delivery metrics). This is
distinct from proxy metrics (AP5); the claim is that the direction moves a
lagging outcome, not just a leading indicator. Symptom of this pattern being
present: the direction names a target outcome and the direction (sign) of the
expected change. Test: which lagging outcome does this direction claim to move,
and how would we observe the movement?

**D11. Direction is grounded at the bounded-context boundary.**
A direction that crosses bounded-context boundaries without naming the
integration strategy creates design drift (Evans, DDD [11]: strategic design decisions
live at context boundaries). If the direction touches more than one bounded
context — say, "the review layer" and "the merge gate" — it should name the
relationship (conformist, anti-corruption layer, open host) and own the
cross-context coupling as a deliberate choice. Symptom of this pattern being present: the direction names each bounded context
it touches and the integration relationship between them (conformist,
anti-corruption layer, open host). Test:
how many bounded contexts does this direction touch, and is the integration
relationship between them named?

**D12. Direction reports whether this approach has been tried, here or elsewhere.**
(Direction-layer member of the cross-layer prior-art set, parallel to
P12/DS12/T12/I12.) A sound direction states whether the chosen approach has prior
art — attempted
before on this team, in this codebase's history, or documented externally — and
what the result was (Nygard, "Documenting Architecture Decisions" [1]: superseded
ADRs exist precisely because directions get retried). "We tried gated reopens in
2023 and abandoned them because X" is a stronger basis than silence. Searching
for prior attempts converts a fresh bet into an informed one and surfaces the
conditions that changed. Symptom of this pattern being present: the direction
cites a prior attempt (internal post-mortem, superseded ADR, or an external
team's published result) and explains what is different now. Test: has this
direction been tried before, and if so, what changed to make it worth retrying?

**D13. Direction commits reversibly when the bet is uncertain.**
For a hard-to-reverse direction (a "one-way door"), the bar for evidence and
alternatives is higher; for an easily reversible one (a "two-way door"), bias
toward acting and learning (Bezos, 2016 Amazon shareholder letter [12]: distinguish
Type 1 from Type 2 decisions). A sound direction states its reversibility and
calibrates rigor accordingly, rather than agonizing over a cheap-to-undo choice
or rushing an irreversible one. This is the reversibility of the *approach as a
whole*; calibrating scrutiny to the reversal cost of each individual accepted
cost (API contracts, schema fields, naming) belongs to the tradeoff layer (T4,
AP7). Symptom of this pattern being present: the direction names how it would be
backed out and at what cost. Test: is this a one-way or two-way door, and does
the deliberation match?

**D14. Direction is weighed against the null option of doing nothing.**
"Do nothing" is always a live alternative, and a sound direction states the
cost of inaction — what continues to degrade, or what opportunity is foregone,
if the status quo persists (this is distinct from D6's "absolve," which is a
deliberate choice to accept consequences; the null option is the *baseline* every
other direction must beat). Quantifying the cost of delay turns "we should do
something" into "this is worth doing now versus later" (Reinertsen, "The
Principles of Product Development Flow" [13]: cost of delay is the one number that
makes prioritization economic). Here the cost of delay sets the *go/no-go
baseline* for the approach as a whole; folding deferral cost into the accounting
for a specific accepted cost is the tradeoff layer's concern (T6). Symptom of
this pattern being present: the
direction is justified relative to the cost of leaving the problem unaddressed,
not just relative to other active options. Test: what is the cost of doing
nothing, and does the chosen direction clear that bar by a margin worth the
effort?

**D15. Direction is checked for second-order and systemic effects.**
A direction can be locally sound yet create worse system behavior through
feedback loops, displaced load, or perverse incentives elsewhere (Meadows,
"Thinking in Systems" [14]: the higher-leverage interventions are often counter-
intuitive, and fixes that ignore feedback tend to be defeated by the system).
A direction that "structures review discourse into layers" might, for instance,
push low-quality comments into whichever layer is least gated. A sound direction
names the most likely second-order effect and argues it is tolerable or
mitigated. This is the direction-level question of whether the *approach* triggers
a systemic backlash; weighing whether a specific accepted *cost* is the
second-order one is the tradeoff layer's job (T13). Symptom of this pattern being
present: the direction discusses not just its intended first-order effect but
where the displaced behavior or load goes. Test: if this direction works as
intended, what does the system do in response, and is that response acceptable?

**D16. Direction defers commitment to the last responsible moment when the option space is still open.**
When more than one direction remains credible and the cost of keeping them open
is low, a sound direction can carry the leading candidate forward while
preserving a fallback rather than converging prematurely (Poppendieck, "Lean
Software Development" [15]: decide at the last responsible moment; Sobek/Ward, set-based
concurrent engineering [16]: hold a set of options until the data narrows it). This is
the complement of D13 — D13 calibrates rigor to reversibility, while D16 asks
whether commitment must be made at all yet. The discipline is naming the
decision point: the observation or deadline at which the choice must be locked.
Symptom of this pattern being present: the direction names which alternatives are
still live and the trigger that will resolve the choice, rather than declaring a
single winner before the evidence justifies it. Test: does this direction have to
be locked now, or can the leading and fallback options both be carried until a
named decision point?

## Anti-patterns (signs the layer is unsettled)

**AP1. Direction conflated with mechanism.**
"We'll add a `[review-pr / layer / status]` header" is a mechanism (a design or
implementation choice), not a direction. The direction should be at a level where
the header is one of several plausible implementation options. When direction and
mechanism are fused, the PR cannot be reviewed at the right level of abstraction
— disagreement about the header becomes disagreement about the direction, and
vice versa. Symptom: the only way to challenge the direction is to challenge a
specific implementation detail. Test: if the named mechanism were swapped for a
different one, would the direction still stand?

**AP2. Alternatives dismissed without engagement.**
"We could have used labels, but structured comments are better" is dismissal, not
a reason. A direction is sound when the rejection of alternatives is as
defensible as the acceptance of the chosen path (Nygard, "Documenting
Architecture Decisions" [1]: consequences of rejected options matter). Symptom:
alternatives are listed in one sentence each with no stated failure mode — the
author has enumerated but not reasoned. Test: for each rejected alternative, is
there a concrete failure mode, not just a comparative adjective?

**AP3. Direction solves the instance, not the class.**
A direction that patches one PR review style without addressing the general
failure mode will leave the problem partially unsolved. If the motivating
instance is a single noisy PR, and the direction only handles that noise pattern,
the next variant of the problem will require a new direction. The direction layer
should articulate what class of problem the direction addresses. Symptom: the
direction's justification refers only to the motivating incident, never to the
general failure mode behind it. Test: name a second, different instance of the
problem — does this direction handle it too?

**AP4. Direction assumes buy-in not yet established.**
"We'll enforce the layer hierarchy in all PR reviews" is a direction that assumes
a level of team commitment the PR hasn't established. Directions that depend on
organizational adoption before they can deliver value are high-risk bets;
the direction layer should either show that buy-in exists or propose a direction
that delivers value incrementally without requiring it up front. Symptom: the
direction's value is unlocked only after everyone adopts it, with no value at
low adoption. Test: does this direction deliver any value before universal
adoption is achieved?

**AP5. Direction optimized for a proxy metric, not the valued outcome.**
A direction aimed at increasing review comment count, coverage percentage, or
layer-completion rate is directionally wrong if those metrics don't track the
actual valued outcome — fewer escaped defects, faster consensus, better design.
Once a measure becomes a target it ceases to be a good measure (Goodhart's Law [17];
Harris & Tayler, "Don't Let Metrics Undermine Your Business," HBR 2019 [18], on
surrogation — substituting the metric for the goal). Symptom: the success
criteria are all measurable leading indicators with no connection to the
lagging outcome the team actually cares about. Test: if this metric improved
while the underlying outcome got worse, would the direction still claim success?

**AP6. Direction by analogy without showing the analogy holds.**
"Other teams use structured review layers, so we should" is analogical reasoning
that hasn't been validated (first principles vs. analogical reasoning: show the
context transfers). The other team's problem, constraints, and adoption path
may differ in ways that make the direction unsuitable here. Symptom: the
direction section cites prior art or industry practice as justification without
examining whether the conditions that made it work elsewhere are present in
this context. Test: which specific conditions made the analogy's source case
succeed, and are those same conditions present here?

**AP7. Direction stated at the wrong level of abstraction for the audience.**
A direction pitched at the architectural level when the audience needs a
product-level framing (or vice versa) will not generate useful feedback — the
audience evaluates a different claim than the one being made. A systems-thinking
failure: the direction must be legible to the stakeholders who need to validate
it, not just to the author (Ackoff, "The Art of Problem Solving" [5]: dissolving a
problem requires shared framing before options can be evaluated). Symptom:
reviewers ask "but what will it actually do?" when the direction is stated, or
conversely ask "why are we doing this at all?" when only mechanism has been
described — the level of abstraction has been misjudged. Test: do the
stakeholders who must validate this direction operate at the level it is
pitched, or are they evaluating a different claim?

**AP8. Direction defended by prior investment rather than current merit.**
A direction that survives review because "we've already built half of it" or
"we committed to this last quarter" is escalation of commitment, not a decision
— sunk costs are sunk and should not bear on whether the direction is right now
(Staw, "Knee-Deep in the Big Muddy," 1976 [19]: people escalate commitment to a
failing course of action to justify prior choices). The relevant question is the
marginal one: starting from today's state, is this still the best direction? A
sound review separates "we have invested in X" from "X is the right approach."
Symptom: the justification leans on work already done or commitments already
made, and abandoning the direction is framed as waste rather than as cutting a
loss. Test: if no work had yet been done, would this still be the direction we
would choose today?

**AP9. Direction chosen with no search for prior attempts.**
A direction proposed as if the approach were untried — when the team, the
codebase history, or the wider industry has already attempted it — repeats
avoidable mistakes (the inverse of D12; superseded ADRs and post-mortems exist
to prevent exactly this, per Nygard, "Documenting Architecture Decisions" [1]). The
failure is not choosing a previously-tried direction; it is choosing one without
checking, so the conditions that defeated it last time go unexamined. Symptom:
the direction reads as a clean-slate invention, with no mention of whether this
was considered or attempted before. Test: what search for prior attempts (git
history, ADRs, incident reports, external write-ups) was done, and what did it
turn up?

**AP10. Direction converges on one option before the uncertainty justifies it.**
The mirror of D16: committing to a single direction while the decision is still
cheap to keep open and the evidence has not yet discriminated between candidates
trades away optionality for a false sense of progress. Premature convergence
funnels all subsequent design and implementation effort behind one bet, so when
the bet proves wrong the rework cost is paid in full (Poppendieck, "Lean Software
Development" [15]: deciding too early destroys the value of information that would
arrive for free by waiting). This differs from AP8 (escalation) — there the
problem is refusing to abandon a commitment already made; here it is making the
commitment too soon. Symptom: a sole direction is declared while reviewers can
still name a credible, un-eliminated alternative and there is no reason it had to
be ruled out now. Test: what made it necessary to pick this direction at this
moment rather than carry two candidates a little further?
