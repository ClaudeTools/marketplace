#!/usr/bin/env bash
# aggregate-session.sh — SessionEnd hook: compute session-level metrics
# Runs async at session end. Always exits 0.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/detect-project.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"

# sqlite3 required
if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

# Read hook input from stdin
INPUT=$(cat)
MODEL_FAMILY=$(detect_model_family)

session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

if [ -z "$session_id" ]; then
  exit 0
fi

# Ensure DB exists
ensure_metrics_db || exit 0

# Query tool_outcomes for this session (parameterised queries)
total_calls=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(*) FROM tool_outcomes WHERE session_id=?1;" \
  "$session_id" 2>/dev/null) || total_calls=0

total_failures=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(*) FROM tool_outcomes WHERE session_id=?1 AND success=0;" \
  "$session_id" 2>/dev/null) || total_failures=0

total_edits=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(*) FROM tool_outcomes WHERE session_id=?1 AND tool_name IN ('Edit','Write');" \
  "$session_id" 2>/dev/null) || total_edits=0

unique_files=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(DISTINCT file_path) FROM tool_outcomes WHERE session_id=?1 AND file_path != '' AND file_path IS NOT NULL;" \
  "$session_id" 2>/dev/null) || unique_files=0

# Compute edit churn rate (edits / unique files)
if [ "$unique_files" -gt 0 ] 2>/dev/null; then
  churn_rate=$(awk "BEGIN {printf \"%.2f\", ${total_edits} / ${unique_files}}")
else
  churn_rate="0.00"
fi

# Count completed tasks from ~/.claude/tasks/
tasks_completed=0
SESSION_MARKER="/tmp/.claude-session-start-${session_id}"
if [ -d "$HOME/.claude/tasks" ] && [ -f "$SESSION_MARKER" ]; then
  tasks_completed=$(find "$HOME/.claude/tasks" -name '*.json' -newer "$SESSION_MARKER" -exec grep -l '"status".*"completed"' {} + 2>/dev/null \
    | wc -l \
    | tr -d ' ') || tasks_completed=0
fi

# Detect project type
detect_project_type
project_type="${PROJECT_TYPE:-general}"
# Insert session metrics (parameterised query)
sqlite3 "$METRICS_DB" \
  "INSERT INTO session_metrics (session_id, total_tool_calls, total_failures, total_edits, unique_files_edited, edit_churn_rate, tasks_completed, project_type, timestamp)
   VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, datetime('now'));" \
  "$session_id" "${total_calls:-0}" "${total_failures:-0}" "${total_edits:-0}" "${unique_files:-0}" "$churn_rate" "${tasks_completed:-0}" "$project_type" \
  2>/dev/null || true

hook_log "session=${session_id} calls=${total_calls} failures=${total_failures} edits=${total_edits} files=${unique_files} churn=${churn_rate}"

# Clean up old tool_outcomes
RETENTION_DAYS=$(get_threshold "outcome_retention_days")
RETENTION_DAYS=${RETENTION_DAYS%.*}
sqlite3 "$METRICS_DB" \
  "DELETE FROM tool_outcomes WHERE timestamp < datetime('now', '-${RETENTION_DAYS} days');" \
  2>/dev/null || true

exit 0
