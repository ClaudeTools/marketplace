#!/usr/bin/env bash
# analyse-metrics.sh — Query metrics.db for threshold tuning data

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
METRICS_DB="$PLUGIN_ROOT/data/metrics.db"

if [ ! -f "$METRICS_DB" ]; then
  echo "No metrics.db found. Run a few sessions first to collect data."
  exit 0
fi

echo "=== Recent Sessions (last 10) ==="
sqlite3 -header -column "$METRICS_DB" \
  "SELECT session_id, total_tool_calls, total_failures, total_edits, unique_files_edited,
   ROUND(edit_churn_rate, 2) as churn, tasks_completed, ROUND(duration_minutes, 1) as mins, project_type, timestamp
   FROM session_metrics ORDER BY timestamp DESC LIMIT 10"

echo ""
echo "=== Current Thresholds ==="
sqlite3 -header -column "$METRICS_DB" \
  "SELECT metric_name, default_value, current_value, min_bound, max_bound, last_updated, reason
   FROM threshold_overrides"

echo ""
echo "=== Aggregate Stats (last 30 days) ==="
sqlite3 -header -column "$METRICS_DB" \
  "SELECT COUNT(*) as sessions,
   ROUND(AVG(edit_churn_rate), 2) as avg_churn,
   ROUND(AVG(CAST(total_failures AS REAL) / MAX(total_tool_calls, 1)), 4) as avg_failure_rate,
   SUM(total_failures) as total_failures,
   SUM(tasks_completed) as total_tasks
   FROM session_metrics
   WHERE timestamp > datetime('now', '-30 days')"

echo ""
echo "=== Top Failing Tools (last 30 days) ==="
sqlite3 -header -column "$METRICS_DB" \
  "SELECT tool_name, COUNT(*) as failures
   FROM tool_outcomes
   WHERE success = 0 AND timestamp > datetime('now', '-30 days')
   GROUP BY tool_name ORDER BY failures DESC LIMIT 5"
