#!/usr/bin/env bash
# collect-metrics.sh — Gather local plugin usage data for the review skill
# Queries metrics.db and events.jsonl to provide quantitative context.
# Output: structured text sections the agent can reference during reflection.

set -euo pipefail

_plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)}"

# Versioned install path — use parent directory for stable data dir
if [[ "$_plugin_root" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  _plugin_root="$(dirname "$_plugin_root")"
fi

METRICS_DB="${_plugin_root}/data/metrics.db"
EVENTS_FILE="${_plugin_root}/logs/events.jsonl"
HOOKS_JSON="${_plugin_root}/hooks/hooks.json"
PLUGIN_JSON="${_plugin_root}/.claude-plugin/plugin.json"

# ── Plugin metadata ──────────────────────────────────────────────────
echo "=== PLUGIN INFO ==="
if [ -f "$PLUGIN_JSON" ]; then
  version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"' || echo "unknown")
  echo "version: $version"
else
  echo "version: unknown (plugin.json not found)"
fi

# OS and environment
echo "os: $(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)"
echo "model_family: ${MODEL_FAMILY:-unknown}"

# ── Hook inventory ───────────────────────────────────────────────────
echo ""
echo "=== HOOK INVENTORY ==="
if [ -f "$HOOKS_JSON" ]; then
  total_hooks=$(grep -c '"command"' "$HOOKS_JSON" 2>/dev/null || echo "0")
  echo "total_configured_hooks: $total_hooks"
  # List hook event types
  grep -o '"event"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOOKS_JSON" 2>/dev/null \
    | grep -o '"[^"]*"$' | tr -d '"' | sort | uniq -c | sort -rn \
    | while read -r count event; do echo "  $event: $count hooks"; done
else
  echo "hooks.json not found"
fi

# ── Validator inventory ──────────────────────────────────────────────
echo ""
echo "=== VALIDATORS ==="
if [ -d "${_plugin_root}/scripts/validators" ]; then
  ls -1 "${_plugin_root}/scripts/validators/"*.sh 2>/dev/null | while read -r f; do
    echo "  $(basename "$f" .sh)"
  done
else
  echo "no validators directory"
fi

# ── Skill inventory ─────────────────────────────────────────────────
echo ""
echo "=== SKILLS ==="
if [ -d "${_plugin_root}/skills" ]; then
  ls -1d "${_plugin_root}/skills/"*/ 2>/dev/null | while read -r d; do
    name=$(basename "$d")
    echo "  $name"
  done
else
  echo "no skills directory"
fi

# ── Metrics DB queries ───────────────────────────────────────────────
if ! command -v sqlite3 &>/dev/null; then
  echo ""
  echo "=== METRICS ==="
  echo "sqlite3 not available — skipping quantitative metrics"
  echo "The review can still proceed with qualitative observations only."
  exit 0
fi

if [ ! -f "$METRICS_DB" ]; then
  echo ""
  echo "=== METRICS ==="
  echo "metrics.db not found — no quantitative data available"
  echo "The review can still proceed with qualitative observations only."
  exit 0
fi

days="${1:-30}"

echo ""
echo "=== SESSION METRICS (last ${days} days) ==="
sqlite3 -separator '|' "$METRICS_DB" "
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
done

echo ""
echo "=== HOOK OUTCOMES (last ${days} days) ==="
sqlite3 -separator '|' "$METRICS_DB" "
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
done

echo ""
echo "=== TOP FAILING TOOLS (last ${days} days) ==="
sqlite3 -separator '|' "$METRICS_DB" "
  SELECT tool_name,
         SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failures,
         COUNT(*) as total,
         ROUND(SUM(CASE WHEN success = 0 THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) as fail_pct
  FROM tool_outcomes
  WHERE timestamp > datetime('now', '-${days} days')
  GROUP BY tool_name
  HAVING failures > 0
  ORDER BY failures DESC
  LIMIT 10;
" 2>/dev/null | while IFS='|' read -r tool failures total pct; do
  echo "  $tool: $failures failures / $total total ($pct%)"
done

echo ""
echo "=== THRESHOLD STATUS ==="
sqlite3 -separator '|' "$METRICS_DB" "
  SELECT metric_name, default_value, current_value,
         CASE WHEN current_value != default_value THEN 'modified' ELSE 'default' END as status
  FROM threshold_overrides
  ORDER BY metric_name;
" 2>/dev/null | while IFS='|' read -r metric default current status; do
  echo "  $metric: $current (default: $default) [$status]"
done

# ── Recent error events from JSONL ───────────────────────────────────
if [ -f "$EVENTS_FILE" ]; then
  echo ""
  echo "=== RECENT ERRORS (from events.jsonl) ==="
  grep '"tool_failure"' "$EVENTS_FILE" 2>/dev/null | tail -20 | while read -r line; do
    tool=$(echo "$line" | grep -o '"tool":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    error_class=$(echo "$line" | grep -o '"error_class":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    [ -n "$tool" ] && echo "  $tool: $error_class"
  done
fi

echo ""
echo "=== DATA COLLECTION COMPLETE ==="
