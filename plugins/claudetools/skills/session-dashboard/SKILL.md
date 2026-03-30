---
name: session-dashboard
description: >
  Generate a human-readable report of claudetools system health, session metrics,
  success rates, failure patterns, and token efficiency. Use when asked for
  session stats, health reports, or plugin metrics.
argument-hint: "[current|summary|all]"
allowed-tools: Glob, Grep, LS, Read, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: observability
  tags: [dashboard, metrics, health, session, report]
---

# Session Dashboard

Generate a report of claudetools system health and session metrics.

## When to Use

- "How is the plugin performing?"
- "Show me session stats"
- "What's the hook success rate?"
- After a long session to review what happened

## Process

Run: `bash ${CLAUDE_SKILL_DIR}/scripts/generate-report.sh`

The report covers:
- Session duration and tool call counts
- Hook decision breakdown (allow/warn/block rates)
- Failure patterns and repeated errors
- Token efficiency metrics
