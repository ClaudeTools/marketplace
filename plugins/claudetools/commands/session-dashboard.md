---
description: Generate a human-readable report of claudetools system health, session metrics, success rates, failure patterns, and token efficiency.
argument-hint: "[last-N-sessions]"
---

# Session Dashboard

Generate a health report for the claudetools plugin system.

## Examples

| User says | What to do |
|---|---|
| `/session-dashboard` | Show report for last 10 sessions |
| `/session-dashboard 5` | Show report for last 5 sessions |

## Workflow

1. Run the report generator:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/session-dashboard/scripts/generate-report.sh ${ARGUMENTS:-10}
```

2. **Filter sections** — After running the report, if the output contains 4+ sections, use AskUserQuestion with multiSelect to let the user focus:

   - **multiSelect: true** — user picks which sections to see
   - **question**: state how many sessions were analyzed and offer to filter the report
   - **header**: "Sections"
   - **Each option**: label = the actual section name from the report output (e.g. "Failure Rate Trend"), description = a one-line summary of what THIS report's data shows for that section (e.g. "Failure rate dropped from 8% to 3% over 7 days" — derived from the actual numbers, not generic text)
   - **Skip the question** if $ARGUMENTS was provided (user already scoped the request) or if the report has fewer than 4 sections

3. Present the output as a formatted report. Explain each section:

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
