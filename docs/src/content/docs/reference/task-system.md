---
title: "Task System"
description: "Task System — claudetools documentation."
---
MCP server providing persistent task tracking with cross-session continuity, dependency management, history, and quality gate integration. Tasks persist in `.tasks/` and survive context compaction.

**MCP Server:** `plugin/task-system/`
**Storage:** `.tasks/task-manager.json` (tasks), `.tasks/history.jsonl` (audit log)

---

## MCP Tools

### task_create

Create a new task. Returns task ID, content, and status.

```json
{
  "content": "Comprehensive task description with Title, Description, Acceptance Criteria, File References, Constraints, Verification commands, Risk Level",
  "parent_id": "optional — parent task ID for subtasks",
  "dependencies": ["task-id-1", "task-id-2"],
  "tags": ["feature", "auth"],
  "priority": "critical | high | medium | low",
  "metadata": {
    "file_references": { "read": [], "modify": [], "do_not_touch": [] },
    "acceptance_criteria": ["verb-led criterion"],
    "verification_commands": ["npm test -- --grep auth"],
    "risk_level": "low | medium | high"
  }
}
```

Content must include acceptance criteria (verb-led, measurable), file references (with real paths), and verification commands (exact shell commands). One-liners are rejected.

### task_update

Update an existing task's status, dependencies, tags, files_touched, metadata, or priority.

```json
{
  "id": "task-id",
  "status": "pending | in_progress | completed | removed",
  "files_touched": ["src/api/auth.ts"],
  "metadata": {}
}
```

Mark `in_progress` when starting work. Mark `completed` only when genuinely done (triggers `task-completion-gate.sh`).

### task_query

Query tasks with filters.

```json
{
  "status": "pending | in_progress | completed | removed",
  "tag": "feature",
  "parent_id": "task-id",
  "has_blocker": true,
  "format": "json | summary"
}
```

### task_decompose

Get context for decomposing a task into subtasks. Returns the parent task, existing subtasks, and guidance.

```json
{ "id": "task-id", "max_subtasks": 5 }
```

### task_progress

Get task progress data.

```json
{ "action": "generate | append_session" }
```

- `generate` — full tasks + history for a session handoff narrative
- `append_session` — current session counts only

---

## Quality Gate Integration

When a task is marked `completed`, the `task-completion-gate.sh` hook fires and verifies:
- Verification commands listed in the task metadata ran successfully
- Files listed in `file_references.modify` were actually touched (via `files_touched`)
- The task was not completed with zero tool calls (a sign of premature completion)

When a teammate goes idle, `enforce-task-quality.sh` checks that in-progress tasks have been properly updated.

---

## Task Lifecycle

```
pending → in_progress → completed
                     ↘ removed
```

All transitions are recorded in `.tasks/history.jsonl` for audit and handoff purposes.

---

## Cross-Session Continuity

- `.tasks/task-manager.json` — persists all task state
- `.tasks/progress.md` — human-readable session handoff (written by `/managing-tasks handoff`)
- On session start, check `progress.md` first, then run `/managing-tasks restore` to sync TodoWrite display

Commit `.tasks/` to version control to share task state across team members and sessions.
