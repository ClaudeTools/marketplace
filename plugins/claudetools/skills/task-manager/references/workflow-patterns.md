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

## Anti-Patterns

- **Over-decomposition**: Only decompose tasks with 3+ distinct non-trivial steps.
- **Status thrashing**: Leave tasks as `in_progress` once started, even if temporarily switching focus.
- **Orphaned subtasks**: Always use `/task-manager decompose` to set parent relationships.
- **Stale progress.md**: Always run `/task-manager handoff` before ending a session.
