# Layer 5: implementation

**The question this layer answers:** Are the code-level choices correct,
consistent, and maintainable?

Note: this layer is partially delegated to Copilot and static analysis tools.
The patterns here serve two purposes: (1) recognizing when an automated finding
is actually a higher-layer issue in disguise, which is the primary value a human
reviewer adds beyond tooling; and (2) catching classes of problems that
automated tools miss because they require understanding intent, context, or the
gap between the design doc and the code.

> Sources named inline below are listed in full in
> [references.md](../references.md#implementation-layer).

## Patterns (what good looks like)

**I1. Implementation contracts match design contracts.**
If the design says "every tool-posted comment has a parseable header as the
first non-empty line," every code path that posts a comment satisfies that
invariant — including error paths, empty-result paths, and retry paths. Divergence
between design contract and implementation is not an implementation detail: it
is a design violation that the implementation layer surfaces first, and the
correct response is to go back to the design layer, not to patch the code
(Freeman, Pryce, "Growing Object-Oriented Software" [1]: the tests — and the
implementation — should exercise the component at the same seam the design
identified as the boundary; if the seam in the code is at a different level
than the design's seam, the design and the implementation have drifted).
Symptom of this pattern being present: for each design invariant named in the
design doc or contract schema, there is a corresponding test that would fail
if the invariant were violated. Test: for each invariant the design names, can
the reviewer point to the code path AND the test that enforce it on every branch
— including error, empty, and retry paths — or does the invariant hold only on
the happy path?

**I2. Names carry meaning without a comment.**
A name that requires an inline comment to interpret is a design failure surfaced
at the naming layer: the concept needed a better word, not an annotation
(Martin, "Clean Code" [2]: a name that requires a comment is a name that failed;
the comment is evidence that the right name wasn't found). This applies to
variables, functions, classes, files, and commit messages. The test is not
"does a comment exist?" but "if the comment were deleted, would the name still
communicate the intent correctly to someone unfamiliar with the implementation?"
Inconsistency in naming — the same concept called `event`, `action`, and
`payload` in three adjacent files — is a DDD ubiquitous-language violation
(Evans [3]): the codebase is speaking multiple dialects of the domain, which forces
readers to maintain a mental translation table that authors never documented
(Boswell, Foucher, "The Art of Readable Code" [4]: consistency means similar things
look similar; dissimilar things look dissimilar; inconsistency forces the reader
to decide whether the difference is intentional). Symptom of this pattern being
present: identifiers read as domain nouns and verbs, and the same concept wears
the same name everywhere it appears. Test: can a reviewer
read each identifier cold and name the domain concept it represents, without
reading surrounding code?

**I3. Functions do one thing at one level of abstraction.**
A function that validates its inputs, transforms a data structure, calls an
external service, and logs the result is not doing one thing — it is doing at
least four, and it is doing them at mixed levels of abstraction (Martin, "Clean
Code" [2]: functions that do more than one thing are scope problems, not length
problems; a long function is evidence that one level of abstraction was not
maintained throughout). The implementation-level signal is the paragraph test:
if descriptive comments would naturally divide the function body into paragraphs,
each paragraph should be its own function. Mixed abstraction levels — one line
calling a domain verb like `classify_intent()` followed immediately by a line
manipulating a raw dict key — indicate that the function is operating at two
levels simultaneously. Symptom of this pattern being present: each function reads
as a sequence of calls at one level of abstraction, and its name fully describes
its body without an "and." Test: can the reviewer write a single-sentence
description of what this function does without using the word "and"?

**I4. Error handling is a first-class concern, not an afterthought.**
An implementation that handles the happy path and leaves error cases to
propagate upward unmodified has an unspecified contract for callers: they cannot
distinguish a domain error from a programming error from an infrastructure
failure (Martin, "Clean Code" [2]: functions that return error codes mixed with
domain values conflate two concerns; error handling is a behavior of its own).
Named error paths — the tool outputs "no active context" when none is found; the
gatekeeper emits "borderline" rather than raising — are part of the specification
and should be as intentional as success paths. Nygard ("Release It!") [5] adds a
production constraint: every integration point is a potential failure; an
implementation that calls an external service without a timeout or a bounded
retry limit has not been implemented for the failure profile of the environment
it will run in. Symptom of this pattern being present: each named failure mode has
its own deliberate code path and output, and every integration point carries an
explicit timeout and bounded retry. Test: for each error case the design names,
is there an explicit code path that produces the named output, or does the error
path fall through to whatever the underlying library happens to emit?

**I5. Implementation has seams at the right level for testing and variation.**
A seam is a place where behavior can be altered without editing that place
(Feathers, "Working Effectively with Legacy Code" [6]). An implementation that
instantiates its own dependencies — constructs a database connection, spawns a
subprocess, reads a live file — inside a function that also encodes business
logic has no seam: the business logic and the infrastructure are fused, and the
only way to test the logic is to provide the real infrastructure. The right seam
is the same boundary the design identified as the component boundary. A test
that reaches into internals is at the wrong seam; a test that plugs into the
port the design defined is at the right seam (Freeman, Pryce [1]: the test harness
should plug into the port, not the adapter; implementation testable only through
the adapter has no port). Symptom of this pattern being present: dependencies enter
through parameters or an injected port rather than being constructed inside the
logic, and tests plug into that port without touching real infrastructure. Test:
can the business logic of this component be unit-tested without network access,
filesystem access, or spawning a process?

**I6. Duplication is knowledge duplication, not text duplication.**
Two functions that share three lines of string manipulation are not necessarily
a DRY violation. Two functions that independently encode the same business rule
— the same set of valid state transitions, the same classification thresholds,
the same retry budget — are, regardless of whether the text is identical (Hunt,
Thomas, "The Pragmatic Programmer" [7]: DRY is about knowledge, not text; two
places that must be kept in sync manually because they encode the same business
rule are a DRY violation even if they share no characters). The implementation
signal is: if the business rule changes, how many places must be updated? One
is the target; more than one is a DRY violation. The converse is also true:
accidental text similarity that does not represent the same business rule should
not be collapsed into a shared function, because a future change to one rule
will incorrectly propagate to the other. Symptom of this pattern being present:
each business rule has exactly one authoritative location, while merely
text-similar code that encodes different rules is left separate. Test: for each
place this PR adds or modifies business logic, is there exactly one location that
encodes it?

**I7. Comments explain why, never what.**
A comment that says "iterate over the results and emit an event for each one"
is noise: the code already says that. A comment that says "GitHub's API
paginates review comments and review bodies separately; this loop merges them
because the inline comment thread ID only appears in the comments endpoint, not
the review summary" is signal: it names an external constraint, a non-obvious
invariant, or a workaround for a third-party bug that cannot be derived from
reading the code alone (Martin, "Clean Code" [2]: comments that explain what well-
named code already shows are a symptom that the code was not well-named;
comments that explain why a constraint exists are irreplaceable documentation).
A function with many what-comments and no why-comments either has naming
problems (the what-comments are compensating) or has no interesting constraints
(acceptable for simple utility code). Symptom of this pattern being present:
comments in the diff name external constraints, non-obvious invariants, or
third-party workarounds, and there are no comments that merely restate what the
code already says. Test: for each comment in the
diff, does it reveal information that cannot be recovered by reading the code,
or is it restating what the code already shows?

**I8. Variable and predicate names describe semantic content, not shape.**
`result`, `data`, `items`, `flag`, and `temp` describe the variable's role in
the implementation machinery, not its meaning in the domain. A boolean condition
that requires a comment — or a mental model of the surrounding state — to
evaluate correctly should be extracted into a named predicate that states the
condition's meaning (McConnell, "Code Complete" [8]: a variable should describe its
semantic content; a boolean expression too complex to read at a glance should be
extracted into a named function that makes the truth condition legible). The
implementation-level signal is: can a reviewer read the condition in an `if`
statement cold and state in plain English what must be true for the branch to
execute, without reading the variable's assignment site? When the unclear name
is also an untyped primitive standing in for a domain concept, that is Primitive
Obsession (Fowler, "Refactoring" [9]), addressed under AP8. Symptom of this pattern
being present: variables are named for their domain meaning rather than their
shape, and complex conditions are hoisted into named predicates that read as
plain assertions. Test: does each boolean condition read like a
declarative statement of what is true, or does it read like a sequence of
bit-level tests?

**I9. The implementation is orthogonal — a change scoped to one module stays
there.**
Orthogonality at the implementation level means that a change to one module's
behavior does not require coordinated edits in unrelated modules (Hunt, Thomas,
"The Pragmatic Programmer" [7]: an orthogonal change touches a number of files
proportional to the logical scope of the change, not to the total size of the
system). The implementation-level symptom is Shotgun Surgery (Fowler,
"Refactoring" [9]): a single logical change requires many small edits scattered
across many classes, indicating that the responsibility is not localized. The
dual smell is Divergent Change: one class changes for multiple unrelated reasons,
indicating that two responsibilities have been collocated. Neither is visible
from a single file; both require scanning the change set as a whole to recognize.
Symptom of this pattern being present: a single logical change touches a number
of files proportional to its logical scope, and no module in the change set is
edited for a reason unrelated to that change. Test: for each module touched in
this PR, is the reason for the touch
the same logical change, or are there modules touched for different reasons that
should have been in separate PRs (Humble, Farley, "Continuous Delivery" [10]: a
commit that bundles unrelated changes is harder to review, bisect, and revert)?

**I10. Assertions and error handling are used for the right class of failure.**
An assertion communicates "this cannot happen if the program is correct" —
it is a programmer-error check, and violating it should halt execution loudly
(McConnell, "Code Complete" [8]: defensive programming distinguishes pre/post
condition violations, which are programmer errors and should assert-crash, from
expected runtime errors, which are environmental and should be handled
gracefully). Catching an `AssertionError` and returning a default value, or
using an assertion to guard user input, conflates the two categories and produces
a system that swallows bugs silently. Ousterhout ("A Philosophy of Software
Design") [11] adds the complementary principle: rather than adding error handling for
a case that should not arise, redesign so the case cannot arise; implementation
that adds defensive checks for states the design has already ruled impossible is
adding complexity, not safety — the correct response is to audit the design, not
to add a guard. Symptom of this pattern being present: assertions guard
programmer-error invariants and crash loudly, while environmental failures are
caught and handled — and neither category is used to do the other's job. Test:
for each error handler in the diff, is the failure it catches an environmental
error (network, filesystem, user input) or a programmer error (violated
precondition, broken invariant)?

**I11. The implementation builds a thin end-to-end slice before widening.**
A PR that implements a wide slice of one layer — all parsing, all validation, all
schema definitions — without any end-to-end path through the system is not
delivering value that can be observed or tested in context (Hunt, Thomas, "The
Pragmatic Programmer" [7]: a tracer bullet builds the thinnest possible end-to-end
path first so feedback is immediate; a broad slice of one layer defers integration
feedback to a later PR). The implementation-level signal is: after this PR merges,
can the behavior it introduces be exercised in the running system by any real
use case, however simple? If not, the PR has widened a layer without connecting
it to the observable behavior the design called for. This is related to but
distinct from the design-layer scope question: a well-scoped implementation can
still be non-traceable if it delivers the wrong slice of a correctly scoped
problem. Symptom of this pattern being present: after the PR merges, at least one
real use case can drive the new behavior end-to-end through the system boundary,
however thin the slice. Test: is there a test — or a manual invocation — that
exercises the new code end-to-end through the system boundary, not just at the
unit level?

**I12. The implementation reaches for an existing idiom, library, or internal
utility before writing bespoke code (prior-art set: P12 / D12 / DS12 / T12 / I12).**
This is the implementation-layer member of the cross-layer prior-art set: where
the design layer asks "is there a reference architecture to adopt?" (DS12), the
implementation layer asks "is there an existing idiom, library, or internal
helper to call?" Before a code path hand-rolls retry-with-backoff, argument
parsing, date math, URL construction, or a data structure, the question is
whether the language's standard library, an already-vetted third-party
dependency, or an existing internal helper already solves it (Hunt, Thomas, "The
Pragmatic Programmer" [7]: reuse existing, tested code rather than writing your own,
because the existing code has already paid down the bugs the reimplementation
will have to re-discover). The
strongest version of this is repository-local: the same project almost always
has a shared helper (in `goodies-lib.sh`, here `safe_link`, `path_append`,
`ensure_dir`, logging) that the new code should call instead of re-implementing.
Reusing a tested idiom inherits its edge-case handling for free; a bespoke copy
re-discovers the same edge cases the hard way. Symptom of this pattern being
present: new code calls into the standard library or an existing project helper
for mechanics, reserving handwritten logic for the genuinely novel domain part.
Test: for each non-trivial mechanism this PR implements by hand, did the author
check whether the stdlib, an existing dependency, or an internal helper already
provides it — and is there a reason the existing option was rejected?

## Anti-patterns (signs the layer is unsettled)

**AP1. Implementation finding that's actually a higher-layer issue.**
A Copilot finding that says "this code has no path for handling a headerless
comment at the problem layer" is stated as an implementation gap. But if the
design says the tool infers the layer for headerless comments, the finding is
actually asking "is the inference good enough?" — which is a design-layer question
about the adequacy of the contract, not a code-level question about a missing
branch (Feathers [6]: the right seam for a design question is the design layer;
patching code without revisiting the design fixes the symptom while leaving the
cause open). Recognizing this mismatch is the primary value a human reviewer adds
at the implementation layer: automated tools can detect the missing branch;
they cannot determine whether the branch was intentionally absent because the
design prohibits that input, or absent because the design has a gap. Symptom:
the finding proposes a code-level fix for a case that the design doc does not
mention. Test: before fixing, ask — is the design silent on this case,
or does it explicitly state what should happen? If silent, the design layer must
be settled first.

**AP2. Inconsistency that reflects an unsettled design choice.**
"Step 3 uses `--jq '.[]'` but Step 2 uses `--jq '[.[]]'`" looks like an
implementation inconsistency (Boswell, Foucher [4]: similar things should look
similar; dissimilar things should look dissimilar; gratuitous inconsistency
forces the reader to decide whether the difference is intentional). But if both
patterns appear in the same codebase and neither is clearly wrong, the
inconsistency may indicate that the design never settled whether paginated results
should be streamed or collected — and two contributors made independent choices
that were never reconciled. The implementation fix is trivial; the design
clarification is the value a human reviewer provides. Symptom: two similar code
paths use visibly different idioms for what appears to be the same operation,
with no comment explaining why they differ. Test: is this a style
inconsistency (fix it) or evidence that two design choices were made independently
for the same concern (escalate to the design layer)?

**AP3. Dead code that reflects a design revision not recorded.**
Unused variables, commented-out logic, vestigial feature flags, and Lazy Classes
(Fowler, "Refactoring" [9]: a class that doesn't do enough to justify its existence)
accumulate when design changes aren't fully traced to implementation. As a
cleanup issue, dead code should be deleted — git history is the recovery path,
not in-place comments (Feathers [6]: code kept "just in case" is state with no
contract; delete it). At the design layer, dead code may indicate a direction or
trade-off that changed without a record: code that was written to implement a
design decision and then abandoned is evidence that the decision was revisited,
which should be reflected in the design doc. Symptom: a code path that is
unreachable, a class with no callers, or a flag that is always the same value.
Test: if this code were deleted today, would any test fail? If not, is
there a design-layer reason the code exists (a decision in flight, an interface
commitment), or is it pure accumulation?

**AP4. Scope creep visible only in the implementation.**
A feature that appears only in the code — never in the design doc, the trade-off
record, or the commit message — was not reviewed at the layers that matter.
Speculative Generality (Fowler, "Refactoring" [9]: YAGNI — infrastructure for
hypothetical future requirements that no current use case exercises) is the most
common form: a generic registry is built when one concrete instance exists; a
plugin system is added when two variants are known; a configuration knob is
exposed when it will always be the same value in practice. The implementation-
level signal is a component that has no corresponding entry in the problem
statement, design doc, or trade-off discussion. (When the speculative
abstraction *was* deliberately chosen at the design layer, the over-engineering
judgment lives there — design AP10; AP4 is specifically the case where the
mechanism appears only in code and was never reviewed.) Symptom: the PR description
says "add X support" but the implementation includes a full extension mechanism
with a registry, a schema, and a loader — none of which were described in the
design. Test: for each abstraction introduced, is there a corresponding
design-layer discussion about why a general mechanism is needed rather than a
direct implementation?

**AP5. Feature Envy and Inappropriate Intimacy signal a misplaced responsibility.**
Feature Envy (Fowler, "Refactoring" [9]) occurs when a method uses another class's
data more than its own — it is a signal that the method belongs in the other
class. Inappropriate Intimacy occurs when two classes know too much about each
other's internals — accessing private fields directly, depending on internal
ordering, or calling implementation methods rather than interface methods. Both
are implementation-level smells that point to a design-layer problem: the
responsibility boundary between the two modules was drawn in the wrong place.
The implementation fix (move the method, extract an interface) is mechanical; the
design question (why does this module own this responsibility if another module
uses it more?) is the value a human reviewer surfaces. Symptom: a method whose
body consists mostly of calls to another class's getters, or a class that directly
accesses another class's private attributes. Test: if this method were
moved to the class whose data it uses, would the calling class become simpler?

**AP6. Conway's Law in the implementation — boundaries follow team structure,
not domain structure.**
An implementation that splits a single logical operation across files or modules
that correspond to team ownership boundaries — rather than domain capability
boundaries — will drift back toward the org chart regardless of the intended
architecture (Conway's Law [12]: systems mirror the communication structure of the
organizations that build them). The implementation signal is a class or module
whose name encodes a team's identity ("platform-utils", "infra-helpers",
"review-team-shims") rather than a domain concept. These boundaries survive
org chart stability and break under reorgs; domain-capability boundaries survive
reorgs and break only when the domain itself changes. A deeper form of this
smell is when the component boundary matches the communication overhead of the
team that built it, not the logical cohesion of the concept it encodes (Hunt,
Thomas [7]: orthogonality means changes propagate in proportion to logical scope;
team-topology boundaries concentrate changes in proportion to team surface area).
Symptom: a module or class is named for a team or org unit ("platform-utils",
"review-team-shims") rather than a domain capability, and a single logical
operation is split to follow ownership lines instead of cohesion. Where design
AP6 catches a design that *requires* cross-team coordination, this entry catches
the code-level residue — team-named modules and ownership-driven splits — that
appears even when the design itself was sound. Test: for each
module boundary in this PR, can the reviewer name the domain concept it
encapsulates — or does the name only make sense in terms of the team or
infrastructure layer that produced it?

**AP7. Tactical shortcuts accumulate strategic debt.**
An implementation full of quick workarounds — hardcoded string comparisons where
a predicate would do, raw dict access where a typed value would encode the
invariant, a try/except that swallows all exceptions because the specific ones
were not investigated — is tactical programming (Ousterhout, "A Philosophy of
Software Design" [11]: tactical programming makes things work now; strategic
programming makes things right so future changes are cheap; a system built
entirely tactically has the worst complexity-per-feature ratio). Each individual
shortcut is defensible in isolation; the accumulation is the problem. The
implementation-level signal is density: how many of these appear in a single
PR, in a single file, in a single function? A PR that introduces three tactical
shortcuts and no strategic investment is adding complexity faster than the feature
justifies. Symptom: the PR contains multiple instances of raw primitive access,
unnamed boolean conditions, broad exception handling, and magic literals — all
in code that is not marked as a known compromise. Test: is each tactical
shortcut named (via a comment, a TODO, or a tracking issue) as a known debt item,
or has it been introduced without acknowledgment?

**AP8. Data Clumps that should be encapsulated as value objects.**
When the same group of fields — say, `host`, `port`, and `timeout` — appears
together as parameters in multiple function signatures, or as a cluster of
variables that are always assigned and read together, the group is a Data Clump
(Fowler, "Refactoring" [9]) and should be encapsulated as a value object or named
tuple. The implementation-level symptom is a function with five or more
parameters where three of them always travel together, or a class with ten
fields where a named sub-group would encode the domain concept more directly
(Martin, "Clean Code" [2]: a function with many parameters is a scope problem — most
multi-parameter functions are encoding an implicit object whose fields are the
parameters; the object should be named). The value is not DRY: it is that the
value object can carry its own invariants, be named in the domain vocabulary, and
be passed as a unit. Primitive Obsession (Fowler [9]) is the adjacent smell: using
a raw string to represent an event type, a raw integer to represent a timeout,
or a raw dict to represent a structured record — all cases where a named type
would encode the constraints and make the code self-documenting. Symptom: the
same group of fields appears together across multiple signatures or as a cluster
of always-co-assigned variables, or a function takes five or more parameters
where three always travel together. Test:
for each cluster of parameters or fields that always appear together, is there a
named type that could represent the cluster and enforce its invariants?

**AP9. Bespoke reimplementation of a solved problem (Not-Invented-Here).**
A PR that hand-rolls something the ecosystem already solves — a custom argument
parser instead of the stdlib one, a homegrown retry loop instead of a vetted
backoff utility, a manual JSON walk instead of `jq`/a schema library, or a
duplicate of an existing internal helper — is paying full maintenance cost for a
problem someone has already debugged (Hunt, Thomas, "The Pragmatic Programmer" [7]:
reusing existing tested code avoids re-discovering its bugs; rewriting it imports
all the edge cases the original already handles). The give-away is the absence of
a prior-art check: no commit message, comment, or PR note explains what existing
option was considered and why it was rejected, which means the alternatives were
never searched for. Bespoke code is justified only when the existing option is
genuinely unfit (wrong license, missing a required capability, too heavy a
dependency) — and that justification belongs in the PR, not in the reviewer's
imagination. Symptom: the diff contains generic plumbing (parsing, retry, path
manipulation, pagination) written from scratch alongside a standard library or
project helper that already does it, with no rationale for the duplication. Test:
for this reimplemented mechanism, can the author name the existing library or
internal utility they evaluated and state the concrete reason it was insufficient
— or was no search done?
