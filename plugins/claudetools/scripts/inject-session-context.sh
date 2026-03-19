#!/usr/bin/env bash
# inject-session-context.sh — SessionStart hook: inject learned patterns from recent sessions
# Output goes to stdout and becomes Claude's context. Always exits 0.

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"
source "$(dirname "$0")/lib/telemetry.sh" 2>/dev/null || true

# Read session_id and create timestamp marker for task counting
INPUT=$(cat 2>/dev/null || true)
MODEL_FAMILY=$(detect_model_family)
_session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
if [ -n "$_session_id" ]; then
  touch "/tmp/.claude-session-start-${_session_id}"
fi

# Emit session start telemetry (environment snapshot) — main session only, not subagents
_agent_type=$(echo "$INPUT" | jq -r '.agent_type // "main"' 2>/dev/null || echo "main")
if [ "$_agent_type" = "main" ]; then
  emit_session_start 2>/dev/null || true
fi

# --- Dependency health check: warn if critical tools are missing ---
MISSING_DEPS=""
command -v sqlite3 &>/dev/null || MISSING_DEPS="${MISSING_DEPS}sqlite3 (metrics, self-learning, memory FTS), "
command -v jq &>/dev/null || MISSING_DEPS="${MISSING_DEPS}jq (hook input parsing), "
if [ -n "$MISSING_DEPS" ]; then
  MISSING_DEPS=${MISSING_DEPS%, }
  echo "[claudetools] Missing dependencies: ${MISSING_DEPS}. Some guardrails will silently bypass. Install with: apt install ${MISSING_DEPS%%(*}" >&2
fi

# sqlite3 required for remaining setup
if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

# Ensure DB exists
ensure_metrics_db || exit 0

# --- Bulk reindex memory files into DB (ensures FTS is populated) ---
MEMORY_DIR="$HOME/.claude/projects/$(pwd | sed 's|^/|-|' | tr '/' '-')/memory"
if [ -d "$MEMORY_DIR" ]; then
  INDEXED=0
  for memfile in "$MEMORY_DIR"/*.md; do
    [ -f "$memfile" ] || continue
    BASENAME=$(basename "$memfile")
    [ "$BASENAME" = "MEMORY.md" ] && continue

    MEM_ID=$(printf '%s' "$memfile" | sha256sum 2>/dev/null | head -c 16 || printf '%s' "$memfile" | shasum -a 256 2>/dev/null | head -c 16)
    EXISTS=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM memories WHERE id='$MEM_ID';" 2>/dev/null || echo "0")
    [ "$EXISTS" -gt 0 ] && continue

    # Parse frontmatter
    IN_FM=0; PAST_FM=0; M_NAME=""; M_DESC=""; M_TYPE=""; M_BODY=""
    while IFS= read -r line; do
      if [ "$IN_FM" -eq 0 ] && [ "$PAST_FM" -eq 0 ] && [ "$line" = "---" ]; then IN_FM=1; continue; fi
      if [ "$IN_FM" -eq 1 ] && [ "$line" = "---" ]; then IN_FM=0; PAST_FM=1; continue; fi
      if [ "$IN_FM" -eq 1 ]; then
        case "$line" in
          name:*)        M_NAME=$(echo "$line" | sed 's/^name:[[:space:]]*//' | sed "s/^[\"']//" | sed "s/[\"']$//") ;;
          description:*) M_DESC=$(echo "$line" | sed 's/^description:[[:space:]]*//' | sed "s/^[\"']//" | sed "s/[\"']$//") ;;
          type:*)        M_TYPE=$(echo "$line" | sed 's/^type:[[:space:]]*//' | sed "s/^[\"']//" | sed "s/[\"']$//") ;;
        esac; continue
      fi
      [ "$PAST_FM" -eq 1 ] && M_BODY="${M_BODY:+${M_BODY}
}${line}"
    done < "$memfile"
    [ -z "$M_NAME" ] && M_NAME="${BASENAME%.md}"
    [ -z "$M_TYPE" ] && M_TYPE="unknown"
    [ -z "$M_BODY" ] && M_BODY=$(cat "$memfile")

    # Auto-generated files get lower confidence and 'auto' source
    M_SOURCE="human"; M_CONF="1.0"
    case "$BASENAME" in
      auto_*|auto-*) M_SOURCE="auto"; M_CONF="0.6" ;;
    esac

    E_NAME=$(echo "$M_NAME" | sed "s/'/''/g")
    E_DESC=$(echo "$M_DESC" | sed "s/'/''/g")
    E_TYPE=$(echo "$M_TYPE" | sed "s/'/''/g")
    E_BODY=$(echo "$M_BODY" | sed "s/'/''/g")
    E_PATH=$(echo "$memfile" | sed "s/'/''/g")

    sqlite3 "$METRICS_DB" "INSERT INTO memories (id, content, type, name, description, source, file_path, confidence, created_at)
      VALUES ('$MEM_ID', '$E_BODY', '$E_TYPE', '$E_NAME', '$E_DESC', '$M_SOURCE', '$E_PATH', $M_CONF, datetime('now'))
      ON CONFLICT(id) DO UPDATE SET content=excluded.content, type=excluded.type, name=excluded.name, description=excluded.description, file_path=excluded.file_path, source=excluded.source, confidence=excluded.confidence;" 2>/dev/null && INDEXED=$((INDEXED + 1))
  done
  # Rebuild FTS index after bulk insert
  if [ "$INDEXED" -gt 0 ]; then
    sqlite3 "$METRICS_DB" "INSERT INTO memories_fts(memories_fts) VALUES('rebuild');" 2>/dev/null || true
    hook_log "session-start: indexed $INDEXED memory files into FTS"
  fi
fi

# Check if we have any session data
session_count=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(*) FROM session_metrics;" 2>/dev/null) || session_count=0

# --- Session history (only if we have prior sessions) ---
if [ "$session_count" -gt 0 ] 2>/dev/null; then

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

# --- Inject high-confidence memories (from active memories table) ---
if [ -f "$METRICS_DB" ]; then
  MEM_CONFIDENCE=$(get_threshold "memory_confidence_inject" "$MODEL_FAMILY")
  # Query the active memories table (FTS5-backed) for high-confidence entries
  MEMORIES=$(sqlite3 "$METRICS_DB" \
    "SELECT type, description FROM memories
     WHERE confidence >= ${MEM_CONFIDENCE}
     ORDER BY confidence DESC, COALESCE(last_accessed, created_at) DESC
     LIMIT 5;" \
    2>/dev/null || true)

  if [ -n "$MEMORIES" ]; then
    echo "$MEMORIES" | while IFS='|' read -r mtype mdesc; do
      [ -z "$mdesc" ] && continue
      echo "[memory:${mtype}] ${mdesc}"
    done
  fi

  # Also check legacy project_memories if table exists
  HAS_LEGACY=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='project_memories';" 2>/dev/null || echo "0")
  if [ "$HAS_LEGACY" -gt 0 ] 2>/dev/null; then
    LEGACY_MEMS=$(sqlite3 "$METRICS_DB" \
      "SELECT content FROM project_memories
       WHERE confidence > ${MEM_CONFIDENCE}
       AND content NOT IN (SELECT description FROM memories WHERE description IS NOT NULL)
       ORDER BY confidence DESC, last_seen DESC
       LIMIT 3;" \
      2>/dev/null || true)
    if [ -n "$LEGACY_MEMS" ]; then
      echo "$LEGACY_MEMS" | while IFS= read -r line; do
        echo "[memory:project] ${line}"
      done
    fi
  fi

  # Decay old memories (active table)
  MEM_DECAY_RATE=$(get_threshold "memory_decay_rate" "$MODEL_FAMILY")
  MEM_DECAY_DAYS=$(get_threshold "memory_decay_window_days" "$MODEL_FAMILY")
  MEM_DECAY_DAYS=${MEM_DECAY_DAYS%.*}
  MEM_PRUNE=$(get_threshold "memory_prune_threshold" "$MODEL_FAMILY")
  sqlite3 "$METRICS_DB" \
    "UPDATE memories SET confidence = confidence * ${MEM_DECAY_RATE}
     WHERE COALESCE(last_accessed, created_at) < datetime('now', '-${MEM_DECAY_DAYS} days')
     AND confidence > ${MEM_PRUNE};" 2>/dev/null || true

  # Prune low-confidence auto-extracted memories
  sqlite3 "$METRICS_DB" \
    "DELETE FROM memories
     WHERE confidence < ${MEM_PRUNE} AND access_count < 2 AND source != 'human';" 2>/dev/null || true

  # Legacy table decay/prune (if exists)
  if [ "$HAS_LEGACY" -gt 0 ] 2>/dev/null; then
    sqlite3 "$METRICS_DB" \
      "UPDATE project_memories SET confidence = confidence * ${MEM_DECAY_RATE}
       WHERE last_seen < datetime('now', '-${MEM_DECAY_DAYS} days')
       AND confidence > ${MEM_PRUNE};" 2>/dev/null || true
    sqlite3 "$METRICS_DB" \
      "DELETE FROM project_memories
       WHERE confidence < ${MEM_PRUNE} AND times_reinforced < 2;" 2>/dev/null || true
  fi
fi

fi  # end session_count > 0

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
