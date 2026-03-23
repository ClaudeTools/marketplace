#!/usr/bin/env bash
# Validator: session metrics aggregator
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Calls: ensure_metrics_db, get_threshold, detect_project_type, hook_log
# Returns: 0 always (side-effect runner)

run_aggregate_session() {
  # sqlite3 required
  if ! command -v sqlite3 &>/dev/null; then
    return 0
  fi

  local session_id
  session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

  if [ -z "$session_id" ]; then
    return 0
  fi

  # Ensure DB exists
  ensure_metrics_db || return 0

  # Query tool_outcomes for this session (parameterised queries)
  local total_calls
  total_calls=$(sqlite3 "$METRICS_DB" \
    "SELECT COUNT(*) FROM tool_outcomes WHERE session_id=?1;" \
    "$session_id" 2>/dev/null) || total_calls=0

  local total_failures
  total_failures=$(sqlite3 "$METRICS_DB" \
    "SELECT COUNT(*) FROM tool_outcomes WHERE session_id=?1 AND success=0;" \
    "$session_id" 2>/dev/null) || total_failures=0

  local total_edits
  total_edits=$(sqlite3 "$METRICS_DB" \
    "SELECT COUNT(*) FROM tool_outcomes WHERE session_id=?1 AND tool_name IN ('Edit','Write');" \
    "$session_id" 2>/dev/null) || total_edits=0

  local unique_files
  unique_files=$(sqlite3 "$METRICS_DB" \
    "SELECT COUNT(DISTINCT file_path) FROM tool_outcomes WHERE session_id=?1 AND file_path != '' AND file_path IS NOT NULL;" \
    "$session_id" 2>/dev/null) || unique_files=0

  # Compute edit churn rate (edits / unique files)
  local churn_rate
  if [ "$unique_files" -gt 0 ] 2>/dev/null; then
    churn_rate=$(awk "BEGIN {printf \"%.2f\", ${total_edits} / ${unique_files}}")
  else
    churn_rate="0.00"
  fi

  # Count completed tasks from ~/.claude/tasks/
  local tasks_completed=0
  local SESSION_MARKER="/tmp/.claude-session-start-${session_id}"
  if [ -d "$HOME/.claude/tasks" ] && [ -f "$SESSION_MARKER" ]; then
    tasks_completed=$(find "$HOME/.claude/tasks" -name '*.json' -newer "$SESSION_MARKER" -exec grep -l '"status".*"completed"' {} + 2>/dev/null \
      | wc -l \
      | tr -d ' ') || tasks_completed=0
  fi

  # Detect project type
  detect_project_type
  local project_type="${PROJECT_TYPE:-general}"

  # Insert session metrics (parameterised query)
  sqlite3 "$METRICS_DB" \
    "INSERT INTO session_metrics (session_id, total_tool_calls, total_failures, total_edits, unique_files_edited, edit_churn_rate, tasks_completed, project_type, timestamp)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, datetime('now'));" \
    "$session_id" "${total_calls:-0}" "${total_failures:-0}" "${total_edits:-0}" "${unique_files:-0}" "$churn_rate" "${tasks_completed:-0}" "$project_type" \
    2>/dev/null || true

  hook_log "session=${session_id} calls=${total_calls} failures=${total_failures} edits=${total_edits} files=${unique_files} churn=${churn_rate}"

  # Clean up old tool_outcomes
  local RETENTION_DAYS
  RETENTION_DAYS=$(get_threshold "outcome_retention_days")
  RETENTION_DAYS=${RETENTION_DAYS%.*}
  sqlite3 "$METRICS_DB" \
    "DELETE FROM tool_outcomes WHERE timestamp < datetime('now', '-${RETENTION_DAYS} days');" \
    2>/dev/null || true

  return 0
}
