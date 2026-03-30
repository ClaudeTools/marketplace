# The Five-Step Algorithm

> Before you write code, run these steps in strict order. NEVER skip ahead. Each step depends on the one before it.

---

## Step 1: Question the requirement

NEVER accept a requirement at face value. Before touching any file:

1. **Trace it to a real problem.** What specific, observable failure or gap exists right now? If you cannot name one, stop.
2. **Separate problems from solutions.** "Add caching" is a solution. "Page load takes 4 seconds" is a problem. Work from problems, not prescribed solutions.
3. **Challenge necessity.** The best implementation of a wrong requirement is still wrong. If the requirement does not survive scrutiny, push back or clarify before proceeding.

<example>
Requirement: "Add a Redis cache layer for user preferences"
<reasoning>The real problem is slow preference lookups. Before building a cache, check: are preferences already in memory? Is the DB query unindexed? A missing index is a 1-line fix. A cache layer is a new dependency, invalidation logic, and operational burden.</reasoning>
Action: Identify the actual bottleneck before building infrastructure.
</example>

**STOP.** Do not proceed to Step 2 until you know WHY this work matters.

---

## Step 2: Delete

Before adding anything, remove what should not exist.

1. **Delete dead code.** Uncalled functions, unused parameters, unreferenced imports. Dead code is not "insurance" — it is noise that slows comprehension and invites bugs.
2. **Delete dependencies.** Every dependency is a liability. If you use 3 lines from a package, inline them. If the standard library can do it, use the standard library.
3. **Delete abstractions.** A wrapper serving one caller costs more than it saves. Inline it.
4. **Delete indirection.** Every layer between intent and execution is a place for bugs to hide. If data flows through three transformations when one works, delete the other two.
5. **Apply the 10% rule.** Push deletion until something breaks. Add back only what is proven necessary. If you did not add back at least 10% of what you removed, you did not delete enough.

<example>
WRONG: Keep an unused utility function "in case we need it later."
CORRECT: Delete it. Git remembers. If needed later, restore it then.
WHY: Dead code misleads future readers (human and agent) into thinking it is load-bearing. It also creates false dependencies that block refactoring.
</example>

**STOP.** Do not proceed to Step 3 until you have removed everything you can.

---

## Step 3: Simplify

Only after questioning and deleting should you design what remains. Use the lowest tier of complexity that solves the real problem.

1. **Tier 1 — Deterministic.** Can a constant, lookup table, or `if` statement solve it? Use that. Zero overhead.
2. **Tier 2 — Contained logic.** Does it need a function with clear inputs and outputs but no architectural decisions? Write that single function.
3. **Tier 3 — Full complexity.** Does it genuinely require abstractions, interfaces, or multi-component coordination? Only then build that, and justify why Tiers 1-2 are insufficient.

ALWAYS choose the lowest tier that works. Three similar lines of code are better than a premature abstraction.

<example>
WRONG: Create a `DateResolver` class with a strategy pattern to handle "last month", "Q4", and "YTD".
CORRECT: Write three `if` branches that return date ranges. No class needed.
WHY: The strategy pattern is Tier 3 complexity for a Tier 1 problem. The input set is small and known. A lookup or branch handles it with zero abstraction overhead.
</example>

NEVER optimise a thing that should not exist. If Step 2 should have deleted it, go back to Step 2.

**STOP.** Do not proceed to Step 4 until the design is simple.

---

## Step 4: Accelerate

Now that you have a clean, simple design, make each stage serve the next.

1. **Pre-process inputs at the boundary.** Parse dates, validate formats, normalise data once at entry. Downstream code NEVER guesses or re-parses.
2. **Narrow the decision space.** If a downstream step chooses between 30 options and you can narrow to 5 based on known context, do that. Fewer choices mean fewer errors.
3. **Fail fast and fail specifically.** Surface errors at the earliest point with the most specific message. An error at the boundary costs nothing. The same error three layers deep costs hours.
4. **Each function serves its caller.** A function's job is not just to produce output — it is to produce output in the form most useful to whatever consumes it.

<example>
WRONG: Pass raw user input through three layers, then validate at the database query.
CORRECT: Validate and normalise at the API boundary. Downstream functions receive clean, typed data.
WHY: Every layer that touches unvalidated input is a layer that can fail in unexpected ways. Validation at the boundary eliminates an entire class of downstream bugs.
</example>

**STOP.** Do not proceed to Step 5 until the pipeline flows cleanly from input to output.

---

## Step 5: Automate

Automation is the last step, not the first.

1. **Automate what is proven.** If you have done something manually 3+ times and it works every time, automate it. If you have done it once or never, it is not ready.
2. **Do not build frameworks for one use case.** Build the specific thing. If a second use case arrives and genuinely shares structure, refactor then.
3. **Do not add configuration for hypothetical flexibility.** If there is one right answer, hardcode it. Config is for values that legitimately vary between environments, not for avoiding commitment.
4. **ALWAYS automate verification.** The one thing that must be automated: confirming the implementation works. A concrete command or test that produces observable output. "It should work" is not verification.

<example>
WRONG: Build a generic plugin framework before the second plugin exists.
CORRECT: Build the specific plugin. When a second plugin arrives, extract shared structure if it genuinely overlaps.
WHY: Frameworks are bets that future use cases share enough structure to justify shared machinery. That bet is usually wrong. Premature frameworks create constraints that do not match real requirements.
</example>

---

## The sequence is the algorithm

Each step depends on the one before it:

- You cannot delete well without knowing what is actually needed (Step 1).
- You cannot simplify what you have not reduced (Step 2).
- You cannot accelerate a complicated design — only a simple one (Step 3).
- You cannot automate well without a clean pipeline (Step 4).

Skipping ahead produces systems that are fast at the wrong thing, automated around unnecessary complexity, and optimised for requirements nobody has.

**Follow the order. Every time.**
