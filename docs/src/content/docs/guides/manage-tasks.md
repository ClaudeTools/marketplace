---
title: "Manage Tasks"
description: "Track work across sessions with persistent tasks, subtask decomposition, and handoff summaries."
---

Use `/managing-tasks` to create, track, and hand off work across sessions — with persistent storage, cross-session continuity, and AI-assisted decomposition.

## Real scenarios

### Scenario A: Starting a multi-session project

**Session 1 — Create tasks and start work**

> "I need to add CSV export to the invoices page, including column selection and date filtering"

:::note[Behind the scenes]
`/managing-tasks new` runs `codebase-pilot map` to understand the project structure, then calls an enrichment agent that adds acceptance criteria, file references, and verification commands before creating the task with a deterministic ID.
:::

```
Task created: task-a3f8b2c1
Title: Add CSV export to invoices page
Files: src/pages/invoices.tsx, src/api/export.ts (new), src/components/ExportModal.tsx (new)
Acceptance criteria:
  - Column selector lets users pick which fields to export
  - Date range filter applies before export
  - Export triggers a file download with correct MIME type
  - Works with up to 10,000 rows without timeout
```

Now decompose it into subtasks before starting:

> "/managing-tasks decompose task-a3f8b2c1"

:::note[Behind the scenes]
Claude analyses the task, breaks it into 3–7 subtasks with explicit dependencies, and gives each subtask its own acceptance criteria and file references so it can be executed autonomously.
:::

```
Decomposed into 4 subtasks:

task-b1c2d3e4  [1] Add export API endpoint           src/api/export.ts
task-f5g6h7i8  [2] Build ExportModal component        src/components/ExportModal.tsx
task-j9k0l1m2  [3] Wire modal into invoices page      src/pages/invoices.tsx
task-n3o4p5q6  [4] Add E2E test for export flow       tests/e2e/export.spec.ts

Dependencies: 1 → 2 → 3; 4 depends on 3
```

Start the first task:

> "/managing-tasks start"

Claude picks `task-b1c2d3e4` (highest priority, no blockers) and begins via TeamCreate.

---

**Session 1 ends — generate a handoff**

Before closing the session:

> "/managing-tasks handoff"

:::note[Behind the scenes]
The handoff command writes `progress.md` with completed items (with implementation detail), in-progress work, blocked items, key decisions, and concrete next steps in priority order.
:::

```
Handoff written to .tasks/progress.md

Completed this session:
  ✓ task-b1c2d3e4 — Export API endpoint at POST /api/invoices/export
    Returns CSV with Content-Disposition header. Accepts { columns[], startDate, endDate }.
    Pagination handled internally — single request regardless of row count.

In progress:
  → task-f5g6h7i8 — ExportModal — column checkboxes done, date picker not yet wired

Next steps (in order):
  1. Finish ExportModal date picker (task-f5g6h7i8)
  2. Wire modal into invoices page (task-j9k0l1m2)
  3. Add E2E test (task-n3o4p5q6)
```

---

### Scenario B: Picking up in a new session

**Session 2 — Restore and continue**

> "/managing-tasks restore"

```
Restored 4 tasks (1 completed, 1 in_progress, 2 pending)

Last session summary:
  Export API complete at POST /api/invoices/export
  ExportModal partially done — column checkboxes work, date picker incomplete

Next up: task-f5g6h7i8 — finish ExportModal date picker
```

Continue without re-explaining anything:

> "/managing-tasks start"

Claude picks `task-f5g6h7i8` and resumes from where it left off, using the handoff context as its starting point.

---

### Scenario C: Checking status mid-session

> "/managing-tasks status"

```
COMPLETED (1)
  ✓ task-b1c2d3e4  Export API endpoint

IN PROGRESS (1)
  → task-f5g6h7i8  ExportModal component

PENDING (2)
  · task-j9k0l1m2  Wire modal into invoices page    [blocked by task-f5g6h7i8]
  · task-n3o4p5q6  Add E2E test                     [blocked by task-j9k0l1m2]
```

---

:::tip[Which command to use when]
- **New project or feature**: `/managing-tasks new` + `/managing-tasks decompose` before starting
- **Resuming work**: Always run `/managing-tasks restore` first — it shows the last handoff summary
- **Ending a session**: Run `/managing-tasks handoff` before closing — this is the most important command for cross-session continuity
- **Check what's next**: `/managing-tasks status` shows blocked vs ready tasks at a glance
:::

## MCP tools for programmatic use

The task system exposes MCP tools you can invoke directly:

> "Use task_query to show all blocked tasks"

```
task-j9k0l1m2  Wire modal into invoices page    blocked by task-f5g6h7i8
task-n3o4p5q6  Add E2E test                     blocked by task-j9k0l1m2
```

> "Use task_create to add a task: investigate the slow query on the invoices list page"

```
Task created: task-r7s8t9u0
Title: Investigate slow query on invoices list page
Priority: medium
Files: src/api/invoices.ts, src/db/queries/invoices.ts
```

| Tool | Purpose |
|------|---------|
| `task_create` | Create a task with full metadata |
| `task_query` | Filter tasks by status, tag, parent, or blocked state |
| `task_update` | Change status, priority, tags, or dependencies |
| `task_decompose` | Get decomposition guidance for a task |
| `task_progress` | Generate or append a session progress report |

## What happens behind the scenes

- Tasks are stored in `.tasks/tasks.json` — commit this to git so state is shared across teammates and survives branch switches
- History is appended to `.tasks/history.jsonl` on every status change
- Task IDs are deterministic (SHA-256 of content, truncated to 8 hex chars) — reference them in commit messages to link work to its tracking record
- A PostToolUse hook fires on every `TodoWrite` to sync the persistent store in under 100ms
- All execution uses TeamCreate to keep the main conversation context clean

## Tips

- Use `/managing-tasks decompose` before `/managing-tasks start` on large tasks — subtasks execute in parallel, saving significant time
- Task IDs are stable — use them in commit messages (`fix: auth token expiry (task-a3f8b2c1)`) for traceability
- If task state looks inconsistent, run `/managing-tasks validate` to check for orphaned subtasks or broken dependencies

## Related

- [Coordinate Agents](coordinate-agents.md) — tasks and agents work together via TeamCreate
- [Build a Feature](build-a-feature.md) — the feature-pipeline creates and tracks tasks automatically
- [Improve Prompts](improve-prompts.md) — use `task` mode to convert prompts into tracked tasks
