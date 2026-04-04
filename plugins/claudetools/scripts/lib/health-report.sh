#!/usr/bin/env bash
# health-report.sh — Query metrics.db for plugin health indicators
#
# Callers must export METRICS_DB before sourcing, or set CLAUDE_PLUGIN_ROOT so
# the path helpers below can locate the database automatically.
#
# Optional exports honoured by the field-review sections:
#   EVENTS_FILE   — path to logs/events.jsonl
#   HOOKS_JSON    — path to hooks/hooks.json
#   PLUGIN_JSON   — path to .claude-plugin/plugin.json
#   CHANGELOG     — path to CHANGELOG.md
#   _versioned_root — versioned install root (for hooks.json / plugin.json)

# ── Internal path helpers ─────────────────────────────────────────────────────

_hr_versioned_root() {
  echo "${_versioned_root:-${CLAUDE_PLUGIN_ROOT:-}}"
}

_hr_plugin_root() {
  local vroot
  vroot="$(_hr_versioned_root)"
  # Strip version suffix when inside a versioned cache path
  if [[ "$vroot" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$(dirname "$vroot")"
  else
    echo "$vroot"
  fi
}

_hr_metrics_db() {
  echo "${METRICS_DB:-$(_hr_plugin_root)/data/metrics.db}"
}

_hr_events_file() {
  echo "${EVENTS_FILE:-$(_hr_plugin_root)/logs/events.jsonl}"
}

_hr_hooks_json() {
  echo "${HOOKS_JSON:-$(_hr_versioned_root)/hooks/hooks.json}"
}

_hr_plugin_json() {
  echo "${PLUGIN_JSON:-$(_hr_versioned_root)/.claude-plugin/plugin.json}"
}

_hr_changelog() {
  echo "${CHANGELOG:-$(_hr_versioned_root)/CHANGELOG.md}"
}

# ── Field-review: plugin metadata ────────────────────────────────────────────

# plugin_info — Print plugin version, OS, and model family
plugin_info() {
  local plugin_json
  plugin_json="$(_hr_plugin_json)"

  echo "=== PLUGIN INFO ==="
  if [ -f "$plugin_json" ]; then
    local version
    version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$plugin_json" 2>/dev/null \
      | grep -o '"[^"]*"$' | tr -d '"' || echo "unknown")
    echo "version: $version"
  else
    echo "version: unknown (plugin.json not found)"
  fi

  echo "os: $(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)"

  local model="${CLAUDE_MODEL:-unknown}"
  local model_family
  case "$model" in
    *opus*)   model_family="opus" ;;
    *sonnet*) model_family="sonnet" ;;
    *haiku*)  model_family="haiku" ;;
    *)        model_family="$model" ;;
  esac
  echo "model_family: $model_family"
}

# recent_changes [N_LINES] — Print the last N lines of CHANGELOG.md (default 60)
recent_changes() {
  local n="${1:-60}"
  local changelog
  changelog="$(_hr_changelog)"

  echo ""
  echo "=== RECENT CHANGES ==="
  if [ -f "$changelog" ]; then
    head -"$n" "$changelog" | tail -n +3
  else
    echo "No CHANGELOG.md found — version history unavailable"
  fi
}

# hook_inventory — Count hooks and list event types from hooks.json
hook_inventory() {
  local hooks_json
  hooks_json="$(_hr_hooks_json)"

  echo ""
  echo "=== HOOK INVENTORY ==="
  if [ -f "$hooks_json" ]; then
    local total_hooks
    total_hooks=$(grep -c '"command"' "$hooks_json" 2>/dev/null || echo "0")
    echo "total_configured_hooks: $total_hooks"
    grep -o '"event"[[:space:]]*:[[:space:]]*"[^"]*"' "$hooks_json" 2>/dev/null \
      | grep -o '"[^"]*"$' | tr -d '"' | sort | uniq -c | sort -rn \
      | while read -r count event; do echo "  $event: $count hooks"; done || true
  else
    echo "hooks.json not found"
  fi
}

# validator_inventory — List validator scripts from scripts/validators/
validator_inventory() {
  local vroot
  vroot="$(_hr_versioned_root)"

  echo ""
  echo "=== VALIDATORS ==="
  if [ -d "${vroot}/scripts/validators" ]; then
    ls -1 "${vroot}/scripts/validators/"*.sh 2>/dev/null | while read -r f; do
      echo "  $(basename "$f" .sh)"
    done || true
  else
    echo "no validators directory"
  fi
}

# skill_inventory — List skill directories from skills/
skill_inventory() {
  local vroot
  vroot="$(_hr_versioned_root)"

  echo ""
  echo "=== SKILLS ==="
  if [ -d "${vroot}/skills" ]; then
    ls -1d "${vroot}/skills/"*/ 2>/dev/null | while read -r d; do
      echo "  $(basename "$d")"
    done || true
  else
    echo "no skills directory"
  fi
}

# session_metrics [DAYS] — Aggregate session stats from session_metrics table
session_metrics() {
  local days="${1:-30}"
  local db
  db="$(_hr_metrics_db)"

  echo ""
  echo "=== SESSION METRICS (last ${days} days) ==="

  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available — skipping"; return 0; }
  [ -f "$db" ] || { echo "metrics.db not found — no data available"; return 0; }

  sqlite3 -separator '|' "$db" "
    SELECT COUNT(*) as sessions,
           ROUND(AVG(total_tool_calls), 1) as avg_tool_calls,
           ROUND(AVG(total_failures), 1) as avg_failures,
           ROUND(AVG(total_edits), 1) as avg_edits,
           ROUND(AVG(edit_churn_rate), 2) as avg_churn,
           ROUND(AVG(tasks_completed), 1) as avg_tasks,
           ROUND(AVG(duration_minutes), 1) as avg_duration_min
    FROM session_metrics
    WHERE timestamp > datetime('now', '-${days} days');
  " 2>/dev/null | while IFS='|' read -r sessions calls fails edits churn tasks dur; do
    echo "sessions: $sessions"
    echo "avg_tool_calls: $calls"
    echo "avg_failures: $fails"
    echo "avg_edits: $edits"
    echo "avg_churn: $churn"
    echo "avg_tasks_completed: $tasks"
    echo "avg_duration_min: $dur"
  done || true
}

# hook_outcomes [DAYS] — Per-hook block/warn/allow rates with FP percentage
hook_outcomes() {
  local days="${1:-30}"
  local db
  db="$(_hr_metrics_db)"

  echo ""
  echo "=== HOOK OUTCOMES (last ${days} days) ==="

  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available — skipping"; return 0; }
  [ -f "$db" ] || { echo "metrics.db not found — no data available"; return 0; }

  sqlite3 -separator '|' "$db" "
    SELECT hook_name,
           COUNT(*) as total,
           SUM(CASE WHEN decision='block' THEN 1 ELSE 0 END) as blocks,
           SUM(CASE WHEN decision='warn' THEN 1 ELSE 0 END) as warns,
           SUM(CASE WHEN decision='allow' THEN 1 ELSE 0 END) as allows,
           ROUND(SUM(CASE WHEN decision='block' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) as block_pct,
           ROUND(SUM(CASE WHEN classification='FP' THEN 1.0 ELSE 0 END) / NULLIF(SUM(CASE WHEN classification IS NOT NULL THEN 1 ELSE 0 END), 0) * 100, 1) as fp_pct
    FROM hook_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
    GROUP BY hook_name
    ORDER BY total DESC;
  " 2>/dev/null | while IFS='|' read -r name total blocks warns allows block_pct fp_pct; do
    echo "  $name: total=$total block=$blocks($block_pct%) warn=$warns allow=$allows fp_rate=${fp_pct:-n/a}%"
  done || true
}

# top_failing_tools [DAYS] [LIMIT] — Tools with highest failure counts
top_failing_tools() {
  local days="${1:-30}"
  local limit="${2:-10}"
  local db
  db="$(_hr_metrics_db)"

  echo ""
  echo "=== TOP FAILING TOOLS (last ${days} days) ==="

  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available — skipping"; return 0; }
  [ -f "$db" ] || { echo "metrics.db not found — no data available"; return 0; }

  sqlite3 -separator '|' "$db" "
    SELECT tool_name,
           SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failures,
           COUNT(*) as total,
           ROUND(SUM(CASE WHEN success = 0 THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) as fail_pct
    FROM tool_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
    GROUP BY tool_name
    HAVING failures > 0
    ORDER BY failures DESC
    LIMIT ${limit};
  " 2>/dev/null | while IFS='|' read -r tool failures total pct; do
    echo "  $tool: $failures failures / $total total ($pct%)"
  done || true
}

# threshold_status — Print current threshold overrides vs defaults
threshold_status() {
  local db
  db="$(_hr_metrics_db)"

  echo ""
  echo "=== THRESHOLD STATUS ==="

  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available — skipping"; return 0; }
  [ -f "$db" ] || { echo "metrics.db not found — no data available"; return 0; }

  sqlite3 -separator '|' "$db" "
    SELECT metric_name, default_value, current_value,
           CASE WHEN current_value != default_value THEN 'modified' ELSE 'default' END as status
    FROM threshold_overrides
    ORDER BY metric_name;
  " 2>/dev/null | while IFS='|' read -r metric default current status; do
    echo "  $metric: $current (default: $default) [$status]"
  done || true
}

# recent_errors [N] — Print last N tool_failure events from events.jsonl (default 20)
recent_errors() {
  local n="${1:-20}"
  local events_file
  events_file="$(_hr_events_file)"

  [ -f "$events_file" ] || return 0

  echo ""
  echo "=== RECENT ERRORS (from events.jsonl) ==="
  grep '"tool_failure"' "$events_file" 2>/dev/null | tail -"$n" | while read -r line; do
    local tool error_class
    tool=$(echo "$line" | grep -o '"tool":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    error_class=$(echo "$line" | grep -o '"error_class":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    [ -n "$tool" ] && echo "  $tool: $error_class"
  done || true
}

# ── Core health functions ─────────────────────────────────────────────────────

# stale_skills [DAYS] — Skills with zero invocations in past N days
stale_skills() {
  local days="${1:-30}"
  command -v sqlite3 &>/dev/null || { echo "sqlite3 not available"; return 0; }
  local db
  db="$(_hr_metrics_db)"
  [ -f "$db" ] || { echo "metrics.db not found"; return 0; }

  local active_skills
  active_skills=$(sqlite3 "$db" "
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
  local db
  db="$(_hr_metrics_db)"
  [ -f "$db" ] || { echo "metrics.db not found"; return 0; }

  echo "=== Validator Health (past ${days} days) ==="
  sqlite3 -header -column "$db" "
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
  local db
  db="$(_hr_metrics_db)"
  [ -f "$db" ] || { echo "metrics.db not found"; return 0; }

  echo "=== Dead Validators (0 triggers in ${days} days) ==="
  local active_validators
  active_validators=$(sqlite3 "$db" "
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

# ── Composite report functions ────────────────────────────────────────────────

# full_health_report [DAYS] — Core health: stale skills, FP rates, dead validators
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

# field_review_report [DAYS] — Full field-review report including all metric sections
field_review_report() {
  local days="${1:-30}"
  local db
  db="$(_hr_metrics_db)"

  plugin_info
  recent_changes

  hook_inventory
  validator_inventory
  skill_inventory

  if ! command -v sqlite3 &>/dev/null; then
    echo ""
    echo "=== METRICS ==="
    echo "sqlite3 not available — skipping quantitative metrics"
    echo "The review can still proceed with qualitative observations only."
    return 0
  fi

  if [ ! -f "$db" ]; then
    echo ""
    echo "=== METRICS ==="
    echo "metrics.db not found — no quantitative data available"
    echo "The review can still proceed with qualitative observations only."
    return 0
  fi

  session_metrics "$days"
  hook_outcomes "$days"
  top_failing_tools "$days"
  threshold_status
  recent_errors

  echo ""
  echo "=== DATA COLLECTION COMPLETE ==="
}
