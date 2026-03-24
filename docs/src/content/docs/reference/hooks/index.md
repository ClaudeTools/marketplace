---
title: "Hooks"
description: "51 hooks across 17 lifecycle events — complete index organized by category with event names, severity, and link to detailed reference."
---
51 hooks across 17 lifecycle events. Guardrails that run automatically on every tool call.

## What hooks protect you from

Without hooks, Claude Code operates without guardrails — it can run destructive shell commands, overwrite files it hasn't read, commit half-finished work, or write secrets directly into your source. Hooks intercept every tool call before and after it executes, so those mistakes are caught automatically rather than discovered after the fact. You don't need to remember to check; the hooks run whether you think about them or not.

## Lifecycle Events

| Event | Hooks | When it fires |
|-------|-------|---------------|
| PreToolUse | 8 | Before any tool executes |
| PostToolUse | 12 | After a tool completes |
| PostToolUseFailure | 2 | After a tool fails |
| TaskCompleted | 1 | When a task is marked done |
| TeammateIdle | 2 | When a spawned teammate goes idle |
| SubagentStart | 2 | When a subagent is created |
| SubagentStop | 2 | When a subagent finishes |
| SessionStart | 5 | At the beginning of a session |
| SessionEnd | 3 | At the end of a session |
| Stop | 4 | When the user stops the session |
| UserPromptSubmit | 1 | When the user sends a message |
| PermissionRequest | 1 | When a permission prompt appears |
| ConfigChange | 2 | When configuration changes |
| WorktreeCreate | 3 | When a worktree is created |
| PreCompact | 1 | Before context compaction |
| PostCompact | 1 | After context compaction |
| Notification | 1 | On permission/idle notifications |

## Categories

Hooks are organized into 4 categories by purpose:

- [**Safety**](/reference/hooks/safety-hooks/) — Blocks destructive commands, hardcoded secrets, sensitive file access
- [**Quality**](/reference/hooks/quality-hooks/) — Catches stubs, type abuse, edit churn, incomplete work
- [**Process**](/reference/hooks/process-hooks/) — Enforces read-before-edit, commit hygiene, scope discipline
- [**Context**](/reference/hooks/context-hooks/) — Prevents redundant reads, injects memory, tracks telemetry

---

## Related

- [Core Concepts — Hooks](/getting-started/core-concepts/#hooks) — introduction to hooks and their four categories
- [Configuration](/advanced/configuration/) — tune hook thresholds and quiet mode
- [Advanced: Validators](/advanced/validators/) — companion validators that run alongside hooks
