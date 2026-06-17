# Layer 4: tradeoff

**The question this layer answers:** Are the rejected alternatives properly
considered? Are the costs being paid the right ones?

> Sources named inline below are listed in full in
> [references.md](../references.md#tradeoff-layer).

## Patterns (what good looks like)

**T1. Each major design choice names a cost, not just a winner.**
A tradeoff record is not "X vs Y, and X wins." It is "X wins on dimension A at
the cost of dimension B; we accept dimension B's cost because it matters less here
than A." Essential complexity cannot be removed, only relocated (Brooks, "No
Silver Bullet" [1]: the essential complexity of a problem is irreducible — design
choices move where it is paid, they do not eliminate it). A tradeoff that claims
one option is strictly superior on every dimension has not yet found where the
complexity moved. A reviewer should be able to read the tradeoff and state, in one
sentence, what the author gave up. Symptom of this pattern being present: each
choice in the record is stated as "wins on A at the cost of B," never as an
unqualified win. Test: can the reviewer name the cost of the chosen approach
without reading the implementation?

**T2. The runner-up alternative is given genuine consideration.**
The closest alternative tests the design's reasoning more sharply than any option
that is clearly inferior — if the runner-up was nearly chosen, the tradeoff record
should say so and state what would tip the balance back (Kahneman, "Thinking, Fast
and Slow", WYSIATI — "what you see is all there is" [2]: the mind judges with the
evidence in front of it and neglects alternatives that require deliberate effort
to construct, so the runner-up is often the hardest alternative to fairly
evaluate). A tradeoff section that dismisses its runner-up in one clause — "we
considered X but it was complex" — has not found the dimension on which X wins.
Symptom of this pattern being present: the runner-up gets a full paragraph naming
its genuine advantage and the specific condition under which it would have won, not
a single dismissive sentence. Test: if conditions changed in one specific way,
would the runner-up become the right choice? The tradeoff record should name that
condition.

**T3. The tradeoff record names what evidence would update the bet.**
A tradeoff is a bet on an uncertain future (Duke, "Thinking in Bets" [3]: a tradeoff
record should name the probability estimate and the observations that would change
it; a record that states only what was decided without naming what would reverse
the decision cannot be updated as conditions evolve). A good record specifies:
what signal, in six months, would indicate the tradeoff should be revisited? This
makes the decision explicitly provisional rather than permanently settled. Symptom
of this pattern being present: the record contains a sentence of the form "revisit
this if X is observed," naming a concrete metric or event. Test: can a future
maintainer identify — without talking to the author — what changed condition would
warrant reopening the decision?

**T4. Irreversible tradeoffs are held to a higher evidentiary standard.**
Reversible tradeoffs are cheaper than they appear because they can be undone;
irreversible tradeoffs are more expensive than they appear because they foreclose
future options (Snowden, Cynefin framework [4]: in complex domains the right move is a
safe-to-fail probe — a reversible experiment — rather than an irreversible bet;
Bezos's "one-way vs. two-way doors" [5] makes the same point — reversible decisions
should be made fast and cheap, irreversible ones slowly and with more evidence). A tradeoff record should name
which options are foreclosed, when they close, and what additional evidence was
gathered before accepting the lock-in (Poppendieck, "Lean Software Development" [6]:
defer commitment — the cost of an irreversible decision is the value of all future
options it eliminates). Symptom of this pattern being present: API contracts,
schema fields, and event-type names are treated as irreversible and reviewed with
more care than internal implementation choices. Test: is the level of scrutiny
proportional to how difficult reversal would be?

**T5. Foundation-level tradeoffs carry more evidence than feature-level ones.**
A small tradeoff at the API surface, schema vocabulary, or event-naming layer has
outsized consequences at scale because every downstream consumer compounds it; the
same tradeoff inside a single module is cheap to reverse. A schema field added at
layer 0 of a large distributed system is far harder to remove than a function
renamed inside one service — the analysis budget should track the blast radius of
reversal, not the size of the diff (Hyrum's Law [7]: with enough consumers, every
observable behavior of a contract is depended upon, so foundation-level surfaces
ossify faster than their authors expect). A tradeoff record for a foundation-level
decision should cite more evidence, explore more alternatives, and state explicit
migration paths for the rejected options. Symptom of this pattern being present:
the tradeoff section for a public API change is substantially deeper than the one
for a private helper function. Test: is the depth of analysis proportional to the
blast radius of reversal?

**T6. The tradeoff record accounts for cost of delay, not just direct build cost.**
A tradeoff that compares "build option A" against "build option B" but does not
account for the cost of not solving the problem now is incomplete (Reinertsen,
"The Principles of Product Development Flow" [8]: delay cost is often larger than the
direct cost difference between alternatives; the right choice frequently changes
when delay cost is included). A deferred solution accrues interest — workarounds
proliferate, knowledge degrades, dependent systems build assumptions the solution
would remove. Symptom of this pattern being present: the record states the cost of
deferring the decision by a concrete interval, not just the cost of building each
option. Test: does the tradeoff record state what happens if this decision is
deferred three months? If the answer is "nothing much," the urgency claim in the
problem layer deserves scrutiny.

**T7. The tradeoff names what resilience is being traded for efficiency.**
Systems optimized for efficiency are fragile; the tradeoff record should name what
resilience is being given up when the chosen option improves throughput, reduces
latency, or lowers resource cost (Meadows, "Thinking in Systems" [9]: tradeoffs between
efficiency and resilience are the central system design tension; a system that
maximizes efficiency has eliminated redundancy, which is the same thing as
eliminating the ability to absorb perturbation). A tradeoff that improves the
local measure while worsening the global system is a local optimum, not an
improvement (Ackoff [10]: a system is not the sum of its parts but the product of their
interactions, so improving a part in isolation can degrade the whole — the
performance of the system depends on how the parts fit, not on each part optimized
alone). Symptom of this pattern being present: the record names a specific
redundancy, slack, or failure-absorption capacity that the efficient option
consumes. Test: does the tradeoff section name what the system loses under failure
conditions if the efficient option is chosen?

**T8. The tradeoff identifies the throughput metric being maximized, not just the
local cost.**
A tradeoff evaluated by local cost accounting can appear favorable while worsening
global throughput (Goldratt, "The Goal" [11]: throughput accounting vs. cost accounting
— decisions that look good on a local cost basis frequently worsen the constraint
that governs system output). A tradeoff record that minimizes engineer-hours on
one team while creating a dependency bottleneck for three downstream teams has not
measured the right variable. The tradeoff record should name the system-level
metric — deploy frequency, end-to-end latency, time-to-diagnosis — that the
decision is being optimized against. Symptom of this pattern being present: the
record names a global, system-level metric the decision moves, not only a
team-local cost like engineer-hours. Test: does the tradeoff identify what
constraint in the system the chosen option helps or hurts?

**T9. The tradeoff explicitly names the opportunity cost — what was foregone.**
Every tradeoff forecloses the next-best option; a record that names only the
direct cost of the chosen option but not what was foregone is incomplete (classical
opportunity cost [12]: the cost of a choice is the value of the best alternative
sacrificed). Naming only the direct cost makes the chosen option look cheaper than
it is. Naming the foregone option creates the right reference class for evaluating
whether the choice was worth it. Symptom of this pattern being present: the record
names the best alternative use of the same resources that the decision forecloses,
not just the resources the chosen option consumes. Test: does the tradeoff record
name what the team can no longer do, or will do later and at higher cost, as a
direct consequence of the decision?

**T10. The tradeoff distinguishes false tradeoffs from real ones.**
Some tradeoffs that appear real are false — the two horns of the dilemma can both
be satisfied with a different approach (Forsgren, Humble, Kim, "Accelerate" [13]: the
belief that speed and stability are fundamentally in tension is empirically false
for high-performing organizations; stating "we traded stability for speed" may
disguise a process or architecture problem that creates the apparent constraint).
A tradeoff record that accepts a dilemma without testing whether the dilemma is
real has not finished the analysis. Symptom of this pattern being present: for each
"we must give up X to get Y" claim, the record states why a third option that gets
both is unavailable here. Test: is there any evidence that other teams or systems
have achieved both horns simultaneously? If so, the tradeoff record should explain
why that path is not available here.

**T11. Technical debt incurred is named with a repayment plan.**
Deliberate tradeoffs that accept known shortcuts incur debt; a good tradeoff record
names the debt and the repayment plan; undocumented debt compounds silently
(Cunningham, technical debt metaphor [14]: the original metaphor was for deliberate,
named shortcuts with a known repayment plan — undocumented debt is not technical
debt, it is an uncontrolled liability). The repayment plan should name the trigger
condition ("when we add a second data type") rather than just the intention ("we
will fix this later"). Symptom of this pattern being present: each accepted shortcut
is recorded with a named carrying cost and a concrete repayment trigger, not left
implicit. Test: can a future maintainer identify, without author context, what the
shortcut was, what it costs to carry it, and what event should trigger paying it
back?

**T12. The tradeoff cites how it was already litigated, here or in the literature.**
This is the tradeoff-layer member of the cross-layer prior-art set (parallel to
problem P12, direction D12, design DS12, implementation I12): each layer asks its own
version of "has this been done before?" — here, has this exact tradeoff already been
decided? Most tradeoffs are not new: the efficiency-vs-resilience, consistency-vs-availability,
build-vs-buy, and monolith-vs-services debates have been argued in prior ADRs,
postmortems, and the published literature. A strong record states whether this exact
tradeoff has been decided before — and if the team is choosing the opposite of a
prior decision, what new information justifies the reversal (Larson, "An Elegant
Puzzle" [15]: durable decisions are recorded so they are not relitigated from scratch
each time; reopening one without new evidence burns trust and time). The
CAP theorem (Brewer [16]) and the speed/stability finding (Forsgren et al., "Accelerate" [13])
are examples of tradeoffs the literature has already resolved or reframed — citing
them prevents re-deriving a known result. Symptom of this pattern being present: the
record links to the prior ADR or external source it is consistent with, or names the
new fact that overturns it. Test: has this tradeoff been decided before in this
codebase or the literature, and if the choice differs, what changed?

**T13. The tradeoff accounts for second-order and delayed consequences.**
The cost that matters is often not the first-order one the author optimized against
but the second-order effect that arrives later: the cache that improves latency now
and creates an invalidation hazard later, the coupling that speeds this feature and
slows the next ten (Meadows, "Thinking in Systems", policy resistance [9]: a system
pushes back against interventions that ignore its feedback structure, so the
short-term win is reversed by the system's response). A tradeoff record that stops
at the immediate, measurable cost has measured the cheap half. Symptom of this pattern being present: the record
names only effects observable within the current sprint, with no statement of what
the decision makes harder six months out. Test: does the record name at least one
second-order or delayed consequence, not just the immediate cost the author
optimized against?

**T14. The tradeoff names who bears the cost, not just what the cost is.**
A cost has an address: the team that absorbs the on-call load, the downstream
service that inherits the coupling, the future maintainer who pays the carrying
cost, the user who absorbs the latency. A tradeoff that lowers cost for the
deciding team by externalizing it onto another party is not a net win — it is a
transfer, and the record should say so (Conway's Law [17] makes the transfer concrete:
the system's interfaces mirror the org's communication structure, so a cost moved
across a module boundary usually lands on the team that owns that boundary). When
the bearer of a cost is not in the room, the cost tends to be undercounted. Symptom
of this pattern being present: each named cost in the record is attributed to a
specific party — this team, that downstream service, the future maintainer, the
user. Test: for every cost the record accepts, can the reviewer name who pays it,
and was that party consulted?

**T15. The tradeoff weighs tail risk, not just the expected case.**
Two options with the same expected cost are not equivalent if one has a bounded
downside and the other has a ruinous tail. A tradeoff record that compares only
average or modal outcomes can accept a fragile option whose rare failure is
catastrophic and unrecoverable (Taleb, "Antifragile" and "The Black Swan" [18]: in the
presence of fat-tailed risk, avoid options with ruinous downside even at higher
expected value — "do not cross a river that is on average four feet deep"). The
right question for an irreversible or safety-relevant tradeoff is not "what happens
usually" but "what is the worst case, and can we survive it." Symptom of this
pattern being present: the record states the worst-case outcome of the chosen
option and whether it is recoverable, not only the expected one. Test: does the
tradeoff name the worst plausible outcome of the chosen option, and is that
downside survivable?

**T16. The tradeoff weights present and future costs on a consistent scale.**
People systematically over-discount future costs relative to present ones, so a
tradeoff that takes a cheap win now and a larger expense later looks better than it
is (hyperbolic discounting, Ainslie, "Picoeconomics" [19]: near-term outcomes are weighted
far more heavily than distant ones, and the discount rate is inconsistent over time,
which biases choices toward immediate payoff and deferred pain). This differs from
cost of delay (T6, the cost of deferring the decision) and from second-order effects
(T13, the kind of consequence): here the question is whether a future cost was
deflated simply because it is future. A good record states future costs in
comparable terms — undiscounted, or with an explicit and defensible discount rate.
Symptom of this pattern being present: the record names the future carrying cost in
the same units and at the same prominence as the present build cost, not as a vague
"we'll deal with it later." Test: is the chosen option still preferred if the future
cost is moved to the present and weighed at full value?

## Anti-patterns (signs the layer is unsettled)

**AP1. "Alternative X is strictly worse."**
No credible alternative is strictly worse on all dimensions; an alternative that
survives long enough to be named has at least one advantage. Claiming strict
inferiority either means the comparison is incomplete or the alternative was not
seriously considered (Kahneman, "Thinking, Fast and Slow" [2]: the anchoring effect
causes the first framing of the chosen option to become the baseline from which
alternatives look like costs — framing the analysis this way makes the chosen
option appear cheaper than it is). When a reviewer sees "strictly worse," the
productive follow-up is: on what dimension does this alternative win? Symptom:
the tradeoff section lists alternatives with only costs attached, no benefits. Test:
can the reviewer construct a scenario in which the rejected option would be correct?

**AP2. Tradeoffs listed only for rejected alternatives, not for the chosen approach.**
A tradeoff section that names costs only for the unchosen paths has not completed
the analysis. A complete record also names the cost of the chosen approach: what
the system sacrifices, what failure modes become more likely, and what future
evolution becomes harder. Listing costs only for alternatives is a form of
advocacy, not analysis, and it prevents a reviewer from evaluating whether the
accepted costs are the right ones to carry. Symptom: the tradeoff section reads
as a brief for the author's preference, not an honest accounting. Test: does
the tradeoff section name at least one significant cost of the chosen option?

**AP3. Prior investment cited as a reason to continue.**
"We've already built X this way" is not a tradeoff argument — it is sunk-cost
reasoning (the sunk-cost fallacy, as formalized by Arkes and Blumer, "The
Psychology of Sunk Cost", 1985 [20]: prior unrecoverable investment irrationally biases
the decision to continue, even though only the marginal value of continuing vs.
stopping is relevant). A tradeoff record that
cites prior investment as the primary justification for a design choice has
confused the cost of switching with the value of the current approach. Symptom:
the strongest sentence in favor of the chosen option describes effort already spent
("we've invested months in this path") rather than marginal value going forward.
Test: does the tradeoff argument hold if the prior investment is excluded from the
analysis? If the argument collapses, the record is arguing from sunk cost.

**AP4. The tradeoff is judged by its outcome rather than the quality of reasoning.**
"This worked out well" does not mean the tradeoff was well-reasoned at the time
it was made (Duke, "Thinking in Bets", resulting fallacy [3]: a bad decision that
produced a good outcome is still a bad decision; a good decision that produced a
bad outcome is still a good decision). Tradeoff quality should be evaluated against
the information available at decision time, not against what happened afterward.
Symptom: the tradeoff section presents the current good outcome as evidence that
the reasoning was sound, without stating what reasoning was applied before the
outcome was known. Test: was the analysis sound at the time — before the outcome
was visible?

**AP5. Status quo costs are invisible; alternative costs are prominent.**
The current state appears cheaper than it is because its costs are familiar and
therefore invisible; alternatives appear more expensive than they are because their
costs are novel and therefore salient (status quo bias, Samuelson and Zeckhauser,
"Status Quo Bias in Decision Making", 1988 [21]: decision-makers systematically favor
the current state, and the asymmetric visibility of familiar vs. novel costs
distorts tradeoff analysis in favor of inaction). A tradeoff record that enumerates
the risks of changing while leaving the risks of not changing unstated has not
applied equal scrutiny to both options. Symptom: the tradeoff section contains a
detailed risk list for each alternative but no risk list for the current approach.
Test: does the tradeoff record give equal treatment to the costs of the status quo
and the costs of the alternatives?

**AP6. Batch size not considered — the decision treats scope as fixed.**
A large change may be executable as a smaller change with lower delay cost and
faster feedback; choosing the large batch without considering whether a smaller
batch is possible is an unexamined tradeoff (Reinertsen, "The Principles of Product
Development Flow" [8]: batch size tradeoffs — smaller batches reduce delay cost and
improve feedback quality but increase transaction overhead; the optimal batch size
depends on the relative costs, which must be measured not assumed). Symptom: the
design introduces a large, coordinated change where a staged rollout or
feature-flag-gated increment was available but not considered. Test: is there a
version of this change that could have shipped in one-third of the scope, provided
meaningful feedback, and preserved the option to stop or redirect?

**AP7. The tradeoff treats reversible and irreversible decisions identically.**
Applying the same level of scrutiny to a decision that can be undone in an hour
and one that cannot be undone without a multi-month migration is a calibration
failure (reversibility asymmetry [5]: reversible decisions are cheaper than they appear
because mistakes can be corrected; irreversible decisions are more expensive than
they appear because they foreclose future options; a tradeoff record that treats
both the same is systematically miscalibrated). Over-analyzing reversible decisions
wastes time; under-analyzing irreversible ones creates permanent debt. Symptom:
the tradeoff section devotes equal space to a naming choice that can be aliased
away and an API contract that will be consumed by external systems. Test: is the
depth of tradeoff analysis proportional to the actual cost of reversal?

**AP8. The tradeoff record is a post-hoc justification, not an analysis.**
A tradeoff section written after the implementation was decided reads as advocacy:
it lists costs for alternatives but not for the chosen approach, frames the chosen
option as the baseline, and omits the near-miss cases where a different choice
would have been correct (confirmation bias, Wason, "On the Failure to Eliminate
Hypotheses", 1960 [22]: people seek and structure evidence to confirm a conclusion
already reached rather than to falsify it, so analysis written after the decision
becomes a brief for it). A genuine tradeoff record names the cases where the chosen approach
loses and states what conditions would have led to a different choice. Symptom:
the tradeoff section has no hedge, no admission of uncertainty, and no condition
under which the author would have chosen differently. Test: does the tradeoff
record acknowledge at least one realistic scenario where the rejected alternative
would have been the right call?

**AP9. A settled tradeoff is relitigated — or reinvented — with no prior-art search.**
The mirror failures: re-deriving a tradeoff the team already decided (ignoring a prior
ADR or postmortem) and re-deciding a tradeoff the literature has already resolved
(re-arguing CAP [16], or assuming speed and stability trade off when "Accelerate" shows
they do not for high performers — Forsgren, Humble, Kim [13]). Both waste effort and
discard hard-won context (Larson, "An Elegant Puzzle" [15]: cheap-to-reverse decisions
can be made locally, but durable ones should be recorded and consulted, not
relitigated from a blank page). A record that neither cites the prior decision it
agrees with nor names the new evidence that overturns it has skipped the search.
Symptom: no link to a prior ADR, RFC, postmortem, or external source, and no sentence
explaining why the established conclusion does not apply here. Test: did the author
check whether this tradeoff was already litigated internally or in the literature,
and either align with it or justify the departure?

**AP10. The chosen option is claimed to win on every dimension.**
A genuine tradeoff has a shape: the chosen option gives something up. A record in
which the preferred option is cheaper, faster, simpler, AND more flexible than every
alternative is not a tradeoff analysis — it is a sales pitch, and it usually means
the costs were not looked for (this is the dominated-alternative tell: real
candidates form a Pareto frontier where each wins on some axis; if one option
dominates all others on all axes, either the alternatives were strawmen or a
dimension is missing). The healthy follow-up is to ask which axis the chosen option
is worst on. Symptom: the comparison table has the chosen column winning every row.
Test: on which single dimension does the chosen option lose to its closest
alternative — and if there is none, what dimension is missing from the table?

**AP11. The quantifiable cost is weighed and the unquantifiable cost is dropped.**
Tradeoff records over-weight dimensions that produce numbers — latency, dollars,
lines of code — and silently drop dimensions that resist measurement: maintainability,
cognitive load, team morale, optionality. The result is a decision that optimizes
what was easy to count rather than what mattered (the McNamara fallacy, named for
Robert McNamara and articulated by Daniel Yankelovich [23]: the error of treating the
measurable as important rather than making the important measurable, ultimately
discounting the unmeasurable as nonexistent; a number for one side and a shrug for
the other is not a comparison). Naming an unquantified cost in
words is more honest than excluding it because it cannot be put in the spreadsheet.
Symptom: every cost in the record carries a number except the ones that are hard to
measure, which are absent rather than described. Test: does the record name the
costs that could not be quantified, or does it only weigh the ones that produced a
number?

**AP12. Flexibility is bought for a future that may never arrive.**
A tradeoff that accepts present complexity to preserve an option for a hypothetical
future need is paying a certain cost now for an uncertain benefit later. Speculative
generality — the abstraction layer, plugin system, or configuration knob added "in
case we need it" — is a tradeoff whose cost is real and whose benefit is conditional
on a future that frequently does not occur (the YAGNI principle, attributed to Ron
Jeffries in Extreme Programming [24]: do not build for requirements you do not yet have;
Fowler catalogs "speculative generality" as a code smell [25] for the same reason). The
record should state the probability that the preserved option will ever be exercised
and the cost of carrying the flexibility until then. Where design AP10 asks whether
the speculative seam is architecturally justified (is there a second concrete
variant?), this entry asks whether the cost-versus-conditional-benefit accounting
for that flexibility is honest. Symptom: the justification for
the chosen option's added complexity is a future requirement that is hypothesized,
not committed, with no estimate of how likely it is. Test: if the speculative future
need never arrives, was the added complexity worth carrying for its own sake?

**AP13. A weighted scoring table launders subjective weights as objectivity.**
A decision matrix that scores each option on several criteria, multiplies by
weights, and sums to a "winner" appears rigorous but usually buries the actual
judgment in the choice of weights and scores — which can be tuned, consciously or
not, to make the preferred option win (this is the spreadsheet-as-advocacy failure:
quantification of inherently qualitative weights manufactures false precision and
hides where the real decision was made). The numbers are downstream of the weights;
if the conclusion flips under a small, defensible change to the weights, the table
proved nothing. A reviewer should test the table's sensitivity, not its arithmetic.
Symptom: the record presents a weighted-sum table whose winner depends on weights
that are asserted without justification and never stress-tested. Test: does the
chosen option still win if the most contestable weight is moved by a reasonable
amount — and if not, where is that judgment actually defended?

**AP14. The option set is narrowed to two before the analysis begins.**
A tradeoff presented as "A vs B" can be sound, but it can also be a false dilemma
that hid the real candidates by framing the choice as binary before any analysis ran
(the false-dilemma framing: restricting the option set to two artificially inflates
whichever the author prefers, since a deliberately weak foil makes the favorite look
inevitable). This differs from AP1 (a named alternative dismissed as strictly worse)
and T10 (a dilemma whose two horns could both be satisfied): here the failure is that
viable options were never enumerated at all — a third architecture, a buy-instead-of-build,
a do-nothing baseline, a staged subset. A record that compares exactly two options
should justify why the set is closed. Symptom: the comparison contains the chosen
option and exactly one foil, with no statement of how the candidate set was generated
or why other options were excluded. Test: how was the option set chosen, and what
plausible third option is absent from the comparison?
