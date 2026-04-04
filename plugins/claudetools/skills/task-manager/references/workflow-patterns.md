# Workflow Patterns

Common patterns and anti-patterns for using the extended task system effectively.

---

## Pattern 1: Linear Feature Build

Build a feature from specification to completion in a single logical sequence.

1. Create a parent task: `/task-manager new Implement user authentication`
2. Decompose into subtasks: `/task-manager decompose Implement user authentication`
3. Work subtasks sequentially.
4. Mark parent complete when all subtasks are done.

---

## Pattern 2: Bug Investigation

Investigate a reported bug where the root cause is unknown.

1. Create an investigation task.
2. Add findings as subtasks (completed if not the cause).
3. The fix subtask becomes the actionable item.
4. Completed investigation subtasks serve as a record of what was checked.

---

## Pattern 3: Parallel Workstreams

Manage multiple independent tasks using tags, not hierarchy.

1. Create each task independently.
2. Use tags to group related tasks.
3. Query by tag to focus on a specific workstream.

---

## Pattern 4: Session Handoff

1. Before ending: `/task-manager handoff`
2. Commit `.tasks/` to git.
3. Next session: `/task-manager restore`

---

## Pattern 5: Exploratory Research

Start broad, narrow progressively. Do not over-decompose before understanding the problem.

---

## Pattern 6: Recurring Maintenance

Use consistent tags for recurring categories. Create new task instances each time. Query by tag to see history.

---

## Pattern 7: PRD-Quality Task Creation

Every task should be a self-contained PRD that an agent can execute autonomously without asking clarifying questions.

1. **Gather codebase context first**: Use srcpilot CLI (`srcpilot map`, `srcpilot find`, `srcpilot overview`, `srcpilot related`) to discover real file paths and understand the project structure before writing task content.
2. **Create parent task**: High-level description of the overall goal.
3. **Decompose into subtasks**: Each subtask is a self-contained PRD with ALL sections:
   - Title, Description, Acceptance Criteria (verb-led, measurable, ≥2 items)
   - File References (read/modify/do-not-touch with real paths from srcpilot)
   - Reference Patterns, Constraints, Out of Scope
   - Verification (exact shell commands, ≥1), Risk Level
4. **Create ALL phases upfront**: Including verification, testing, polish, and documentation — not just implementation. Every phase gets the same depth of detail.
5. **Set dependencies based on data flow**: Not just sequential order. Independent tasks should be parallelisable.

**Example — 3-task decomposition with equal depth:**

```
Task 1 (implementation): "Add rate limiting middleware"
  Acceptance: limit to 100 req/min per IP, return 429 with Retry-After header
  Files: modify src/middleware/rate-limit.ts, read src/app.ts
  Verification: curl -s -o /dev/null -w "%{http_code}" localhost:3000/api — returns 429 after 100 requests

Task 2 (tests): "Add rate limiting test suite"
  Acceptance: ≥3 test cases covering normal, limit-hit, and reset scenarios
  Files: create tests/rate-limit.test.ts, read src/middleware/rate-limit.ts
  Verification: npm test -- --grep "rate limit" — all pass

Task 3 (verification): "Verify rate limiting integration"
  Acceptance: middleware registered in app.ts, no regressions in existing tests, no type errors
  Files: read src/app.ts, read src/middleware/rate-limit.ts
  Verification: npm run typecheck && npm test — zero failures
```

Note: Task 3 (verification) has the same structural depth as Task 1 (implementation). Acceptance criteria are measurable. File references are specific. Verification commands are exact.

---

## Anti-Patterns

- **Over-decomposition**: Only decompose tasks with 3+ distinct non-trivial steps.
- **Status thrashing**: Leave tasks as `in_progress` once started, even if temporarily switching focus.
- **Orphaned subtasks**: Always use `/task-manager decompose` to set parent relationships.
- **Stale progress.md**: Always run `/task-manager handoff` before ending a session.
- **Thin Tasks**: Tasks with fewer than 3 lines of content, no acceptance criteria, no verification commands. A task an agent cannot execute autonomously is not a task — it is a reminder. Always include acceptance criteria, file references, and verification commands.
- **Phase Deferral**: Creating only the first 2-3 phases and saying "remaining phases will be created later." All phases must be created upfront with equal detail. Later phases are not less important — verification and documentation tasks require the same depth as implementation tasks.
- **Invented File Paths**: Referencing files like `src/services/auth.service.ts` without verifying they exist. Use srcpilot CLI (`srcpilot find`, `srcpilot overview`) to discover real paths before including them in task content. Invented paths cause agents to waste time searching for files that don't exist.
