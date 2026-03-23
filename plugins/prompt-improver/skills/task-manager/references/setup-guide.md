# Setup Guide

The task system is fully integrated into the claudetools plugin. No manual setup is needed.

## Components

| Layer   | Component              | Purpose                                      |
|---------|------------------------|----------------------------------------------|
| PERSIST | PostToolUse hook       | Captures TodoWrite events, writes to .tasks/  |
| ENRICH  | MCP server             | Provides task_create, task_update, task_query, task_decompose, task_progress |
| TEACH   | /task-manager skill    | Subcommand router for user interaction        |
| CONNECT | Rule file              | CLAUDE.md-level guidance for session behavior |

## Verification

```bash
# Check hook is registered
cat "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json" | grep -A2 "TodoWrite"

# Check MCP server is registered
cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep -A5 "task-system"
```

## Data Directory

`.tasks/` is created automatically at the project root (git root) on the first TodoWrite event. Contains:
- `tasks.json` — Current task state
- `history.jsonl` — Append-only transition log
- `progress.md` — Session summaries (newest at top)

## Troubleshooting

- **Tasks not saved**: Check hooks.json includes TodoWrite hook, check hook script exists and is executable.
- **/task-manager restore shows no tasks**: Verify you are in the correct project directory, check `.tasks/tasks.json` exists.
- **MCP tools not available**: Check plugin.json, restart Claude Code to reinitialize MCP servers.
- **Duplicate tasks after restore**: Should not happen (deterministic IDs). Run `/task-manager validate`.
