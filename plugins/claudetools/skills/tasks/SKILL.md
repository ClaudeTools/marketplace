---
name: tasks
description: Extended task management with persistence, cross-session continuity, and validation. Use when the user says /tasks, task status, manage tasks, restore tasks, or session handoff.
argument-hint: [new|status|restore|decompose|progress|handoff|validate]
allowed-tools: Read, Bash, Grep, Glob, Write, Edit
metadata:
  author: Owen Innes
  version: 1.0.0
  category: task-management
  tags: [tasks, persistence, session, handoff, validation]
---

# Task Management

You are executing the `/tasks` skill. This is a subcommand router for the extended task system. It provides persistent storage, cross-session continuity, and deterministic validation on top of the built-in TodoWrite tool.

Parse the first argument to select the subcommand. Default to `status` if no argument is given.

---

### new

Create a new task.

1. Parse the remaining arguments as the task description.
2. Use the `TaskCreate` tool to add the task to the TodoWrite display.
3. If the MCP `task_create` tool is available, call it instead — it supports richer metadata:
   - `priority` (low, medium, high, critical)
   - `tags` (array of strings)
   - `dependencies` (array of task IDs)
   - `parent_id` (for subtasks)
4. Confirm creation to the user with the assigned task ID.

---

### status

Display current task state. This is also the default when no argument is given.

1. Run the report script:
```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/tasks/scripts/task-report.js" --format markdown
```
2. Present the markdown output to the user.
3. If the script exits non-zero or `.tasks/tasks.json` does not exist, tell the user: "No tasks found. Use `/tasks new <description>` to create one."

---

### restore

Restore tasks from a previous session into the TodoWrite display. Critical for cross-session continuity.

1. Check if `.tasks/progress.md` exists. If yes, read it FIRST — it provides narrative context about where the previous session left off.
2. Run the sync script:
```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/tasks/scripts/sync-display.js"
```
3. Parse the JSON output. It contains an array of task objects with `content` and `status` fields.
4. Call `TodoWrite` with the restored task list to sync the display.
5. Report to the user:
   - Total tasks restored
   - Status counts (pending, in_progress, completed, blocked)
   - Last session context (from progress.md, if available)

---

### decompose

AI-assisted task decomposition. Argument: target task description or ID.

1. Read `.tasks/tasks.json` and match the target task by content string or task ID prefix.
2. If the MCP `task_decompose` tool is available, call it to get parent context and suggested breakdown.
3. Analyse the task in context:
   - What files are likely involved?
   - What are the dependencies and execution order?
   - Are there natural separation points?
4. Generate 3-7 subtasks. Prefer fewer, more substantial subtasks over many trivial ones.
5. Add each subtask via `TaskCreate` with `parent_id` set to the parent task's ID.
6. Update the parent task's status to `in_progress` if it was `pending`.
7. Present the decomposition tree to the user.

---

### progress

Show or update the progress narrative.

1. Check if `.tasks/progress.md` exists.
   - If yes, read and display its contents.
   - If no, tell the user: "No progress file yet. Run `/tasks handoff` at the end of a session to generate one."
2. If the user says "update" or the file is stale (last modified more than 2 hours ago):
   - Read `.tasks/tasks.json` and `.tasks/history.jsonl`
   - Generate an updated session block following the template in `assets/progress-template.md`
   - Prepend the new block to `.tasks/progress.md` (newest session at top)

---

### handoff

Session end workflow. Run this before ending a session or when context compaction is imminent.

1. Read `.tasks/tasks.json` for current state.
2. Read `.tasks/history.jsonl` for transition history since the last handoff.
3. Generate a session summary with these sections:
   - **Completed**: Each completed task with implementation detail, not just the task name.
   - **In Progress**: Each in-progress task with current state and what remains.
   - **Blocked**: Each blocked task with the specific blocker.
   - **Key Decisions**: Decisions that would be expensive to re-deliberate in a future session.
   - **Next Steps**: Concrete, actionable items in priority order.
4. Prepend the new session block to `.tasks/progress.md` (newest at top). Create the file if it does not exist.
5. Suggest committing `.tasks/` to git:
```
Consider committing the task state:
  git add .tasks/ && git commit -m "chore: update task state"
```

---

### validate

Run deterministic validation on the task state.

1. Run the validation script:
```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/tasks/scripts/validate-tasks.js"
```
2. Report the results:
   - Number of tasks checked
   - Validation errors (if any): duplicate IDs, invalid status values, orphaned subtasks, broken dependencies
   - Validation warnings (if any): stale tasks, missing tags, empty descriptions
3. If all checks pass, confirm: "Task state is valid."

---

## Gotchas

- **TodoWrite has no ID field.** Tasks are matched by content string. If you rephrase a task description, the system treats it as a deletion of the old task plus creation of a new one. Keep descriptions stable.
- **Hook fires on every TodoWrite including restores.** This is by design — the hook is idempotent because it uses deterministic IDs. Restoring tasks does not create duplicate history entries.
- **Task IDs are deterministic.** Generated as SHA-256 of the content string, truncated to 8 hex characters (e.g., `task-a3f8b2c1`). Same content always produces the same ID.
- **Hook must complete in <100ms.** The PostToolUse hook runs synchronously. It has zero npm dependencies and uses only Node.js built-ins to stay fast.
- **progress.md uses append-prepend ordering.** Newest session block goes at the top of the file, so the most recent context is always first.
- **.tasks/ belongs in version control.** The entire directory is designed to be committed. It contains only JSON, JSONL, and markdown — no binaries, no secrets.

---

## Conditional References

- Load [references/task-schema.md](references/task-schema.md) when working with tasks.json fields, debugging validation errors, or understanding the data model.
- Load [references/workflow-patterns.md](references/workflow-patterns.md) when handling complex multi-task workflows, decomposition strategies, or session handoff patterns.
- Load [references/setup-guide.md](references/setup-guide.md) when the persistence hook or MCP server is not configured, or when troubleshooting why tasks are not being saved.
