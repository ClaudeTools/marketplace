#!/usr/bin/env bash
# generate-report.sh — Generate human-readable session health report
# Usage: bash generate-report.sh [num-sessions]

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
METRICS_DB="$PLUGIN_ROOT/data/metrics.db"
LIMIT="${1:-10}"

if [ ! -f "$METRICS_DB" ]; then
  echo "No metrics data available yet."
  exit 0
fi

SESSION_COUNT=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM session_metrics" 2>/dev/null || echo "0")
if [ "$SESSION_COUNT" -eq 0 ]; then
  echo "No sessions recorded yet. Data will appear after sessions complete."
  exit 0
fi

echo "=== claudetools Health Report ==="
echo "Sessions analysed: $LIMIT most recent (of $SESSION_COUNT total)"
echo ""

echo "--- Session Summary ---"
sqlite3 -header -column "$METRICS_DB" \
  "SELECT
    ROUND(AVG(total_tool_calls), 0) as avg_tool_calls,
    ROUND(AVG(total_failures), 1) as avg_failures,
    ROUND(AVG(total_edits), 0) as avg_edits,
    ROUND(AVG(edit_churn_rate), 2) as avg_churn,
    ROUND(AVG(tasks_completed), 1) as avg_tasks,
    ROUND(AVG(duration_minutes), 0) as avg_duration_min
  FROM (SELECT * FROM session_metrics ORDER BY timestamp DESC LIMIT $LIMIT)"
echo ""

echo "--- Failure Rate Trend ---"
sqlite3 -header -column "$METRICS_DB" \
  "SELECT
    DATE(timestamp) as date,
    COUNT(*) as sessions,
    SUM(total_failures) as failures,
    SUM(total_tool_calls) as calls,
    ROUND(CAST(SUM(total_failures) AS REAL) / MAX(SUM(total_tool_calls), 1) * 100, 1) as failure_pct
  FROM session_metrics
  WHERE timestamp > datetime('now', '-30 days')
  GROUP BY DATE(timestamp)
  ORDER BY date DESC
  LIMIT 7"
echo ""

echo "--- Top Failing Tools ---"
sqlite3 -header -column "$METRICS_DB" \
  "SELECT tool_name, COUNT(*) as total_failures
   FROM tool_outcomes
   WHERE success = 0
   GROUP BY tool_name
   ORDER BY total_failures DESC
   LIMIT 5"
echo ""

echo "--- Current Thresholds ---"
sqlite3 -header -column "$METRICS_DB" \
  "SELECT metric_name, current_value, default_value,
    CASE WHEN current_value != default_value THEN 'modified' ELSE 'default' END as status
   FROM threshold_overrides"
echo ""

# Recommendations
AVG_CHURN=$(sqlite3 "$METRICS_DB" \
  "SELECT ROUND(AVG(edit_churn_rate), 2) FROM (SELECT * FROM session_metrics ORDER BY timestamp DESC LIMIT $LIMIT)" 2>/dev/null || echo "0")
AVG_FAILURES=$(sqlite3 "$METRICS_DB" \
  "SELECT ROUND(AVG(total_failures), 1) FROM (SELECT * FROM session_metrics ORDER BY timestamp DESC LIMIT $LIMIT)" 2>/dev/null || echo "0")

echo "--- Recommendations ---"
if [ "$(echo "$AVG_CHURN > 3.0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "- High edit churn ($AVG_CHURN avg). Consider adding diagnostics before editing."
fi
if [ "$(echo "$AVG_FAILURES > 5.0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "- Elevated failure rate ($AVG_FAILURES avg). Research before implementing."
fi
if [ "$AVG_CHURN" = "0" ] && [ "$AVG_FAILURES" = "0" ]; then
  echo "- No issues detected. System operating normally."
fi
