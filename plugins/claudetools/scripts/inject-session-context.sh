#!/usr/bin/env bash
# inject-session-context.sh — SessionStart hook: inject learned patterns from recent sessions
# Output goes to stdout and becomes Claude's context. Always exits 0.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"

# Read session_id and create timestamp marker for task counting
INPUT=$(cat 2>/dev/null || true)
MODEL_FAMILY=$(detect_model_family)
_session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
if [ -n "$_session_id" ]; then
  touch "/tmp/.claude-session-start-${_session_id}"
fi

# sqlite3 required
if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

# Ensure DB exists
ensure_metrics_db || exit 0

# Check if we have any session data
session_count=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(*) FROM session_metrics;" 2>/dev/null) || session_count=0

if [ "$session_count" -eq 0 ] 2>/dev/null; then
  # Silent first run — no data yet
  exit 0
fi

# Query last 5 sessions
avg_churn=$(sqlite3 "$METRICS_DB" \
  "SELECT ROUND(AVG(edit_churn_rate), 2) FROM (SELECT edit_churn_rate FROM session_metrics ORDER BY timestamp DESC LIMIT 5);" \
  2>/dev/null) || avg_churn="0"

total_failures=$(sqlite3 "$METRICS_DB" \
  "SELECT COALESCE(SUM(total_failures), 0) FROM (SELECT total_failures FROM session_metrics ORDER BY timestamp DESC LIMIT 5);" \
  2>/dev/null) || total_failures="0"

# Only output if there's something meaningful to say
if [ -n "$avg_churn" ] && [ "$avg_churn" != "0" ] && [ "$avg_churn" != "0.0" ] && [ "$avg_churn" != "0.00" ]; then
  echo "[Session History] Avg edit churn: ${avg_churn} | Recent failures: ${total_failures}"

  # High churn warning
  CHURN_WARN=$(get_threshold "churn_warning" "$MODEL_FAMILY")
  if awk "BEGIN {exit !(${avg_churn} > ${CHURN_WARN})}" 2>/dev/null; then
    echo "Note: recent sessions show high edit churn. Focus on diagnostics before editing."
  fi
fi

# High failure warning
FAILURE_WARN=$(get_threshold "failure_warning" "$MODEL_FAMILY")
FAILURE_WARN=${FAILURE_WARN%.*}
if [ "${total_failures:-0}" -gt "$FAILURE_WARN" ] 2>/dev/null; then
  echo "Note: elevated failure rate. Research before implementing."
fi

# --- Inject high-confidence project memories ---
if [ -f "$METRICS_DB" ]; then
  MEM_CONFIDENCE=$(get_threshold "memory_confidence_inject" "$MODEL_FAMILY")
  MEMORIES=$(sqlite3 "$METRICS_DB" \
    "SELECT content FROM project_memories
     WHERE confidence > ${MEM_CONFIDENCE}
     ORDER BY confidence DESC, last_seen DESC
     LIMIT 5;" \
    2>/dev/null || true)

  if [ -n "$MEMORIES" ]; then
    echo "[Project Memory]"
    echo "$MEMORIES" | while IFS= read -r line; do
      echo "  - $line"
    done
  fi

  # Decay old memories
  MEM_DECAY_RATE=$(get_threshold "memory_decay_rate" "$MODEL_FAMILY")
  MEM_DECAY_DAYS=$(get_threshold "memory_decay_window_days" "$MODEL_FAMILY")
  MEM_DECAY_DAYS=${MEM_DECAY_DAYS%.*}
  MEM_PRUNE=$(get_threshold "memory_prune_threshold" "$MODEL_FAMILY")
  sqlite3 "$METRICS_DB" \
    "UPDATE project_memories SET confidence = confidence * ${MEM_DECAY_RATE}
     WHERE last_seen < datetime('now', '-${MEM_DECAY_DAYS} days')
     AND confidence > ${MEM_PRUNE};" 2>/dev/null || true

  # Prune very low confidence, unreinforced memories
  sqlite3 "$METRICS_DB" \
    "DELETE FROM project_memories
     WHERE confidence < ${MEM_PRUNE} AND times_reinforced < 2;" 2>/dev/null || true
fi

# --- Surface memory candidates from previous sessions ---
PLUGIN_DATA="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/data"
CANDIDATES_FILE="$PLUGIN_DATA/memory-candidates.jsonl"
if [ -f "$CANDIDATES_FILE" ] && [ -s "$CANDIDATES_FILE" ]; then
  CAND_COUNT=$(wc -l < "$CANDIDATES_FILE" 2>/dev/null | tr -d ' ')
  if [ "${CAND_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo "[Memory] ${CAND_COUNT} memory candidates from previous sessions. Review with: cat ${CANDIDATES_FILE}"
    echo "Consider saving valuable ones to memory/ and clearing the staging file."
  fi
fi

exit 0
