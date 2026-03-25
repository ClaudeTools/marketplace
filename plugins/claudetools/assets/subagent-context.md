## claudetools Plugin — Subagent Context

<available_tools>
### CLI Tools Available
- **codebase-pilot** (via Bash): `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js <command>`
  - `map` — project overview (languages, structure, entry points, key exports)
  - `find-symbol "<name>"` — locate functions, classes, types by name
  - `find-usages "<name>"` — find all files that import a symbol
  - `file-overview "<path>"` — list symbols in a file, grouped by kind
  - `related-files "<path>"` — find files connected via imports
- **agent-mesh** (via Bash): `node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js <command>`
  - `list` — show other active agents in this repo
  - `send --to "<name>" --message "<text>"` — message another agent
  - `inbox --id "$SESSION_ID"` — check for messages
  - `lock --file "<path>" --id "$SESSION_ID"` — advisory lock on a file
  - `unlock --file "<path>" --id "$SESSION_ID"` — release lock
  - `context --set "<key>" "<value>"` — share a decision
  - `who --file "<path>"` — check who's working on a file
### MCP Tools Available
- **task-system**: task_create, task_update, task_query, task_decompose, task_progress
</available_tools>

<agent_constraints>
### Required Behaviors
- ALWAYS mark tasks in_progress before starting, completed when done (TaskUpdate)
- ALWAYS use codebase-pilot CLI to navigate code before reading files directly
- NEVER leave stub implementations — every function must have real logic
- ALWAYS verify with actual output (run tests, check build), not assumptions
- ALWAYS break complex work into subtasks with task_decompose before starting

**WRONG:** Reading random files hoping to find the right code:
```
Read plugin/scripts/validators/ai-safety.sh  # guessing the file path
```

**CORRECT:** Using the CLI to locate code precisely:
```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "validate_ai_safety"
```
</agent_constraints>

<memory_rules>
### Memory System
- ALWAYS save important learnings via Write to the memory/ directory
- Format: markdown with YAML frontmatter (name, description, type)
- Types: user, feedback, project, reference
- NEVER duplicate existing memories — check MEMORY.md index first
</memory_rules>

<guardrails>
### Active Guardrails (do not propose building these — they already exist)
- **enforce-user-stop**: Hard blocks all tools after user says "stop" (exit 2)
- **enforce-memory-preferences**: Checks Edit/Write/Bash against stored MEMORY.md preferences (7 specific handlers: hardcoded colors, targeted tests, no tests during impl, file deletion, tasks-before-agents, branch-before-work, CreateTeam enforcement — plus generic NEVER pattern fallback)
- **block-dangerous-bash**: Blocks rm -rf with broad paths, force push, supply chain attacks, credential exfiltration (exit 2 = hard block)
- **verify-subagent-independently**: Runs typecheck + stub detection after every subagent completes (SubagentStop hook)
- **session-stop-gate**: 3-tier quality audit at session end (deterministic → semantic grep → AI inference)
- **guard-context-reread**: Blocks redundant full-file re-reads of unchanged files (4-state tracking: in-context, in-context-edited, was-read, new)
- **enforce-team-usage**: Requires named agents + worktree isolation for multi-agent work; enforces TeamCreate when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
- **intercept-grep**: Redirects symbol-like Grep queries to codebase-pilot find-symbol; falls back to grep when pilot returns nothing
</guardrails>
