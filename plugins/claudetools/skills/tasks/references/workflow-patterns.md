# Workflow Patterns

Common patterns and anti-patterns for using the extended task system effectively.

---

## Pattern 1: Linear Feature Build

Build a feature from specification to completion in a single logical sequence.

**When to use:** You have a well-understood feature with clear steps.

**Steps:**
1. Create a parent task describing the feature: `/tasks new Implement user authentication`
2. Decompose into ordered subtasks: `/tasks decompose Implement user authentication`
   - The system generates 3-7 subtasks with `parent_id` linking them to the parent.
3. Work subtasks sequentially — complete each one before starting the next.
4. As each subtask completes, the parent task's progress is tracked via the subtask count.
5. When all subtasks are done, mark the parent complete.

**Key principle:** Decompose up front, then execute linearly. Avoid re-decomposing mid-flight unless requirements change.

---

## Pattern 2: Bug Investigation

Investigate a reported bug where the root cause is unknown.

**When to use:** The user reports a problem and you need to narrow down the cause before fixing it.

**Steps:**
1. Create an investigation task: `/tasks new Investigate: login fails on Safari`
2. As you explore, add findings as subtasks:
   - "Check Safari-specific CSS/JS issues" (completed if not the cause)
   - "Test cookie SameSite behavior on Safari" (found issue here)
   - "Fix: set SameSite=None for auth cookies"
3. Completed investigation subtasks serve as a record of what was checked.
4. The fix subtask becomes the actionable item.
5. Resolve the parent when the fix is verified.

**Key principle:** Subtasks double as an investigation log. Completed subtasks that did not find the bug are still valuable — they narrow the search space for future sessions.

---

## Pattern 3: Parallel Workstreams

Manage multiple independent tasks that can proceed in any order.

**When to use:** Several unrelated tasks need attention in the same session, or you are working across different parts of the codebase.

**Steps:**
1. Create each task independently (no parent-child relationship):
   - `/tasks new Add input validation to signup form`
   - `/tasks new Fix broken pagination on product list`
   - `/tasks new Update README with API examples`
2. Use tags to group related tasks: `auth`, `bugfix`, `docs`.
3. Query by tag to focus on a specific workstream: the MCP `task_query` tool filters by tag.
4. Work on tasks in any order based on priority and context.

**Key principle:** Tags, not hierarchy, organize parallel work. Reserve parent-child for genuine decomposition.

---

## Pattern 4: Session Handoff

End one session cleanly so the next session can pick up without information loss.

**When to use:** Every session end. Especially important before context compaction or when switching between sessions on the same project.

**Steps:**
1. Before ending, run: `/tasks handoff`
   - This reads all task state and history.
   - Generates a session summary with completed work, in-progress state, blockers, decisions, and next steps.
   - Prepends the summary to `.tasks/progress.md`.
2. Commit the `.tasks/` directory: `git add .tasks/ && git commit -m "chore: update task state"`
3. In the next session, run: `/tasks restore`
   - This reads `progress.md` for narrative context.
   - Syncs the TodoWrite display with persisted state.
   - Reports status counts and last session context.

**Key principle:** Handoff captures the *why* (decisions, context) not just the *what* (task list). The next session starts informed, not just initialized.

---

## Pattern 5: Exploratory Research

Research a topic where the scope becomes clearer as you learn more.

**When to use:** You are evaluating options, reading documentation, or prototyping before committing to an approach.

**Steps:**
1. Create loose, broad tasks:
   - `/tasks new Research: evaluate state management options (Redux, Zustand, Jotai)`
   - `/tasks new Prototype: test Zustand with existing data layer`
2. As understanding grows, refine tasks:
   - Complete or remove options that are ruled out.
   - Decompose the chosen option into implementation subtasks.
3. Prune irrelevant tasks that are no longer needed (they will be recorded as "removed" in history).

**Key principle:** Start broad, narrow progressively. Do not over-decompose before you understand the problem. It is cheaper to remove a few broad tasks than to manage dozens of premature subtasks.

---

## Pattern 6: Recurring Maintenance

Track repeating work patterns across sessions.

**When to use:** Certain tasks recur regularly — dependency updates, performance audits, documentation refreshes.

**Steps:**
1. Use consistent tags for recurring categories: `maintenance`, `deps`, `perf-audit`, `docs-refresh`.
2. Create new task instances each time the work is needed. Do not reuse old task objects.
3. Query by tag to see the history of a recurring pattern: how often it occurs, what was done last time.
4. Reference previous task content and decisions when performing the same type of work again.

**Key principle:** Tags create queryable categories across time. Each instance is a separate task, but the tag connects them into a pattern.

---

## Anti-Patterns

### Over-decomposition

**Problem:** Breaking an atomic task into sub-steps that cannot meaningfully exist independently.

**Example:** Decomposing "Add email field to form" into "Create input element", "Add label", "Add validation", "Style the field". Each of these is a single line of code and not worth tracking separately.

**Fix:** Only decompose tasks that have 3+ distinct, non-trivial steps. If a task takes less than 5 minutes, it does not need subtasks.

### Status thrashing

**Problem:** Flipping a task between `pending` and `in_progress` repeatedly, creating noisy history.

**Example:** Starting a task, getting distracted, marking it pending, starting again, marking it pending again.

**Fix:** Leave a task as `in_progress` once started, even if you temporarily switch focus. Use the narrative in progress.md to note interruptions, not status changes.

### Orphaned subtasks

**Problem:** Creating subtasks without setting `parent_id`, so they appear as independent top-level tasks with no connection to the parent.

**Example:** Running `/tasks decompose` but manually creating tasks with `/tasks new` instead of letting the decompose flow set parent relationships.

**Fix:** Always use `/tasks decompose` for creating subtasks. If creating manually, explicitly set `parent_id` via the MCP `task_create` tool.

### Stale progress.md

**Problem:** Forgetting to run `/tasks handoff` before session end, leaving progress.md outdated for the next session.

**Example:** The next session runs `/tasks restore`, reads progress.md, and gets context from two sessions ago instead of the most recent one.

**Fix:** Always run `/tasks handoff` before ending a session. Make it a habit. The rule file in CLAUDE.md reminds you, but it requires following through.
