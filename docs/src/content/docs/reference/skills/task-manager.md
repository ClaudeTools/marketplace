---
title: "Managing Tasks"
description: "Skill for persistent task tracking with cross-session continuity, dependency management, and session handoff summaries."
---

> **Status:** ✅ Stable — included in all claudetools versions

Extended task management with persistence, cross-session continuity, and validation. Provides a subcommand router on top of the built-in task system.

**Trigger:** Use when the user says `/task-manager`, "task status", "manage tasks", "restore tasks", or "session handoff".

**Invocation:** `/task-manager [subcommand] [arguments]`

---

## When to use this

Use this skill when a piece of work is too large to finish in one session, or when you want to track progress across multiple steps without losing context when Claude's memory resets. It's also the right tool at the start of a session — run `restore` to pick up exactly where you left off, with all tasks, subtasks, and decisions still intact. If you're about to ask Claude to do five distinct things, create and decompose a task first.

---

## Try it now

```
/task-manager new Migrate the user authentication module from JWT to session cookies
```

Claude will gather codebase context, enrich the task description with acceptance criteria and file references, create it in the persistent task system, and offer to decompose it into subtasks. Run `/task-manager status` at any point to see where things stand.

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
3. Run `/task-manager restore` to sync TodoWrite display with persisted state.

### Creating a Task (`new`)
1. Parse arguments as raw input.
2. Gather codebase context via codebase-pilot CLI (`map`, `find-symbol`, `file-overview`).
3. Triage: if already detailed, skip enrichment. If rough, spawn enrichment agent.
4. Enrichment agent produces a self-contained task description with acceptance criteria, file references, verification commands, risk level.
5. Create task via MCP `task_create`.

### Session End / Before Compaction
1. Run `/task-manager handoff` to update `progress.md`.
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
/task-manager status
/task-manager new Fix the broken webhook endpoint for Stripe events
/task-manager decompose task-abc123
/task-manager restore
/task-manager handoff
```

---

## Related Components

- **task-system** — the underlying MCP server this skill wraps (see [Task System](../task-system.md))
- **prompt-improver skill** — task mode creates tasks for this skill to execute
- **enforce-task-quality hook** — fires on TeammateIdle to verify task completeness
- **task-management rule** — session start/end procedures injected into all sessions
