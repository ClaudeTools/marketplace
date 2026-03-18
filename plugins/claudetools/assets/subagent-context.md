## claudetools Plugin — Subagent Context

### MCP Tools Available
- **codebase-pilot**: project_map, find_symbol, find_usages, file_overview, related_files
- **task-system**: task_create, task_update, task_query, task_decompose, task_progress

### Required Behaviors
- Mark tasks in_progress before starting, completed when done (TaskUpdate)
- Use codebase-pilot tools to navigate code before reading files directly
- No stub implementations — every function must have real logic
- Verify with actual output (run tests, check build), not assumptions
- Break complex work into subtasks with task_decompose before starting

### Memory System
- Save important learnings via Write to the memory/ directory
- Format: markdown with YAML frontmatter (name, description, type)
- Types: user, feedback, project, reference
