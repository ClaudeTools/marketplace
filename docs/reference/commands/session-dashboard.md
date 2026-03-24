---
title: /session-dashboard
parent: Slash Commands
grand_parent: Reference
nav_order: 2
---

# /session-dashboard

Generate a human-readable health report of the claudetools plugin system — session metrics, success rates, failure patterns, and token efficiency.

## Invocation

```
/session-dashboard [N]
```

**Arguments:**
- `N` — number of recent sessions to include (default: 10)

## Output Sections

### Session Summary
Key metrics per session:
- `avg_tool_calls` — typical range 20-100
- `avg_failures` — under 3 is healthy; above 5 suggests struggling
- `avg_churn` — edit churn rate; under 2.0 is good, above 3.0 indicates trial-and-error
- `avg_tasks` — tasks completed per session

### Failure Rate Trend
Daily failure percentages over the last 7 days. Improving trend means guardrails are working.

### Top Failing Tools
Which tools fail most often and likely causes (e.g., Edit failing = agent not reading before editing).

### Current Thresholds
Adaptive guardrail thresholds. "modified" entries have been tuned from defaults.

### Recommendations
Automated suggestions based on metric patterns.

## Examples

```
/session-dashboard
/session-dashboard 5
/session-dashboard 20
```

## Edge Cases

- **No metrics.db** — metrics appear after a few sessions with claudetools active.
- **sqlite3 not installed** — install with `apt install sqlite3` or `brew install sqlite3`.
- **Fewer than 3 sessions** — recommendations may not be reliable with limited data.
