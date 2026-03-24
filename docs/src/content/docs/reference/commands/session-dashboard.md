---
title: "/session-dashboard"
description: "Plugin health report command — session metrics, hook success rates, failure patterns, and token efficiency in a single readable summary."
---

> **Status:** 🆕 New in v4.0 — migrated to native command format in the v4.0.0 release

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

## Quick example

```
/session-dashboard
```

**Claude responds:**

```
claudetools Session Health — last 10 sessions

Session Summary
  avg_tool_calls  42   (healthy range: 20–100)
  avg_failures     1.2  ✓  (under 3 is healthy)
  avg_churn        1.4  ✓  (under 2.0 is good)
  avg_tasks        3.1

Failure Rate Trend (last 7 days)
  Mon  2.1%   Tue  1.8%   Wed  3.4%   Thu  1.1%   Fri  0.9%
  ↓ Improving

Top Failing Tools
  Edit  — 4 failures   (likely cause: editing without reading first)
  Bash  — 2 failures   (exit 1 — see individual session logs)

Current Thresholds
  uncommitted_file_limit   10   (default)
  failure_loop_limit        3   (default)
  bulk_edit_limit           5   (modified ↑ from 3)

Recommendations
  ✓ No issues detected. Session quality looks healthy.
```

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

## Related

- [Reference: /logs command](logs.md) — query raw conversation history and tool usage across sessions
- [Reference: /field-review command](field-review.md) — audit hook decisions for false positives
- [Installation](/getting-started/installation/) — verify hooks are registered after install
