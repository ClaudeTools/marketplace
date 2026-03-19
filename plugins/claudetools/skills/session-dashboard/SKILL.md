---
name: session-dashboard
description: Generate a human-readable report of claudetools system health, session metrics, success rates, failure patterns, and token efficiency. Use when the user says dashboard, show metrics, system health, session stats, how am I doing, or performance report.
argument-hint: [last-N-sessions]
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
metadata:
  author: Owen Innes
  version: 1.1.0
  category: meta
  tags: [metrics, dashboard, analytics, health]
---

# Session Dashboard

Generate a health report for the claudetools plugin system.

## Examples

| User says | What to do |
|---|---|
| `/session-dashboard` | Show report for last 10 sessions |
| `/session-dashboard 5` | Show report for last 5 sessions |
| `how am I doing` | Same as `/session-dashboard` |
| `show metrics` | Same as `/session-dashboard` |
| `session stats` | Same as `/session-dashboard` |

## Workflow

1. Run the report generator:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/generate-report.sh ${ARGUMENTS:-10}
```

2. Present the output as a formatted report. Explain each section:

### Session Summary
- **avg_tool_calls**: Average tool uses per session. Typical range: 20-100. Higher = more active sessions.
- **avg_failures**: Average failed tool calls per session. Under 3 is healthy. Above 5 suggests the agent is struggling.
- **avg_edits**: Average file edits per session. Context-dependent — a refactoring session naturally has more.
- **avg_churn**: Edit churn rate — how often the same file gets re-edited. Under 2.0 is good. Above 3.0 means files are being edited repeatedly (trial-and-error instead of plan-first).
- **avg_tasks**: Tasks completed per session. Higher = more structured work.
- **avg_duration_min**: Session length in minutes.

### Failure Rate Trend
Shows daily failure percentages over the last 7 days. Look for:
- **Improving**: failure_pct decreasing over time — guardrails are working.
- **Degrading**: failure_pct increasing — investigate the failing tools.
- **Stable low** (<5%): healthy system.

### Top Failing Tools
Which tools fail most often. Common causes:
- **Edit**: file path wrong, content mismatch — the agent may need to read before editing.
- **Bash**: command errors, permission issues, or blocked by safety hooks.
- **Write**: file already exists, path issues.

### Current Thresholds
Adaptive guardrail thresholds. "modified" means the value has been tuned from its default. Use `/tune-thresholds` to adjust these.

### Recommendations
Automated suggestions based on metrics patterns. Act on these if present.

## Edge cases

- **No metrics.db**: Tell the user: "No session data collected yet. Metrics will appear after a few sessions with claudetools active."
- **Empty sessions table**: Tell the user: "No sessions recorded yet. Data will appear after sessions complete."
- **sqlite3 not installed**: Tell the user: "sqlite3 is required for metrics. Install it with: apt install sqlite3 (Linux) or brew install sqlite3 (macOS)."
- **Very few sessions (<3)**: Note that recommendations may not be reliable with limited data.
