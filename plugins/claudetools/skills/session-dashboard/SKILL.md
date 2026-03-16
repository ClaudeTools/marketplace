---
name: session-dashboard
description: Generate a human-readable report of claudetools system health, session metrics, success rates, failure patterns, and token efficiency. Use when the user says dashboard, show metrics, system health, session stats, how am I doing, or performance report.
argument-hint: [last-N-sessions]
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
metadata:
  author: Owen Innes
  version: 1.0.0
  category: meta
  tags: [metrics, dashboard, analytics, health]
---

# Session Dashboard

Generate a health report for the claudetools plugin system.

## Workflow

1. Run the report generator:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/generate-report.sh ${ARGUMENTS:-10}
```

2. Present the output as a formatted report to the user. Include:
   - Session count and date range
   - Average metrics per session (tool calls, failures, edits, churn)
   - Failure rate trend (improving or degrading)
   - Most common failure tools
   - Current threshold values
   - Recommendations if metrics suggest issues

3. If metrics.db doesn't exist or has no data, tell the user: "No session data collected yet. Metrics will appear after a few sessions with claudetools active."
