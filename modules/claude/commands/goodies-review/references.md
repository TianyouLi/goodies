# goodies-review — references

Full citations for the sources marked `[n]` inline across the layer guidance
files (`layers/problem.md`, `layers/direction.md`, `layers/design.md`,
`layers/tradeoff.md`, `layers/implementation.md`). Each inline `[n]` resolves to
the correspondingly
numbered entry **within that layer's section** below — numbering restarts at
`[1]` for each layer, and a source cited more than once in a layer reuses its
number.

**This file is reference material for human readers — it is NOT loaded during
`--engage`.** The runtime only `cat`s the per-layer file for the layer being
engaged, so keeping the bibliography separate keeps the loaded context lean.
Each layer file links here so a reader following an inline `[n]` can resolve it.

- [Problem layer](#problem-layer)
- [Direction layer](#direction-layer)
- [Design layer](#design-layer)
- [Tradeoff layer](#tradeoff-layer)
- [Implementation layer](#implementation-layer)

---

## Problem layer

1. **IEEE 830 / Wiegers** — IEEE Std 830-1998, *Recommended Practice for Software
   Requirements Specifications*; Karl Wiegers & Joy Beatty, *Software
   Requirements* (3rd ed., 2013). Well-formed, traceable, unambiguous
   requirements.
2. **Reinertsen** — Donald G. Reinertsen, *The Principles of Product Development
   Flow* (2009). Work without a traceable valued outcome is waste; cost of delay;
   frequency vs. severity.
3. **JTBD** — "Jobs to be Done" framing: situation + motivation + desired outcome.
   See Christensen, *Competing Against Luck* (entry 12).
4. **Shape Up** — Ryan Singer, *Shape Up* (Basecamp, 2019). "Appetite" — bounding
   how much solving a problem is worth.
5. **Specification by example / BDD** — Gojko Adzic, *Specification by Example*
   (2011); Cucumber/BDD practice. Abstract claims grounded in runnable instances;
   stated boundaries.
6. **Meadows** — Donella H. Meadows, *Thinking in Systems: A Primer* (2008).
   Symptom-level fixes that ignore structure regenerate the problem.
7. **Goldratt** — Eliyahu M. Goldratt, *The Goal* (1984) / Theory of Constraints.
   The bottleneck whose removal yields the largest downstream improvement.
8. **Moore** — Geoffrey A. Moore, *Crossing the Chasm* (1991) and the "Whole
   Product" model. Early-adopter vs. mainstream scope; ecosystem gaps vs. feature
   gaps.
9. **Chesterton's Fence** — G. K. Chesterton, *The Thing* (1929). Do not remove a
   fence until you know why it was put there.
10. **Hunt & Thomas** — Andrew Hunt & David Thomas, *The Pragmatic Programmer*
    (1999). DRY applies to knowledge, not just code.
11. **Cynefin** — Dave Snowden, the Cynefin framework. Complicated
    (expert-knowable) vs. complex (only-knowable-in-retrospect) problems.
12. **Christensen** — Clayton M. Christensen et al., *Competing Against Luck*
    (2016). Jobs validated only through the inventor's own use may be absent for
    the mainstream.

## Direction layer

1. **Nygard (ADRs)** — Michael Nygard, "Documenting Architecture Decisions"
   (2011). An ADR records the decision *and* the rejected options; superseded
   ADRs exist because directions get retried.
2. **Duke** — Annie Duke, *Thinking in Bets* (2018). Make the bet explicit; name
   the odds and what would update it.
3. **Raymond** — Eric S. Raymond, *The Art of Unix Programming* (2003). Separate
   policy from mechanism.
4. **Martin (Clean Architecture)** — Robert C. Martin, *Clean Architecture*
   (2017). Policy vs. detail.
5. **Ackoff** — Russell L. Ackoff, *The Art of Problem Solving* (1978).
   Dissolve / solve / resolve / absolve; shared framing before options.
6. **Rogers** — Everett M. Rogers, *Diffusion of Innovations* (1962). Adoption
   cost is a direction-level concern.
7. **Wardley** — Simon Wardley, Wardley Mapping. Match investment strategy to a
   component's evolutionary stage (genesis / custom / product / commodity).
8. **Snowden (Cynefin)** — Dave Snowden, the Cynefin framework. Safe-to-fail
   probes in complex domains.
9. **Christensen (Innovator's Solution)** — Clayton M. Christensen & Michael
   Raynor, *The Innovator's Solution* (2003). Sustaining vs. disruptive — different
   evaluation frameworks.
10. **Forsgren, Humble, Kim** — Nicole Forsgren, Jez Humble, Gene Kim,
    *Accelerate* (2018). The four key delivery metrics (lead time, deploy
    frequency, change-fail rate, MTTR).
11. **Evans (DDD)** — Eric Evans, *Domain-Driven Design* (2003). Strategic design
    at bounded-context boundaries; integration patterns (conformist,
    anti-corruption layer, open host).
12. **Bezos** — Jeff Bezos, 2016 Amazon shareholder letter. Type 1 (one-way door)
    vs. Type 2 (two-way door) decisions.
13. **Reinertsen** — Donald G. Reinertsen, *The Principles of Product Development
    Flow* (2009). Cost of delay as the go/no-go baseline.
14. **Meadows** — Donella H. Meadows, *Thinking in Systems* (2008). Second-order
    and systemic effects; feedback loops.
15. **Poppendieck** — Mary & Tom Poppendieck, *Lean Software Development* (2003).
    Decide at the last responsible moment.
16. **Sobek / Ward** — Durward Sobek & Allen Ward, set-based concurrent
    engineering. Hold a set of options until the data narrows it.
17. **Goodhart's Law** — when a measure becomes a target it ceases to be a good
    measure.
18. **Harris & Tayler** — Michael Harris & Bill Tayler, "Don't Let Metrics
    Undermine Your Business," *HBR* (2019). Surrogation — substituting the metric
    for the goal.
19. **Staw** — Barry M. Staw, "Knee-Deep in the Big Muddy" (1976). Escalation of
    commitment to a failing course of action.

## Design layer

1. **Evans (DDD)** — Eric Evans, *Domain-Driven Design* (2003). Bounded contexts
   as the unit of carve; ubiquitous language.
2. **Postel's Law** — the robustness principle: be conservative in what you
   produce, liberal in what you accept.
3. **OCP** — Open/Closed Principle (Bertrand Meyer; popularized by Robert C.
   Martin). Open for extension, closed for modification.
4. **Feathers** — Michael Feathers, *Working Effectively with Legacy Code* (2004).
   A seam is a place where behavior can be altered without editing that place.
5. **Martin (Clean Architecture)** — Robert C. Martin, *Clean Architecture*
   (2017). The dependency rule: dependencies point inward toward policy.
6. **Cockburn** — Alistair Cockburn, "Hexagonal Architecture" (Ports and
   Adapters).
7. **Ousterhout** — John Ousterhout, *A Philosophy of Software Design* (2018).
   Deep vs. shallow modules; designing for an imagined future as over-engineering.
8. **CQRS / Event Sourcing** — Greg Young, Udi Dahan et al. Append-only event
   sequence makes state lifetime and ordering legible.
9. **Hunt & Thomas** — Andrew Hunt & David Thomas, *The Pragmatic Programmer*
   (1999). Orthogonality — systems change in proportion to the change being made.
10. **Meadows** — Donella H. Meadows, *Thinking in Systems* (2008). A feedback
    loop with unmodeled delay is a design defect.
11. **Meyer (CQS)** — Bertrand Meyer, Command-Query Separation.
12. **Nygard (Release It!)** — Michael Nygard, *Release It!* (2007). Stability
    patterns (timeout, circuit breaker, bulkhead, fallback); at-least-once
    delivery and idempotency.
13. **Richards & Ford** — Mark Richards & Neal Ford, *Fundamentals of Software
    Architecture* (2020). Architecture-style catalog; ranking architectural
    characteristics.
14. **Ford, Parsons, Kua** — Neal Ford, Rebecca Parsons, Patrick Kua, *Building
    Evolutionary Architectures* (2017). Fitness functions as objective measures of
    architectural characteristics.
15. **Hyrum's Law** — with enough consumers, every observable behavior of an
    interface becomes a de facto contract.
16. **Minsky** — Yaron Minsky, "Effective ML" / "Making Illegal States
    Unrepresentable" (2011). Push constraints into the data model.
17. **Newman** — Sam Newman, *Building Microservices* (2015). Capability
    boundaries vs. technical layers; premature decomposition pays the distribution
    tax.
18. **LSP** — Liskov Substitution Principle (Barbara Liskov). Subtypes
    substitutable without changing program correctness.
19. **ISP** — Interface Segregation Principle. Clients should not depend on
    methods they do not use.
20. **Conway's Law** — Melvin Conway (1968). Systems mirror the communication
    structure of the organizations that build them.
21. **Evans & Fowler (Specifications)** — the Specification pattern: business
    rules as first-class, composable, independently testable predicates.
22. **Spolsky** — Joel Spolsky, "The Law of Leaky Abstractions" (2002).
23. **Fowler (MonolithFirst)** — Martin Fowler, "MonolithFirst" (2015). Start
    with a modular monolith; split only when a real boundary asserts itself.

## Tradeoff layer

1. **Brooks** — Fred Brooks, "No Silver Bullet" (1986). Essential complexity is
   irreducible; design choices relocate it, not eliminate it.
2. **Kahneman** — Daniel Kahneman, *Thinking, Fast and Slow* (2011). WYSIATI
   ("what you see is all there is"); anchoring.
3. **Duke** — Annie Duke, *Thinking in Bets* (2018). Name what would update the
   bet; the resulting fallacy (judge the reasoning, not the outcome).
4. **Snowden (Cynefin)** — Dave Snowden, the Cynefin framework. Safe-to-fail probe
   vs. irreversible bet.
5. **Bezos** — Jeff Bezos, 2016 Amazon shareholder letter. One-way vs. two-way
   doors.
6. **Poppendieck** — Mary & Tom Poppendieck, *Lean Software Development* (2003).
   Defer commitment; the cost of an irreversible decision is the value of the
   options it eliminates.
7. **Hyrum's Law** — with enough consumers, every observable behavior of a
   contract is depended upon; foundation-level surfaces ossify faster than authors
   expect.
8. **Reinertsen** — Donald G. Reinertsen, *The Principles of Product Development
   Flow* (2009). Cost of delay; batch-size trade-offs.
9. **Meadows** — Donella H. Meadows, *Thinking in Systems* (2008).
   Efficiency-vs-resilience; policy resistance.
10. **Ackoff** — Russell L. Ackoff. A system is the product of its parts'
    interactions, not their sum.
11. **Goldratt** — Eliyahu M. Goldratt, *The Goal* (1984). Throughput accounting
    vs. local cost accounting.
12. **Opportunity cost** — classical economics: the cost of a choice is the value
    of the best alternative foregone.
13. **Forsgren, Humble, Kim** — *Accelerate* (2018). Speed and stability are not
    in tension for high performers.
14. **Cunningham** — Ward Cunningham, the technical-debt metaphor (1992).
    Deliberate, named shortcuts with a repayment plan.
15. **Larson** — Will Larson, *An Elegant Puzzle* (2019). Durable decisions are
    recorded so they are not relitigated from scratch.
16. **CAP theorem** — Eric Brewer. Consistency / availability / partition
    tolerance.
17. **Conway's Law** — Melvin Conway (1968). A cost moved across a module boundary
    lands on the team that owns it.
18. **Taleb** — Nassim Nicholas Taleb, *The Black Swan* (2007), *Antifragile*
    (2012). Avoid ruinous tails even at higher expected value.
19. **Ainslie** — George Ainslie, *Picoeconomics* (1992). Hyperbolic discounting:
    near-term outcomes weighted far more heavily than distant ones.
20. **Arkes & Blumer** — Hal Arkes & Catherine Blumer, "The Psychology of Sunk
    Cost" (1985). Sunk-cost fallacy.
21. **Samuelson & Zeckhauser** — William Samuelson & Richard Zeckhauser, "Status
    Quo Bias in Decision Making" (1988).
22. **Wason** — Peter Wason, "On the Failure to Eliminate Hypotheses" (1960).
    Confirmation bias.
23. **McNamara fallacy** — named for Robert McNamara; articulated by Daniel
    Yankelovich. Treating the measurable as important rather than making the
    important measurable.
24. **YAGNI** — "You Aren't Gonna Need It," attributed to Ron Jeffries (Extreme
    Programming).
25. **Fowler (Refactoring)** — Martin Fowler, *Refactoring* (1999; 2nd ed. 2018).
    "Speculative generality" as a code smell.

## Implementation layer

1. **Freeman & Pryce** — Steve Freeman & Nat Pryce, *Growing Object-Oriented
   Software, Guided by Tests* (2009). Test/implement at the seam the design names;
   plug into the port, not the adapter.
2. **Martin (Clean Code)** — Robert C. Martin, *Clean Code* (2008). A name that
   needs a comment failed; functions do one thing at one level of abstraction;
   error handling as a first-class concern.
3. **Evans (DDD)** — Eric Evans, *Domain-Driven Design* (2003). Ubiquitous
   language; consistent domain naming.
4. **Boswell & Foucher** — Dustin Boswell & Trevor Foucher, *The Art of Readable
   Code* (2011). Similar things look similar; dissimilar things look dissimilar.
5. **Nygard (Release It!)** — Michael Nygard, *Release It!* (2007). Every
   integration point is a potential failure; timeouts and bounded retries.
6. **Feathers** — Michael Feathers, *Working Effectively with Legacy Code* (2004).
   Seams; delete kept-just-in-case code (git history is the recovery path).
7. **Hunt & Thomas** — Andrew Hunt & David Thomas, *The Pragmatic Programmer*
   (1999). DRY (knowledge, not text); orthogonality; tracer bullets; reuse tested
   code.
8. **McConnell** — Steve McConnell, *Code Complete* (2nd ed., 2004). Semantic
   variable names; named predicates; assertions for programmer errors vs. handling
   for environmental errors.
9. **Fowler (Refactoring)** — Martin Fowler, *Refactoring* (1999; 2nd ed. 2018).
   Code smells: Primitive Obsession, Shotgun Surgery, Divergent Change, Lazy Class,
   Feature Envy, Inappropriate Intimacy, Speculative Generality, Data Clumps.
10. **Humble & Farley** — Jez Humble & David Farley, *Continuous Delivery* (2010).
    A commit that bundles unrelated changes is harder to review, bisect, and
    revert.
11. **Ousterhout** — John Ousterhout, *A Philosophy of Software Design* (2018).
    Tactical vs. strategic programming; redesign so an impossible case cannot
    arise rather than guarding it.
12. **Conway's Law** — Melvin Conway (1968). Code-level residue: modules named for
    teams rather than domain concepts.
