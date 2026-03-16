# Prompting Principles for Claude Code

Rules applied when transforming raw input into structured prompts. Based on Anthropic's official documentation and Claude 4.6 best practices.

## Hierarchy of impact

From highest to lowest leverage:

1. **Verification + self-check** — Claude performs dramatically better when it checks its own work. Every task needs `<verification>`, every prompt needs a `<check>` block.
2. **Few-shot examples** — The single most effective steering tool. Include `<examples>` for any task involving patterns, transformations, or format decisions. Show the input and the expected output.
3. **Think-then-answer structure** — `<approach>` blocks for reasoning through decisions before implementing. Evidence-first grounding prevents hallucination and over-correction.
4. **Escape clauses** — Give Claude permission to flag contradictions, say "I don't know", or report infeasible requirements. Prevents hallucinated workarounds and silent failures.
5. **Research directives** — Search online and explore the codebase before coding. The cost of verifying is near-zero; the cost of stale assumptions is high.
6. **Task decomposition** — One task per block, sequenced with dependencies.
7. **Concrete specifications** — Numbers, formats, breakpoints, file paths.
8. **Code references** — "Follow the pattern in X" beats describing the pattern.
9. **Data-first ordering** — Put longform data at the top, queries at the end. Up to 30% quality improvement with complex multi-document inputs.
10. **Constraints** — Task-specific constraints that prevent likely failure modes for *this* task. Not generic boilerplate.

## Transformation rules

### Replace adjectives with specifications

| Vague | Concrete |
|-------|----------|
| "responsive" | "Works at 1440px, 1024px, 768px, 375px breakpoints" |
| "fast" | "First contentful paint under 1.5s, no layout shift" |
| "clean code" | "Follow existing patterns in src/components/, extract shared logic to hooks" |
| "good UX" | "Keyboard navigable, ARIA labels on interactive elements, loading states on async actions" |
| "secure" | "Sanitise user input, use parameterised queries, validate on server" |
| "scalable" | "Handle 10k concurrent users" or "Support adding new providers without modifying core logic" |
| "well-tested" | "Unit tests for business logic, integration tests for API routes, >80% coverage on new code" |
| "handle errors" | "Catch at service boundary, log with context (requestId, userId), return typed error responses" |

### Add few-shot examples to pattern tasks

Any task that involves transformation, formatting, classification, or following a pattern benefits from examples. This is the most effective single technique.

```xml
<examples>
  <example>
    <input>user submits form with empty email</input>
    <output>Show inline error "Email is required" below the field, focus the field</output>
  </example>
  <example>
    <input>user submits form with invalid email format</input>
    <output>Show inline error "Enter a valid email address" below the field</output>
  </example>
</examples>
```

When to include examples:
- Input/output transformations (data formatting, API response shaping)
- UI behaviour specification (what happens when X)
- Error handling patterns (which error produces which response)
- Any task where showing is clearer than telling

### Add approach blocks for think-then-answer

Replace the old `<evaluate>` pattern with `<approach>`. The key difference: commit to a decision rather than leaving it open-ended.

```xml
<approach>
  Before implementing, reason through:
  - Which state management approach fits (React context, Zustand, URL state)?
  - Criteria: minimal re-renders, deep-linkable, predictable updates.
  Select an approach and commit to it. Avoid revisiting unless new info contradicts your reasoning.
</approach>
```

### Add escape clauses

Every `<execution>` block should include an escape clause:

```xml
<escape>
  If any requirement seems contradictory, infeasible, or would degrade
  existing functionality — flag it and ask rather than working around it.
</escape>
```

This prevents the common failure mode where Claude silently works around a problem by producing hallucinated or degraded output rather than admitting the constraint is unfeasible.

### Replace aggressive language with calm instructions

Claude 4.6 responds better to calm, direct instructions. Aggressive language causes overtriggering on guardrails and defensive behaviour.

| Instead of | Write |
|------------|-------|
| "You MUST always..." | "Always..." |
| "CRITICAL: Never..." | "Do not..." |
| "This is non-negotiable" | (remove — the instruction itself is sufficient) |
| "NEVER do X under ANY circumstances" | "Do not do X" |
| "IMPORTANT: You MUST..." | State the instruction directly |
| "There are NO exceptions" | (remove — if there are exceptions, address them) |
| "ABSOLUTELY REQUIRED" | (remove — all requirements are requirements) |

### Decompose walls of text

Split on natural boundaries:
- Different concerns (layout vs logic vs data)
- Different files or areas of the codebase
- Sequential dependencies (must do A before B)
- Different skill domains (CSS vs API vs database)

Each task block should be completable and verifiable independently.

### Reference over describe

Instead of:
> "Create an API endpoint that returns JSON with proper error handling, uses middleware for auth, validates the request body, and follows RESTful conventions"

Write:
> "Create a new API endpoint at `/api/widgets`. Follow the pattern in `src/api/users.ts` for error handling, auth middleware, and request validation."

### Transform negatives to positives

| Instead of | Write |
|------------|-------|
| "Do NOT use class components" | "Use functional components with hooks" |
| "NEVER use var" | "Use const/let for all declarations" |
| "Do NOT add unnecessary dependencies" | "Use existing dependencies; justify any new additions" |

Keep negative form only when the positive equivalent would be ambiguous.

### Write task-specific constraints

Constraints should prevent likely failure modes for *this specific task*. The test: "What will go wrong with this task if I don't say this?" If the answer is "nothing task-specific" — it doesn't belong in constraints.

**Good constraints** (task-specific, prevent real failure modes):
- "Use raw request body for signature verification — do not parse JSON first" (Stripe webhook)
- "Do not cache authenticated responses without per-user cache keys" (caching task)
- "Preserve all existing chart functionality — tooltips, legends, click handlers" (dashboard refactor)
- "Keep Express running in parallel until Phase 3" (migration task)

**Bad constraints** (generic boilerplate repeated in every prompt):
- "No stubs or placeholders" — belongs in `<check>` block
- "Run tests after each change" — belongs in `<verification>` block
- "Re-read files after writing" — belongs in `<check>` block
- "Use Bash for deterministic operations" — this is execution guidance, not a task constraint

Generic quality rules belong in `<verification>` and `<check>` blocks where they're actionable. Constraints are for task-specific guardrails that the agent wouldn't know without being told.

### Data-first ordering

For prompts with large code blocks, data, or documents: put the data/context above the instructions. Instructions and queries go at the end. This follows the official recommendation for up to 30% quality improvement.

### Deterministic-first execution

Prefer Bash, grep, scripts, and CLI tools over AI inference for mechanical operations.

| Deterministic (Bash/scripts) | AI inference (reasoning required) |
|---|---|
| Running tests | Code generation |
| Type checking | Architectural decisions |
| Git operations | Debugging reasoning |
| File reads / grep | Writing documentation |
| sed/awk transforms | Evaluating tradeoffs |
| Dependency installation | Understanding errors in context |

Rules:
- `<verification>` blocks contain only runnable commands. Not "review the code and confirm it looks correct."
- Repetitive file operations use scripts, not AI-driven file-by-file editing.

## Anti-patterns

| Pattern | Problem |
|---------|---------|
| Motivational preamble ("You are a world-class...") | Wastes tokens, no behaviour change |
| Meta-instruction stacking ("Be concise, don't be verbose, keep it short") | Noise. One output format spec beats five meta-instructions |
| Negative-heavy prompting (list of "NEVER" rules) | Backfires. State what to do instead |
| Kitchen sink (full app in one prompt) | Context dilution. Break into phases |
| Vague verification ("Make sure it works") | Useless. Specify commands with expected outputs |
| Generic constraint dumps (same boilerplate in every prompt) | Dilutes task instructions. Write constraints specific to the task's failure modes |
| Mandatory ceremony for simple tasks (TeamCreate for one file) | Adds overhead without value. Match ceremony to scope |

## Claude 4.6 specifics

- Use calm, direct instructions — aggressive language causes overtriggering
- Claude 4.6 is more proactive — needs less hand-holding but clear scope boundaries
- Prefer telling Claude what to do over what not to do
- Structured reasoning via `<approach>` blocks improves output quality
- Native adaptive thinking replaces external reasoning tool dependencies

## Prompt sizing

| Task scope | Target size | Template |
|------------|-------------|----------|
| Single-line fix, typo, rename | Skip improvement — just execute | None |
| Single-file change | 10-20 lines | Minimal |
| Multi-file feature | 30-60 lines | Full |
| Cross-cutting refactor | 40-80 lines | Full + research |
| >80 lines | Split into phases | Chaining |

## Adapting to task type

| Type | Emphasise | Include |
|------|-----------|---------|
| Build | Requirements, references, verification | Out-of-scope to prevent creep |
| Fix | Reproduction, expected vs actual, root cause | What NOT to change |
| Refactor | What stays the same (behaviour), what changes (structure) | Existing test verification |
| Research | What to search, evaluation criteria, output format | Decision-making criteria |
| Configure | Exact settings, file paths, environment | Verification config takes effect |
| Migrate | Source state, target state, what to preserve | Rollback strategy, incremental steps |
| Review/Audit | Evaluation criteria, output format | Severity levels, actionable recs |
