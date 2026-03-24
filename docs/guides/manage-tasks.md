---
title: Manage Tasks
parent: Guides
nav_order: 6
---

# Manage Tasks

Use the `/managing-tasks` skill to create, track, and hand off work across sessions — with persistent storage, cross-session continuity, and AI-assisted decomposition.
{: .fs-6 .fw-300 }

## What you need
- claudetools installed
- The task-manager MCP server configured (included with claudetools)

## Steps

### 1. Create a task

```
/managing-tasks new Add CSV export to the invoices page
```

The task system enriches your description before creating it:

1. Runs `codebase-pilot map` to understand the project structure
2. Looks up file paths and symbols mentioned in your description
3. Calls an enrichment agent to add acceptance criteria, file references, and verification commands
4. Creates the task with a deterministic ID (e.g. `task-a3f8b2c1`)

You can also pass a file path or URL as the input — the system reads and enriches the content:

```
/managing-tasks new docs/design/csv-export-spec.md
```

### 2. Start the next task

```
/managing-tasks start
```

This picks the highest-priority pending task with no blockers, marks it `in_progress`, and begins execution via TeamCreate. You do not need to specify which task — the system selects based on priority and dependency order.

### 3. Check task status

```
/managing-tasks status
```

The status report shows all tasks grouped by state (pending, in_progress, completed, blocked) with their priority and dependency links.

### 4. Stop (complete) a task

```
/managing-tasks stop
```

This marks the current in-progress task as completed, records which files were touched (via `git diff`), and shows the next pending task as a suggestion.

### 5. Decompose a complex task into subtasks

```
/managing-tasks decompose task-a3f8b2c1
```

Claude analyses the task and breaks it into 3–7 subtasks with explicit dependencies. Each subtask gets its own acceptance criteria, file references, and verification commands so it can be executed autonomously.

### 6. Hand off to the next session

Run this before ending a session or when context is running low:

```
/managing-tasks handoff
```

This writes a `progress.md` file with:
- What was completed (with implementation detail, not just task names)
- What is in progress and what remains
- Blocked items and their specific blockers
- Key decisions made this session
- Concrete next steps in priority order

### 7. Restore tasks in a new session

At the start of a new session, restore the task state:

```
/managing-tasks restore
```

This reads the persistent task store and syncs it to the current display. The previous session's `progress.md` is shown so you have full context before starting.

### 8. View progress narrative

```
/managing-tasks progress
```

Shows the full progress history. If the file is stale (last updated more than 2 hours ago), the system offers to regenerate it from the current task state.

### 9. Validate task state

```
/managing-tasks validate
```

Checks for duplicate IDs, invalid status values, orphaned subtasks, and broken dependencies. Run this if the task state looks inconsistent.

## MCP tools

The task system also exposes MCP tools for direct use:

| Tool | Purpose |
|------|---------|
| `task_create` | Create a task with full metadata |
| `task_query` | Filter tasks by status, tag, parent, or blocked state |
| `task_update` | Change status, priority, tags, or dependencies |
| `task_decompose` | Get decomposition guidance for a task |
| `task_progress` | Generate or append a session progress report |

These tools are called automatically by the skill but you can invoke them directly via Claude:

```
Use task_query to show all blocked tasks
```

## What happens behind the scenes

- Tasks are stored in `.tasks/tasks.json` and designed to be committed to git
- History is appended to `.tasks/history.jsonl` on every status change
- Task IDs are deterministic — SHA-256 of the content string, truncated to 8 hex chars — so the same task always gets the same ID
- A PostToolUse hook fires on every `TodoWrite` to sync the persistent store — it runs in <100ms using only Node.js built-ins
- All execution uses TeamCreate to keep the main conversation context clean

## Tips

- Commit `.tasks/` to git so task state survives branch switches and is shared with teammates
- Use `/managing-tasks decompose` before `/managing-tasks start` on large tasks — subtasks execute in parallel, saving significant time
- The `handoff` command is the most important one to run consistently — it is the primary mechanism for cross-session continuity
- Task IDs are stable — reference them in commit messages and PR descriptions to link work to its tracking record

## Related

- [Build a Feature](build-a-feature.md) — the feature-pipeline creates and tracks tasks automatically
- [Coordinate Agents](coordinate-agents.md) — tasks and agents work together via TeamCreate
- [Improve Prompts](improve-prompts.md) — use `task` mode to convert prompts into tracked tasks
