#!/usr/bin/env bash
# health-report.sh — Query metrics.db for plugin health indicators

# stale_skills [DAYS] — Skills with zero invocations in past N days
stale_skills() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  [ -n "${METRICS_DB:-}" ] || { echo "METRICS_DB not set"; return 0; }

  local active_skills
  active_skills=$(sqlite3 "$METRICS_DB" "
    SELECT DISTINCT skill_name FROM skill_invocations
    WHERE timestamp > datetime('now', '-${days} days')
  " 2>/dev/null || true)

  local skill_dir="${CLAUDE_PLUGIN_ROOT:-}/skills"
  [ -d "$skill_dir" ] || return 0

  echo "=== Stale Skills (0 invocations in ${days} days) ==="
  local found=0
  for dir in "$skill_dir"/*/; do
    local name
    name=$(basename "$dir")
    if ! echo "$active_skills" | grep -qF "$name"; then
      echo "  - $name"
      found=$((found + 1))
    fi
  done
  [ "$found" -eq 0 ] && echo "  (none — all skills active)"
}

# validator_false_positives [DAYS] — Validator block/warn/allow rates
validator_false_positives() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  [ -n "${METRICS_DB:-}" ] || { echo "METRICS_DB not set"; return 0; }

  echo "=== Validator Health (past ${days} days) ==="
  sqlite3 -header -column "$METRICS_DB" "
    SELECT
      hook_name,
      SUM(CASE WHEN decision = 'block' THEN 1 ELSE 0 END) as blocks,
      SUM(CASE WHEN decision = 'warn' THEN 1 ELSE 0 END) as warns,
      SUM(CASE WHEN decision = 'allow' THEN 1 ELSE 0 END) as allows,
      COUNT(*) as total,
      ROUND(100.0 * SUM(CASE WHEN decision = 'block' THEN 1 ELSE 0 END) / COUNT(*), 1) as block_pct
    FROM hook_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
      AND event_type IN ('PreToolUse', 'PostToolUse', 'TaskCompleted')
    GROUP BY hook_name
    HAVING total >= 5
    ORDER BY block_pct DESC
  " 2>/dev/null || echo "  (no data yet)"
}

# dead_validators [DAYS] — Validators with 0 triggers
dead_validators() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  [ -n "${METRICS_DB:-}" ] || { echo "METRICS_DB not set"; return 0; }

  echo "=== Dead Validators (0 triggers in ${days} days) ==="
  local active_validators
  active_validators=$(sqlite3 "$METRICS_DB" "
    SELECT DISTINCT hook_name FROM hook_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
  " 2>/dev/null || true)

  local validator_dir="${CLAUDE_PLUGIN_ROOT:-}/scripts/validators"
  [ -d "$validator_dir" ] || return 0

  local found=0
  for f in "$validator_dir"/*.sh; do
    local name
    name=$(basename "$f" .sh)
    if ! echo "$active_validators" | grep -qF "$name"; then
      echo "  - $name"
      found=$((found + 1))
    fi
  done
  [ "$found" -eq 0 ] && echo "  (none — all validators active)"
}

# full_health_report [DAYS]
full_health_report() {
  local days="${1:-30}"
  echo "Plugin Health Report (past ${days} days)"
  echo "========================================"
  echo ""
  stale_skills "$days"
  echo ""
  validator_false_positives "$days"
  echo ""
  dead_validators "$days"
}
