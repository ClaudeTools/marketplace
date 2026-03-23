---
paths:
  - "**/*"
---

## Task Management

This project may use an extended task system. Task state persists in `.tasks/`.

### On session start
- Check if `.tasks/progress.md` exists. If it does, read it first to understand where we left off.
- Check `.tasks/task-manager.json` for current task state.
- Use `/task-manager restore` to sync TodoWrite display with persisted state.

### During work
- Use TodoWrite normally — the hook persists changes automatically.
- When modifying files as part of a task, record files_touched via task_update if the MCP server is available.
- Use `/task-manager decompose` for tasks with 3+ distinct steps.

### On session end or before context compaction
- Run `/task-manager handoff` to update progress.md with session summary.
- Include key decisions and concrete next steps.
- Suggest committing `.tasks/` to version control.
