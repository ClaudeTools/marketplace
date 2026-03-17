# Setup Guide

Step-by-step setup and troubleshooting for the task management system.

## Architecture Overview

The task system has four layers:

| Layer   | Component              | Purpose                                      |
|---------|------------------------|----------------------------------------------|
| PERSIST | PostToolUse hook       | Captures TodoWrite events, writes to .tasks/  |
| ENRICH  | MCP server             | Provides task_create, task_update, task_query, task_decompose, task_progress |
| TEACH   | /tasks skill           | Subcommand router for user interaction        |
| CONNECT | Rule file              | CLAUDE.md-level guidance for session behavior |

## 1. Hook Setup

The `PostToolUse:TodoWrite` hook is registered in the plugin's `hooks.json`. No user configuration is needed if you are using the claudetools plugin.

**What it does:**
- Intercepts every TodoWrite call after it executes.
- Compares the new task list against the persisted state in `.tasks/tasks.json`.
- Writes additions, updates, and removals to `tasks.json` and `history.jsonl`.
- Generates deterministic task IDs from content strings.

**Verification:**
```bash
# Check that the hook is registered
cat "${CLAUDE_PLUGIN_ROOT}/hooks.json" | grep -A2 "TodoWrite"
```

The hook should appear under `PostToolUse` with event `TodoWrite`.

## 2. MCP Server

The task management MCP server is registered in `plugin.json`. It starts automatically when Claude Code loads the plugin.

**Tools provided:**
- `task_create` — Create a task with enriched metadata (priority, tags, dependencies).
- `task_update` — Update task fields (priority, tags, files_touched, metadata).
- `task_query` — Query tasks by status, tag, parent, or content match.
- `task_decompose` — Get AI-suggested decomposition for a task.
- `task_progress` — Read or update progress.md programmatically.

**Verification:**
```bash
# Check that the MCP server is registered
cat "${CLAUDE_PLUGIN_ROOT}/plugin.json" | grep -A5 "task"
```

If the MCP server is not running, the /tasks skill still works — it falls back to TodoWrite and direct file manipulation. The MCP server adds convenience and richer metadata but is not required.

## 3. Skill

The `/tasks` skill is available when the claudetools plugin is installed. It is located at `${CLAUDE_PLUGIN_ROOT}/skills/tasks/SKILL.md`.

**Subcommands:**
- `/tasks` or `/tasks status` — Show current task state.
- `/tasks new <description>` — Create a new task.
- `/tasks restore` — Restore tasks from previous session.
- `/tasks decompose <task>` — Break a task into subtasks.
- `/tasks progress` — Show or update progress narrative.
- `/tasks handoff` — Generate session summary for handoff.
- `/tasks validate` — Run validation checks on task state.

## 4. Rule File

The rule file `task-management.md` provides CLAUDE.md-level guidance. It is located at `${CLAUDE_PLUGIN_ROOT}/rules/task-management.md`.

**What it does:**
- On session start: prompts checking for existing task state and restoring it.
- During work: reminds to use the hook naturally and decompose complex tasks.
- On session end: prompts running `/tasks handoff` before closing.

The rule applies to all file paths (`**/*`) so it is always active.

## 5. Data Directory

The `.tasks/` directory is created automatically on the first TodoWrite event captured by the hook. No manual setup is needed.

**Contents:**
- `tasks.json` — Current task state (array of task objects).
- `history.jsonl` — Append-only transition log.
- `progress.md` — Session summaries (newest at top).

**Location:** The `.tasks/` directory is created in the project root (where `.git/` lives).

**Version control:** Add `.tasks/` to your git repository. It contains only text-based files and is designed to be committed.

## 6. Troubleshooting

### Tasks are not being saved

**Symptom:** TodoWrite works but `.tasks/tasks.json` is not created or updated.

**Likely cause:** The PostToolUse hook is not registered or not firing.

**Fix:**
1. Check `hooks.json` includes the TodoWrite hook.
2. Check the hook script exists at the registered path.
3. Check file permissions — the hook script must be executable.
4. Check the plugin logs: `cat "${CLAUDE_PLUGIN_ROOT}/logs/hook.log"` for errors.

### /tasks restore shows no tasks

**Symptom:** Running `/tasks restore` reports zero tasks even though you had tasks in a previous session.

**Likely cause:** The `.tasks/` directory does not exist in the current working directory, or `tasks.json` is empty.

**Fix:**
1. Verify you are in the correct project directory.
2. Check if `.tasks/tasks.json` exists: `ls -la .tasks/`
3. If the directory is missing, the hook has never fired in this directory. Create a task with TodoWrite to initialize it.

### MCP tools not available

**Symptom:** The skill falls back to basic TodoWrite instead of using `task_create`, `task_update`, etc.

**Likely cause:** The MCP server failed to start or is not registered.

**Fix:**
1. Check `plugin.json` for the server registration.
2. Check if the server process is running: `ps aux | grep task-system`
3. Check server logs for startup errors.
4. Restart Claude Code to reinitialize MCP servers.

### Duplicate tasks after restore

**Symptom:** After running `/tasks restore`, tasks appear twice in the TodoWrite display.

**Likely cause:** This should not happen because IDs are deterministic. If it does, the content strings may differ slightly (trailing whitespace, punctuation).

**Fix:**
1. Run `/tasks validate` to check for duplicate IDs.
2. If duplicates are found, manually edit `.tasks/tasks.json` to remove the duplicate.
3. The hook's idempotent design prevents this in normal operation.

### history.jsonl growing too large

**Symptom:** The history file is very large (>1MB) and slowing down progress generation.

**Likely cause:** Many sessions with frequent task transitions.

**Fix:**
1. Archive old entries: move lines older than 30 days to `history.archive.jsonl`.
2. The current `history.jsonl` only needs recent entries for progress generation.
3. Do not delete history — archive it for audit purposes.

### Validation errors

**Symptom:** `/tasks validate` reports errors.

**Common errors and fixes:**
- **Duplicate IDs:** Two tasks with different content collided on the 8-char hash. The hook should have extended the ID automatically. Manually rename one ID.
- **Invalid status:** A task has a status value not in [pending, in_progress, completed]. Edit `tasks.json` to fix.
- **Orphaned subtasks:** A subtask references a `parent_id` that does not exist. Either recreate the parent or clear the `parent_id`.
- **Broken dependencies:** A task lists a dependency ID that does not exist. Remove the stale ID from the `dependencies` array.
