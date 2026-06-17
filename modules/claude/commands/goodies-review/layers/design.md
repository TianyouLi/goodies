# Layer 3: design

**The question this layer answers:** Given the direction, are the architectural
choices — carve, contracts, extension points — right?

> Sources named inline below are listed in full in
> [references.md](../references.md#design-layer).

## Patterns (what good looks like)

**DS1. The carve is motivated by the problem's structure.**
Each component boundary should map to a distinct force in the problem: a
different reason to change, a different ownership boundary, or a different
stability horizon (Evans, DDD [1]: bounded contexts are the right unit of design
when a team, a model, or a lifecycle differs across them). A motivated carve
survives the question "what goes wrong if these two things are merged?" — the
answer is a concrete failure mode, not a vague discomfort. An unmotivated carve
is one where merging would produce no regression in behavior or evolvability.
Symptom of this pattern being present: for each boundary, a reviewer can state a
concrete failure mode (a shared change reason, an ownership conflict, a coupled
release cadence) that merging the two sides would reintroduce. Test: can the
reviewer name what breaks if the component boundary is removed?

**DS2. Component contracts are explicit about what is guaranteed, not just what
is produced.**
A contract names three things: what the component receives (input preconditions),
what it emits (output postconditions), and what it guarantees on failure
(error contract). "Emits a JSON object with a `status` field" is a production
description; "emits a JSON object whose `status` field is always one of the
enumerated vocabulary strings, or raises `ContractError`" is a contract (Postel's
Law [2]: be conservative in what you produce, liberal in what you accept; the
conservative side of a contract is what downstream can rely on). A design whose
boundary specifications are only production descriptions will couple consumers
to implementation details. Symptom of this pattern being present: each boundary
specification states preconditions, postconditions, and an error contract, and
downstream code is written against those guarantees rather than observed output.
Test: can a downstream component be written using only the contract, without
reading the implementation?

**DS3. Extension points obey the Open/Closed Principle.**
A design identifies which behaviors are framework (stable, closed for
modification) and which are extension (swappable, added without modifying core
code). Layer pattern files, actor registries, and schema vocabularies are good
extension-point candidates because new variants should not require touching the
dispatch logic (Meyer / Martin, OCP [3]: every time core code must be edited to
accommodate a new variant, the extension seam is in the wrong place). A seam
is in the right place when the mechanism for introducing variation is not the
same mechanism as the core behavior (Feathers, "Working Effectively with Legacy
Code" [4]: a seam is a place where behavior can be altered without editing that
place). Symptom of this pattern being present: new variants are added by
dropping in a file or registering an entry, and the core dispatch logic is never
reopened to accommodate them. Test: does adding a new instance of this variation
class require opening any existing file?

**DS4. Dependencies point inward, toward policy and away from detail.**
Stable policy components — business rules, domain logic, orchestration — should
not import volatile detail components such as I/O adapters, external APIs, or
framework-specific types (Martin, "Clean Architecture" [5]: the dependency rule).
When a stable core depends on a volatile edge, a change in the edge forces
revalidation or retesting of the core; the dependency direction embeds that
coupling. Hexagonal architecture names this correctly (Cockburn, "Hexagonal Architecture" [6]):
the core exposes a port (interface); the adapter implements the port; the
dependency arrow points from adapter to port, never from core to adapter. Symptom
of this pattern being present: the import graph shows policy modules importing
only abstractions, while concrete I/O, framework, and external-API types are
imported exclusively by edge adapters. Test: if the infrastructure layer
(database, API client, shell invocation) is replaced, how many files inside the
core policy layer must change?

**DS5. The design uses deep modules, not shallow ones.**
A deep module hides significant complexity behind a small interface; a shallow
module exposes an interface as large as the implementation it wraps, providing
no leverage to callers (Ousterhout, "A Philosophy of Software Design" [7]: interface
complexity is a tax paid by every caller, so a module should hide more than it
exposes). A string-formatting helper wrapped in a class with twelve methods, a
pipeline stage that is pure pass-through, or a service layer that adds no
invariants on top of its backing store are all shallow. The test is the ratio:
how much does the interface surface shrink relative to the implementation the
caller no longer needs to know? A deep module has a favorable ratio; a shallow
module has a ratio near 1. Symptom of this pattern being present: callers invoke
the module through a small, stable interface and rarely need to read its
internals to use it correctly. Test: does the interface surface shrink
substantially relative to the implementation complexity it hides, or is the
interface as wide as the thing it wraps?

**DS6. State is minimized, pushed to the edges, and its lifetime is explicit.**
Stateless components are independently testable, independently restartable, and
reason about independently; every piece of in-process mutable state is a
coupling across invocations that must be understood before any single call can
be analyzed in isolation. State should be pushed to the edges of the system
(event stores, databases, caches) and its persistence contract named explicitly
— what is guaranteed to survive a crash, a restart, a concurrent call
(event sourcing / CQRS [8]: recording state as an append-only event sequence
makes the lifetime and ordering of state changes legible; mutable state loses
the audit trail). Symptom of this pattern being present: most components are pure
functions of their inputs, and the few that hold state name where it lives and
what survives a crash. Test: can each component be killed and restarted mid-flow
without corrupting the system's observable state?

**DS7. The design uses the domain's vocabulary, not a technical one.**
Component names, event names, and contract field names should be terms a domain
expert would recognize, not terms borrowed from the implementation layer (Evans,
DDD [1]: ubiquitous language — if the domain expert calls it a "profiling request"
and the code calls it a "CapabilityInvocationPayload," the design is speaking a
different language than the problem). Vocabulary drift between the problem layer
and the design layer is a warning sign: it means the design was derived from
an implementation intuition, not from the problem structure. Symptom of this
pattern being present: component, event, and field names in the design match the
terms used in the problem statement and by domain experts, with no translation
table required. Test: can a domain expert (not an engineer) read the component
names in a dependency diagram and recognize the concepts they represent?

**DS8. The design is orthogonal — changing one component does not change others.**
Orthogonality means that a change to one component's implementation propagates
to exactly the components that are logically affected, and no others (Hunt,
Thomas, "The Pragmatic Programmer" [9]: orthogonal systems change in proportion to
the change being made; non-orthogonal systems change in proportion to the
system's total size). High coupling concentrates risk; the design should spread
it by ensuring each change has a bounded blast radius. Symptom of this pattern
being present: a change to one component forces re-examination of its direct
dependents only, not of nodes that merely transitively depend on it. Test: draw
the dependency graph — does a change to node X ripple to all transitive
dependents, or only to its direct neighbors?

**DS9. Feedback loops and their delays are accounted for in the design.**
Any design that involves a control loop — retry logic, freshness resolution,
rate limiting, adaptive behavior — should name the feedback signal, the control
action, and the expected delay between action and observation (Meadows, "Thinking
in Systems" [10]: a feedback loop with unmodeled delay is a design defect; the
controller will overshoot because it cannot distinguish "not yet responded" from
"did not respond"). A design that ignores delay produces oscillation under load
and runaway behavior under stress. Symptom of this pattern being present: every
control loop in the design names its signal, its actuator, and the lag before a
correction is observable, so the controller is not blind to in-flight actions.
Test: for each place in the design that takes a remedial action, is there an
explicit statement of when and how the system learns whether the action worked?

**DS10. The design separates command from query.**
Functions that return a value should not change observable state; functions that
change state should not return domain values (Meyer, CQS [11]; amplified in CQRS
at the architectural level: separating command and query models allows each to
be optimized and evolved independently). A component that conflates reads and
writes is harder to test (side effects inside a read), harder to cache (a cached
read may replay a write), and harder to reason about under concurrency. The seam
between command and query paths is also the natural boundary for read replicas,
event projections, and audit logs. Symptom of this pattern being present: each
public method is classifiable at a glance as either a side-effect-free query or a
state-changing command, with no method that does both. Test: for each public
method, is it either a pure query (returns value, no state change) or a pure
command (changes state, returns at most an acknowledgment)?

**DS11. Stability patterns are named at the design layer, not deferred to
runtime.**
Timeout policies, circuit breakers, bulkheads, and fallback strategies are
design decisions that constrain the system's failure surface; discovering them
at runtime means discovering them under incident conditions (Nygard, "Release
It!" [12]: stability patterns are architectural decisions, not operational tuning
knobs — a design that has none is a design that will fail in unpredictable ways
under the production load profile). A design doc that is silent on what happens
when an external dependency is slow, unavailable, or returning garbage has not
been designed for production. Symptom of this pattern being present: the design
doc enumerates each external dependency alongside its timeout, retry, and
fallback policy, and names where circuit breakers or bulkheads bound the failure.
Test: for each external dependency named in the design, is there an explicit
statement of what the calling component does when that dependency fails?

**DS12. The design adopts an established reference architecture before inventing
a bespoke one.**
Most structural problems — request/response, event-driven, pipes-and-filters,
ports-and-adapters, layered, plugin/microkernel — have named reference
architectures with documented forces, trade-offs, and failure modes (Richards,
Ford, "Fundamentals of Software Architecture" [13]: architecture styles are a catalog;
choosing a named style imports its known consequences instead of rediscovering
them). A good design states which established pattern it is an instance of (or
deliberately departs from, and why), so reviewers can reason from the pattern's
known properties rather than from scratch. This is the design-layer prior-art entry (parallel to problem P12, direction D12,
tradeoff T12, implementation I12): before drawing a novel box-and-arrow diagram,
confirm no catalog style already fits, and check whether an internal team has
solved the same structural shape. Symptom of this pattern
being present: the design doc says "this is a microkernel with the layer files as
plugins" rather than presenting an unnamed structure. Test: can the design be
named as an instance of (or principled deviation from) a known architecture
style, and is the deviation justified?

**DS13. Architectural characteristics are named and made testable.**
A design should state which quality attributes it is optimizing for — latency,
throughput, deployability, modifiability, security — and which it is willing to
sacrifice, because no architecture maximizes all of them at once (Richards, Ford,
"Fundamentals of Software Architecture" [13]: you cannot optimize every architectural
characteristic, so the design must rank them explicitly). The strongest designs
encode these as fitness functions — automated checks that fail when a
characteristic regresses, such as a layering test that fails if the core imports
an adapter (Ford, Parsons, Kua, "Building Evolutionary Architectures" [14]: a fitness
function is an objective measure of an architectural characteristic). Symptom of
this pattern being present: the design lists its top two or three "-ilities" and
at least one is guarded by a check, not just prose. Test: which architectural
characteristic does this design prioritize, and what automated or manual check
catches a regression in it?

**DS14. Contracts are designed to evolve, not just to exist.**
A boundary will outlive its first consumer, so the design should state how the
contract changes without breaking callers: which fields are additive-only, what
the deprecation path is, and how versions coexist (Hyrum's Law [15]: with enough
consumers, every observable behavior of an interface will be depended upon, so
even unspecified behavior becomes a de facto contract). Semantic versioning and
explicit compatibility rules (additive change is minor, removal is breaking) turn
contract evolution from an accident into a policy. A design that treats its
interfaces as frozen forfeits the one guarantee that lets producers and consumers
ship on independent cadences. Symptom of this pattern being present: each public
contract states its compatibility policy and a deprecation path, not just its
current shape. Test: how does a consumer survive the next change to this
contract, and is that survival rule written down?

**DS15. Operations crossing an unreliable boundary are designed to be idempotent.**
Any call that can be retried — across a network, a queue, or a restart — will
eventually be delivered more than once, so the receiving side must produce the
same observable effect whether it is applied once or many times (Nygard, "Release
It!" [12]: at-least-once delivery is the default reality of distributed systems, so the
design must make repeated delivery safe rather than assume exactly-once). The
design names the idempotency key (a client-supplied request ID, a natural
business key, or a version precondition) and states how duplicates are detected
and collapsed; absent that, retries silently double-charge, double-send, or
corrupt state. Symptom of this pattern being present: every retryable or
queue-driven operation in the design carries an explicit dedup key and a stated
rule for what a repeated delivery does. Test: if any message or request in the
design is delivered twice, does the system end in the same state as one delivery,
and is the mechanism that guarantees it written down?

**DS16. The design makes illegal states unrepresentable.**
The strongest invariant is one the type system or schema enforces so that an
invalid combination cannot be constructed in the first place, rather than one
checked at runtime and hoped to hold (Minsky, "Effective ML"/"Making Illegal
States Unrepresentable" [16]: pushing constraints into the data model removes whole
classes of bug and defensive checks). A record with `start` and `end` optional
fields admits the illegal "end without start"; a sum type of `Scheduled |
Started{start} | Completed{start,end}` admits only legal shapes. This complements
DS2's contracts: contracts state what callers may rely on, while unrepresentable
illegal states make the reliance structurally true. Symptom of this pattern being
present: the data model has few "this field is only valid when that flag is set"
caveats because such combinations are not constructible. Test: pick a key
invariant — can a caller build a value that violates it, or does the type/schema
make that combination impossible to express?

## Anti-patterns (signs the layer is unsettled)

**AP1. The carve follows technical layers, not business capabilities.**
Splitting a system into "controller / service / repository" layers is a
technical taxonomy, not a domain taxonomy; it tends to produce components that
change together for any business reason, distributing a single logical operation
across three files with no encapsulation of the business invariant (Newman,
"Building Microservices" [17]: boundaries that follow business capabilities survive
organizational change; boundaries that follow technical layers create distributed
monoliths). Symptom: every feature touches all layers; no layer can be
versioned or replaced independently. Test: name one business behavior that can
change by modifying exactly one component.

**AP2. Extension points allow substitution that violates the base invariant.**
An extension point is sound only if every valid implementation satisfies the
contracts the framework assumes. An extension that allows a component to be
substituted with one that violates the base class's postconditions produces
silent correctness failures — the framework's invariants are broken from within
(Liskov Substitution Principle [18]: a subtype must be substitutable without changing
the correctness of programs that use the supertype; an extension seam that
cannot enforce this is an attack surface on the design's invariants). Symptom:
the extension mechanism gives extenders write access to a resource the framework
assumes is under its control. Test: is there a stated set of invariants that
all extensions must preserve, and is that set enforced or at minimum verifiable?

**AP3. Contracts are defined only for the happy path.**
A contract that specifies only the success case leaves consumers free to make
unbounded assumptions about failure behavior — and they will. A component whose
error contract is "throws an exception" rather than "raises `TimeoutError` with
the elapsed duration when the backend takes more than N seconds" forces every
caller to add defensive code for the entire exception hierarchy (Postel's Law
applied to failure [2]: the producer should be conservative about what failure modes
it exposes; consumers should not need to be liberal about interpreting opaque
errors). Symptom: the design doc describes successful interactions in detail and
treats failure as "handled by the caller." Test: could a consumer implement
correct retry and fallback logic using only the stated contract?

**AP4. State is hidden inside components that claim to be stateless.**
A component declared stateless but backed by a module-level cache, a
singleton registry, or a threadlocal is stateful in practice — it just hides the
state from the design. This is worse than declared state because neither the
consumer nor the operator knows when to invalidate it, what consistency
guarantees it offers, or what happens under concurrent access (CQRS / event
sourcing [8]: undeclared state is the hardest kind to manage because it has no
explicit contract and no lifecycle). Symptom: integration tests require careful
ordering or explicit reset calls between cases; unit tests use `monkeypatch` or
module teardown to restore a "clean" state. Test: are all state-holding data
structures named in the design, with their lifetime and consistency guarantees
stated?

**AP5. Interface Segregation is violated — clients depend on methods they don't
use.**
A fat interface forces every implementor to provide methods they don't need and
every caller to understand a surface larger than the capability they require,
creating coupling to irrelevant behavior (Interface Segregation Principle [19]:
a client should not be forced to depend on methods it does not use; a fat
interface is a coupling multiplier). Symptom: the interface has more than five
to seven methods; implementors stub out or `raise NotImplementedError` for
methods they don't care about; adding a new method to the interface breaks
all existing implementors. Test: for each consumer of an interface, are there
methods on that interface the consumer never calls and doesn't care about?

**AP6. Design fights Conway's Law instead of using it.**
A design that requires tight coordination between components owned by different
teams — or that places a single logical capability in a component that spans two
communication boundaries — will drift toward the organizational structure
regardless of the intended architecture (Conway's Law [20]: systems mirror the
communication structure of the organizations that build them). Proposing a
design that requires a team boundary to disappear, or that assumes cross-team
interfaces will be more granular than cross-team communication allows, is a
structural bet against entropy. Symptom: the design doc identifies integration
points that require synchronous agreement between groups with different backlogs
and different review cadences, with no anti-corruption layer or versioning
strategy. Test: does each major component correspond to a team that owns it
end-to-end, or does a single component require multiple teams to coordinate on
every change?

**AP7. Specification logic is embedded inside the entity it validates.**
Business rules about what constitutes a valid domain object should be expressible
and testable independently of the object they govern (Evans & Fowler,
"Specifications" [21]; also in Evans, DDD [1]: a business rule factored into a first-class
object is composable, nameable, and independently testable; embedded in the
entity, it is untestable in isolation and non-composable). Symptom: validation logic is scattered across
constructor bodies and `save()` methods with no way to ask "is this value valid"
without constructing the full object. Test: can each significant business rule
be stated as a named predicate that can be unit-tested with arbitrary inputs,
independently of the persistence or UI layer?

**AP8. The design is silent on production stability.**
A design doc that describes the happy path, the extension points, and the
contracts but says nothing about what happens under load, partial failure, or
degraded dependencies has not been designed for production (Nygard, "Release
It!" [12]: systems that have not been designed to fail gracefully will fail
ungracefully under production conditions; stability patterns are not
operational concerns, they are design concerns). Symptom: the design doc has
no timeout section, no retry policy, no statement of what the system does when
a dependency returns slowly or incorrectly, and no circuit-breaker or bulkhead
boundary identified. Test: can the on-call engineer read the design doc and
understand what the system will do during a 10x latency spike on a single
external dependency?

**AP9. A bespoke architecture is invented with no survey of established patterns
or internal prior art.**
A design that introduces a novel structure without first checking whether a named
architecture style, an open-source reference, or an internal team already solved
the same shape risks rediscovering known failure modes the hard way (Richards,
Ford, "Fundamentals of Software Architecture" [13]: the catalog of styles exists
precisely so teams stop reinventing structures with documented trade-offs). The
cost is not just wasted effort; a bespoke structure forfeits the operational
playbooks, libraries, and reviewer intuition that come free with a recognized
pattern. Symptom: the design doc has a unique vocabulary and an unnamed topology,
and the "alternatives considered" section omits any established pattern or any
mention of how a sibling team handles the same problem. Test: does the design
cite at least one established architecture style or internal precedent it
evaluated, and explain why a custom structure beats adopting it?

**AP10. Extension points are speculative — built for variation that does not yet
exist.**
A seam added "in case we need to swap this later," with only one implementation
and no concrete second use case, pays the abstraction tax — indirection,
interface maintenance, harder navigation — without the leverage (Ousterhout,
"A Philosophy of Software Design" [7]: designing for an imagined future adds
complexity now to serve a payoff that may never arrive; this is over-engineering,
not flexibility). The discipline is to wait until a second concrete variant
forces the abstraction, then let the two real cases shape the seam. Symptom: an
interface, plugin registry, or strategy hierarchy with exactly one
implementation and a comment about hypothetical future ones. Test: for each
extension point, is there a second concrete implementation today (or a committed,
near-term one), or is it justified solely by speculation?

**AP11. The abstraction leaks — callers must know the implementation to use it
correctly.**
A leaky abstraction is an interface that purports to hide a mechanism but forces
callers to understand the hidden mechanism to use it safely — the encapsulation
is nominal, not real (Spolsky, "The Law of Leaky Abstractions" [22]: all non-trivial
abstractions leak to some degree, so the design goal is to minimize how often and
how painfully the underlying detail surfaces). Unlike a shallow module, which is
honest about exposing its internals, a leaky abstraction is dishonest: it presents
a clean facade while requiring out-of-band knowledge (call ordering, error
recovery, performance cliffs) the interface does not state. Symptom: correct usage
requires reading the source, a wiki page, or a senior engineer, because the
interface alone misleads about latency, failure, or required call sequencing.
Test: can a competent consumer use this interface correctly from its signature and
contract alone, or must they first learn how it is built?

**AP12. The carve is too fine — boundaries are drawn before they are forced.**
Decomposing into many small components or services up front, before the domain's
seams are understood, distributes a single logical change across many units and
converts in-process method calls into network calls that must now handle
partial failure, latency, and versioning (Fowler, "MonolithFirst" [23]: start with a
modular monolith and split only when a real boundary asserts itself; Newman,
"Building Microservices" [17]: premature decomposition pays the distribution tax
before earning the autonomy benefit). This is the mirror of AP10: AP10 is a
speculative seam inside a component, AP12 is a speculative seam between
components. The fix is to keep the carve coarse and well-modularized internally
until a concrete force — independent scaling, separate ownership, divergent
release cadence — demands a split. Symptom: a transaction that should be atomic
now spans three services and needs a saga; most "services" are deployed and
versioned together anyway. Test: for each component boundary, is there a force
demanding the split today, or could two components be merged with no loss of
independent scaling, ownership, or release cadence?
