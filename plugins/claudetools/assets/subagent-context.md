## claudetools Plugin — Subagent Context

<available_tools>
### MCP Tools Available
- **codebase-pilot**: project_map, find_symbol, find_usages, file_overview, related_files
- **task-system**: task_create, task_update, task_query, task_decompose, task_progress
</available_tools>

<agent_constraints>
### Required Behaviors
- ALWAYS mark tasks in_progress before starting, completed when done (TaskUpdate)
- ALWAYS use codebase-pilot tools to navigate code before reading files directly
- NEVER leave stub implementations — every function must have real logic
- ALWAYS verify with actual output (run tests, check build), not assumptions
- ALWAYS break complex work into subtasks with task_decompose before starting

**WRONG:** Reading random files hoping to find the right code:
```
Read plugin/scripts/validators/ai-safety.sh  # guessing the file path
```

**CORRECT:** Using codebase-pilot to locate code precisely:
```
find_symbol "validate_ai_safety"  # finds exact file and line
```
</agent_constraints>

<memory_rules>
### Memory System
- ALWAYS save important learnings via Write to the memory/ directory
- Format: markdown with YAML frontmatter (name, description, type)
- Types: user, feedback, project, reference
- NEVER duplicate existing memories — check MEMORY.md index first
</memory_rules>
