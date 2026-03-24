---
title: "Managing Tasks"
description: "Managing Tasks — claudetools documentation."
---
Extended task management with persistence, cross-session continuity, and validation. Provides a subcommand router on top of the built-in task system.

**Trigger:** Use when the user says `/task-manager`, "task status", "manage tasks", "restore tasks", or "session handoff".

**Invocation:** `/managing-tasks [subcommand] [arguments]`

---

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `new <description>` | Create a new task with enrichment pipeline |
| `start` | Begin executing pending tasks |
| `stop` | Pause task execution |
| `status` | Show current task state (default if no argument) |
| `restore` | Sync TodoWrite display with persisted state from `.tasks/` |
| `decompose <task-id>` | Break a task into subtasks (use for tasks with 3+ distinct steps) |
| `progress` | Generate progress report |
| `handoff` | Write session summary to `.tasks/progress.md` for next session |
| `validate` | Run validation checks on current task state |

---

## Workflow Steps

### Session Start
1. Check if `.tasks/progress.md` exists — if so, read it first.
2. Check `.tasks/task-manager.json` for current task state.
3. Run `/managing-tasks restore` to sync TodoWrite display with persisted state.

### Creating a Task (`new`)
1. Parse arguments as raw input.
2. Gather codebase context via codebase-pilot CLI (`map`, `find-symbol`, `file-overview`).
3. Triage: if already detailed, skip enrichment. If rough, spawn enrichment agent.
4. Enrichment agent produces a self-contained task description with acceptance criteria, file references, verification commands, risk level.
5. Create task via MCP `task_create`.

### Session End / Before Compaction
1. Run `/managing-tasks handoff` to update `progress.md`.
2. Include key decisions and concrete next steps.
3. Commit `.tasks/` to version control.

---

## Storage

Task state persists in `.tasks/`:
- `task-manager.json` — active task state
- `progress.md` — session handoff document (human-readable)
- Task history in the MCP task system

---

## Example Invocations

```
/managing-tasks status
/managing-tasks new Fix the broken webhook endpoint for Stripe events
/managing-tasks decompose task-abc123
/managing-tasks restore
/managing-tasks handoff
```

---

## Related Components

- **task-system** — the underlying MCP server this skill wraps (see [Task System](../task-system.md))
- **improving-prompts skill** — task mode creates tasks for this skill to execute
- **enforce-task-quality hook** — fires on TeammateIdle to verify task completeness
- **task-management rule** — session start/end procedures injected into all sessions
