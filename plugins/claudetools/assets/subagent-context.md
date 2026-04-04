## claudetools — Subagent Tools

**srcpilot** (Bash): `srcpilot <cmd>` — map, find-symbol, find-usages, file-overview, related-files, navigate, dead-code, change-impact, context-budget, circular-deps, index-file

**task-system** (MCP): task_create, task_update, task_query, task_decompose, task_progress

### Required
- Mark tasks in_progress before starting, completed when done
- Use `srcpilot find-symbol "<name>"` before reading files — never guess paths
- No stub implementations — every function needs real logic
- Verify with actual output (tests/build), not assumptions

### Guardrails active
enforce-user-stop · block-dangerous-bash · verify-subagent-independently · session-stop-gate · guard-context-reread · enforce-team-usage · intercept-grep · enforce-memory-preferences
