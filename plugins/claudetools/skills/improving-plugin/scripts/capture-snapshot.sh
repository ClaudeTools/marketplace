#!/usr/bin/env bash
# capture-snapshot.sh — Point-in-time measurement of system health metrics
# Outputs structured JSON to stdout for before/after comparison.
# Usage: bash capture-snapshot.sh [days] > snapshot.json

set -euo pipefail

_versioned_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)}"
_plugin_root="$_versioned_root"
if [[ "$_plugin_root" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  _plugin_root="$(dirname "$_plugin_root")"
fi

METRICS_DB="${_plugin_root}/data/metrics.db"
EVENTS_FILE="${_plugin_root}/logs/events.jsonl"
TELEMETRY_BASE="https://claudetools-telemetry.motionmavericks.workers.dev"
days="${1:-7}"
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Start JSON output
printf '{\n'
printf '  "ts": "%s",\n' "$ts"
printf '  "window_days": %s,\n' "$days"

# ── Local metrics ────────────────────────────────────────────────────
if command -v sqlite3 &>/dev/null && [ -f "$METRICS_DB" ]; then
  # System health: allow rate
  allow_rate=$(sqlite3 "$METRICS_DB" "
    SELECT ROUND(SUM(CASE WHEN decision='allow' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1)
    FROM hook_outcomes WHERE timestamp > datetime('now', '-${days} days');
  " 2>/dev/null || echo "null")
  [ -z "$allow_rate" ] && allow_rate="null"

  total_hook_events=$(sqlite3 "$METRICS_DB" "
    SELECT COUNT(*) FROM hook_outcomes WHERE timestamp > datetime('now', '-${days} days');
  " 2>/dev/null || echo "0")

  printf '  "local_allow_rate": %s,\n' "$allow_rate"
  printf '  "local_total_hook_events": %s,\n' "$total_hook_events"

  # Per-hook rates
  printf '  "hook_rates": {\n'
  first=true
  sqlite3 -separator '|' "$METRICS_DB" "
    SELECT hook_name,
           COUNT(*) as total,
           SUM(CASE WHEN decision='block' THEN 1 ELSE 0 END) as blocks,
           SUM(CASE WHEN decision='warn' THEN 1 ELSE 0 END) as warns,
           SUM(CASE WHEN decision='allow' THEN 1 ELSE 0 END) as allows,
           ROUND(SUM(CASE WHEN decision='block' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) as block_pct,
           ROUND(SUM(CASE WHEN decision='warn' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) as warn_pct
    FROM hook_outcomes
    WHERE timestamp > datetime('now', '-${days} days')
    GROUP BY hook_name
    ORDER BY total DESC;
  " 2>/dev/null | while IFS='|' read -r name total blocks warns allows block_pct warn_pct; do
    if [ "$first" = true ]; then first=false; else printf ',\n'; fi
    printf '    "%s": {"total": %s, "block": %s, "warn": %s, "allow": %s, "block_pct": %s, "warn_pct": %s}' \
      "$name" "$total" "$blocks" "$warns" "$allows" "$block_pct" "$warn_pct"
  done || true
  printf '\n  },\n'

  # Session averages
  sqlite3 -separator '|' "$METRICS_DB" "
    SELECT ROUND(AVG(total_failures), 1), ROUND(AVG(edit_churn_rate), 2), COUNT(*)
    FROM session_metrics WHERE timestamp > datetime('now', '-${days} days');
  " 2>/dev/null | IFS='|' read -r avg_fails avg_churn session_count || true
  printf '  "avg_failures": %s,\n' "${avg_fails:-null}"
  printf '  "avg_churn": %s,\n' "${avg_churn:-null}"
  printf '  "session_count": %s,\n' "${session_count:-0}"

  # Tool failure counts
  printf '  "tool_failures": {\n'
  first=true
  sqlite3 -separator '|' "$METRICS_DB" "
    SELECT tool_name, SUM(CASE WHEN success=0 THEN 1 ELSE 0 END) as failures
    FROM tool_outcomes WHERE timestamp > datetime('now', '-${days} days')
    GROUP BY tool_name HAVING failures > 0 ORDER BY failures DESC LIMIT 10;
  " 2>/dev/null | while IFS='|' read -r tool failures; do
    if [ "$first" = true ]; then first=false; else printf ',\n'; fi
    printf '    "%s": %s' "$tool" "$failures"
  done || true
  printf '\n  },\n'

else
  printf '  "local_allow_rate": null,\n'
  printf '  "local_total_hook_events": 0,\n'
  printf '  "hook_rates": {},\n'
  printf '  "avg_failures": null,\n'
  printf '  "avg_churn": null,\n'
  printf '  "session_count": 0,\n'
  printf '  "tool_failures": {},\n'
fi

# ── Event log counts ─────────────────────────────────────────────────
if [ -f "$EVENTS_FILE" ]; then
  non_allow=$(grep -c '"decision":"block"\|"decision":"warn"' "$EVENTS_FILE" 2>/dev/null || echo "0")
  total_events=$(wc -l < "$EVENTS_FILE" 2>/dev/null || echo "0")
  printf '  "events_total": %s,\n' "$total_events"
  printf '  "events_non_allow": %s,\n' "$non_allow"
else
  printf '  "events_total": 0,\n'
  printf '  "events_non_allow": 0,\n'
fi

# ── Remote telemetry ─────────────────────────────────────────────────
if command -v curl &>/dev/null; then
  remote_stats=$(curl -s --max-time 5 "${TELEMETRY_BASE}/v1/stats" 2>/dev/null || echo '{}')
  printf '  "remote_stats": %s\n' "$remote_stats"
else
  printf '  "remote_stats": {}\n'
fi

printf '}\n'
