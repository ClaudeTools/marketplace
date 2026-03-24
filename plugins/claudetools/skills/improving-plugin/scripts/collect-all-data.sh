#!/usr/bin/env bash
# collect-all-data.sh — Gather all local and remote data for the self-improvement loop
# Queries metrics.db, events.jsonl, remote telemetry, memory files, changelog, and prior improvements.
# Output: structured text sections the agent can analyze during the improvement loop.

set -euo pipefail

# Guard: pipefail + while-read pipes = crash on EOF. Wrap piped reads in subshells.
# Every `| while read` block must end with `|| true` to survive pipefail.

_versioned_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)}"
_plugin_root="$_versioned_root"

# Versioned install path — use parent directory for stable data/logs dirs
# Keep versioned path for plugin.json, hooks.json, CHANGELOG (they live inside the version)
if [[ "$_plugin_root" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  _plugin_root="$(dirname "$_plugin_root")"
fi

METRICS_DB="${_plugin_root}/data/metrics.db"
EVENTS_FILE="${_plugin_root}/logs/events.jsonl"
HOOKS_JSON="${_versioned_root}/hooks/hooks.json"
PLUGIN_JSON="${_versioned_root}/.claude-plugin/plugin.json"
IMPROVEMENTS_LOG="${_plugin_root}/logs/loop-improvements.log"
CHANGELOG="${_versioned_root}/CHANGELOG.md"

TELEMETRY_BASE="https://claudetools-telemetry.motionmavericks.workers.dev"

days="${1:-7}"

# ── Plugin metadata ──────────────────────────────────────────────────
echo "=== PLUGIN INFO ==="
if [ -f "$PLUGIN_JSON" ]; then
  version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"' || echo "unknown")
  echo "version: $version"
else
  echo "version: unknown (plugin.json not found)"
fi

echo "os: $(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)"
_model="${CLAUDE_MODEL:-unknown}"
case "$_model" in
  *opus*)   _model_family="opus" ;;
  *sonnet*) _model_family="sonnet" ;;
  *haiku*)  _model_family="haiku" ;;
  *)        _model_family="$_model" ;;
esac
echo "model_family: $_model_family"

# Install ID
id_file="${_plugin_root}/data/.install-id"
if [ -f "$id_file" ]; then
  echo "install_id: $(cat "$id_file" 2>/dev/null || echo unknown)"
else
  echo "install_id: unknown"
fi

# ── Hook inventory ───────────────────────────────────────────────────
echo ""
echo "=== HOOK INVENTORY ==="
if [ -f "$HOOKS_JSON" ]; then
  total_hooks=$(grep -c '"command"' "$HOOKS_JSON" 2>/dev/null || echo "0")
  echo "total_configured_hooks: $total_hooks"
  grep -o '"event"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOOKS_JSON" 2>/dev/null \
    | grep -o '"[^"]*"$' | tr -d '"' | sort | uniq -c | sort -rn \
    | while read -r count event; do echo "  $event: $count hooks"; done || true
else
  echo "hooks.json not found"
fi

# ── Validator inventory ──────────────────────────────────────────────
echo ""
echo "=== VALIDATORS ==="
if [ -d "${_versioned_root}/scripts/validators" ]; then
  ls -1 "${_versioned_root}/scripts/validators/"*.sh 2>/dev/null | while read -r f; do
    echo "  $(basename "$f" .sh)"
  done || true
else
  echo "no validators directory"
fi

# ── Skill inventory ─────────────────────────────────────────────────
echo ""
echo "=== SKILLS ==="
if [ -d "${_versioned_root}/skills" ]; then
  ls -1d "${_versioned_root}/skills/"*/ 2>/dev/null | while read -r d; do
    echo "  $(basename "$d")"
  done || true
else
  echo "no skills directory"
fi

# ── Metrics DB queries ───────────────────────────────────────────────
if ! command -v sqlite3 &>/dev/null; then
  echo ""
  echo "=== METRICS ==="
  echo "sqlite3 not available — skipping quantitative metrics"
else
  if [ ! -f "$METRICS_DB" ]; then
    echo ""
    echo "=== METRICS ==="
    echo "metrics.db not found — no quantitative data available"
  else
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
    done || true

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
    done || true

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
    done || true

    echo ""
    echo "=== THRESHOLD STATUS ==="
    sqlite3 -separator '|' "$METRICS_DB" "
      SELECT metric_name, default_value, current_value,
             CASE WHEN current_value != default_value THEN 'modified' ELSE 'default' END as status
      FROM threshold_overrides
      ORDER BY metric_name;
    " 2>/dev/null | while IFS='|' read -r metric default current status; do
      echo "  $metric: $current (default: $default) [$status]"
    done || true
  fi
fi

# ── Recent events from JSONL ─────────────────────────────────────────
if [ -f "$EVENTS_FILE" ]; then
  echo ""
  echo "=== RECENT ERRORS (from events.jsonl, last 20) ==="
  grep '"tool_failure"' "$EVENTS_FILE" 2>/dev/null | tail -20 | while read -r line; do
    tool=$(echo "$line" | grep -o '"tool":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    error_class=$(echo "$line" | grep -o '"error_class":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    [ -n "$tool" ] && echo "  $tool: $error_class"
  done || true

  echo ""
  echo "=== RECENT NON-ALLOW EVENTS (from events.jsonl, last 50) ==="
  grep -v '"decision":"allow"' "$EVENTS_FILE" 2>/dev/null \
    | grep -v '"decision":""' 2>/dev/null \
    | grep '"decision"' 2>/dev/null \
    | tail -50 | while read -r line; do
    component=$(echo "$line" | grep -o '"component":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    decision=$(echo "$line" | grep -o '"decision":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    reason=$(echo "$line" | grep -o '"reason":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    echo "  [$ts] $component: $decision ${reason:+(reason: $reason)}"
  done || true
else
  echo ""
  echo "=== EVENTS ==="
  echo "events.jsonl not found"
fi

# ── Remote telemetry ─────────────────────────────────────────────────
echo ""
echo "=== REMOTE TELEMETRY: STATS ==="
if command -v curl &>/dev/null; then
  set +e
  stats_response=$(curl -s --max-time 10 --fail-with-body "${TELEMETRY_BASE}/v1/stats" 2>&1)
  stats_exit=$?
  set -e
  if [ $stats_exit -eq 0 ]; then
    echo "$stats_response"
  else
    echo "Failed to fetch /v1/stats (exit=$stats_exit): $stats_response"
  fi
else
  echo "curl not available — skipping remote telemetry"
fi

echo ""
echo "=== REMOTE TELEMETRY: HOOKS ==="
if command -v curl &>/dev/null; then
  set +e
  hooks_response=$(curl -s --max-time 10 --fail-with-body "${TELEMETRY_BASE}/v1/hooks?days=${days}&detail=true" 2>&1)
  hooks_exit=$?
  set -e
  if [ $hooks_exit -eq 0 ]; then
    echo "$hooks_response"
  else
    echo "Failed to fetch /v1/hooks (exit=$hooks_exit): $hooks_response"
  fi
fi

echo ""
echo "=== REMOTE TELEMETRY: FEEDBACK ==="
if command -v curl &>/dev/null; then
  set +e
  feedback_response=$(curl -s --max-time 10 --fail-with-body "${TELEMETRY_BASE}/v1/feedback" 2>&1)
  feedback_exit=$?
  set -e
  if [ $feedback_exit -eq 0 ]; then
    echo "$feedback_response"
  else
    echo "Failed to fetch /v1/feedback (exit=$feedback_exit): $feedback_response"
  fi
fi

# ── Memory files ─────────────────────────────────────────────────────
echo ""
echo "=== MEMORY FILES ==="
found_memories=0
for mem_dir in "$HOME"/.claude/projects/*/memory/; do
  [ -d "$mem_dir" ] || continue
  project=$(basename "$(dirname "$mem_dir")")
  for f in "$mem_dir"*.md; do
    [ -f "$f" ] || continue
    found_memories=1
    fname=$(basename "$f")
    first_line=$(head -1 "$f" 2>/dev/null || echo "(empty)")
    echo "  [$project] $fname: $first_line"
  done
done
if [ $found_memories -eq 0 ]; then
  echo "  No memory files found"
fi

# ── Changelog ────────────────────────────────────────────────────────
echo ""
echo "=== CHANGELOG (recent) ==="
if [ -f "$CHANGELOG" ]; then
  head -100 "$CHANGELOG" 2>/dev/null
else
  echo "CHANGELOG.md not found"
fi

# ── Prior improvements ───────────────────────────────────────────────
echo ""
echo "=== PRIOR IMPROVEMENTS (last 10) ==="
if [ -f "$IMPROVEMENTS_LOG" ]; then
  tail -10 "$IMPROVEMENTS_LOG" 2>/dev/null
else
  echo "loop-improvements.log not found"
fi

# ── Consumed findings registry (for dedup + verification) ────────────
CONSUMED_FILE="${_plugin_root}/logs/consumed-findings.jsonl"
echo ""
echo "=== CONSUMED FINDINGS REGISTRY ==="
if [ -f "$CONSUMED_FILE" ]; then
  echo "Total consumed: $(wc -l < "$CONSUMED_FILE" | tr -d ' ')"
  echo ""
  echo "Pending validation (need before/after check):"
  grep '"status":"pending_validation"' "$CONSUMED_FILE" 2>/dev/null | tail -20 || echo "  (none)"
  echo ""
  echo "Recently consumed (last 20):"
  tail -20 "$CONSUMED_FILE" 2>/dev/null
else
  echo "No consumed-findings.jsonl — this is the first iteration with tracking"
fi

echo ""
echo "=== DATA COLLECTION COMPLETE ==="
