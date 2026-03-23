---
name: tune-thresholds
description: Analyse session metrics and recommend guardrail threshold adjustments. Use when the user says tune thresholds, adjust sensitivity, review metrics, check guardrail performance, or why is this hook blocking me.
argument-hint: [metric-name]
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
metadata:
  author: Owen Innes
  version: 1.0.0
  category: meta
  tags: [self-learning, metrics, thresholds, guardrails]
---

# Threshold Tuner

Analyse metrics.db and recommend guardrail threshold adjustments based on session history.

## Workflow

1. Run the analysis script to gather metrics:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/analyse-metrics.sh
```

2. Review the output. It shows:
   - Recent session metrics (last 10 sessions)
   - Current threshold values vs defaults
   - Recommended adjustments based on patterns

3. Present findings to the user with:
   - Current values for each threshold
   - Evidence from session data (edit churn rate, failure patterns)
   - Recommended new values with reasoning
   - Safety bounds (thresholds can only drift within [0.5x, 2.0x] of defaults)

4. If the user approves changes, update thresholds in metrics.db:
```bash
sqlite3 "${CLAUDE_PLUGIN_ROOT}/data/metrics.db" "UPDATE threshold_overrides SET current_value = NEW_VALUE, last_updated = datetime('now'), reason = 'REASON' WHERE metric_name = 'METRIC_NAME'"
```

Do not adjust thresholds without user approval. Present evidence and recommendations, then ask.
