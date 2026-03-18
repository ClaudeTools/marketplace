#!/usr/bin/env bash
# memory-consolidate.sh — SessionEnd hook (async)
# Syncs memory/ files ↔ SQLite, decays old memories, prunes low-confidence,
# regenerates MEMORY.md as a hot cache of top-N memories.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"

INPUT=$(cat 2>/dev/null || true)
MODEL_FAMILY=$(detect_model_family)

# sqlite3 required
if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

ensure_metrics_db 2>/dev/null || exit 0

hook_log "memory-consolidate: starting"

# --- Locate memory directory ---
# Check common locations for the user's memory directory
MEMORY_DIR=""
CWD_SLUG=$(pwd | tr '/' '-')
for dir in \
  "$HOME/.claude/projects/${CWD_SLUG}/memory" \
  "$HOME/.claude/projects/-home-$(whoami)-projects-$(basename "$(pwd)")/memory" \
  "$HOME/.claude/memory"; do
  if [[ -d "$dir" ]]; then
    MEMORY_DIR="$dir"
    break
  fi
done

if [[ -z "$MEMORY_DIR" ]]; then
  hook_log "memory-consolidate: no memory directory found"
  exit 0
fi

MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"

# --- 1. Sync files → SQLite ---
# Index any memory files not yet in the database
for mdfile in "$MEMORY_DIR"/*.md; do
  [[ -f "$mdfile" ]] || continue
  [[ "$(basename "$mdfile")" == "MEMORY.md" ]] && continue

  # Check if already indexed by file_path
  EXISTING=$(sqlite3 "$METRICS_DB" "SELECT id FROM memories WHERE file_path='$(echo "$mdfile" | sed "s/'/''/g")' LIMIT 1;" 2>/dev/null || true)
  if [[ -n "$EXISTING" ]]; then
    continue
  fi

  # Parse frontmatter
  IN_FM=0; PAST_FM=0
  MEM_NAME=""; MEM_DESC=""; MEM_TYPE=""; BODY=""
  while IFS= read -r line; do
    if [[ "$IN_FM" -eq 0 && "$PAST_FM" -eq 0 && "$line" == "---" ]]; then IN_FM=1; continue; fi
    if [[ "$IN_FM" -eq 1 && "$line" == "---" ]]; then IN_FM=0; PAST_FM=1; continue; fi
    if [[ "$IN_FM" -eq 1 ]]; then
      case "$line" in
        name:*)        MEM_NAME=$(echo "$line" | sed 's/^name:[[:space:]]*//; s/^["'\'']\|["'\''"]$//g') ;;
        description:*) MEM_DESC=$(echo "$line" | sed 's/^description:[[:space:]]*//; s/^["'\'']\|["'\''"]$//g') ;;
        type:*)        MEM_TYPE=$(echo "$line" | sed 's/^type:[[:space:]]*//; s/^["'\'']\|["'\''"]$//g') ;;
      esac
      continue
    fi
    if [[ "$PAST_FM" -eq 1 ]]; then
      [[ -n "$BODY" ]] && BODY="${BODY}
${line}" || BODY="$line"
    fi
  done < "$mdfile"

  [[ -z "$MEM_NAME" ]] && MEM_NAME="$(basename "$mdfile" .md)"
  [[ -z "$MEM_TYPE" ]] && MEM_TYPE="unknown"
  [[ -z "$BODY" ]] && BODY=$(cat "$mdfile")

  MEM_ID=$(printf '%s' "$mdfile" | sha256sum 2>/dev/null | head -c 16 || printf '%s' "$mdfile" | shasum -a 256 2>/dev/null | head -c 16 || echo "$RANDOM")

  sql_e() { echo "$1" | sed "s/'/''/g"; }

  sqlite3 "$METRICS_DB" "INSERT OR IGNORE INTO memories (id, content, type, name, description, source, file_path, created_at)
    VALUES ('$MEM_ID', '$(sql_e "$BODY")', '$(sql_e "$MEM_TYPE")', '$(sql_e "$MEM_NAME")', '$(sql_e "$MEM_DESC")', 'human', '$(sql_e "$mdfile")', datetime('now'));" 2>/dev/null || true
done

# --- 2. Sync SQLite → files: remove orphaned DB entries ---
sqlite3 "$METRICS_DB" "SELECT id, file_path FROM memories WHERE file_path IS NOT NULL;" 2>/dev/null | while IFS='|' read -r mid mpath; do
  if [[ -n "$mpath" && ! -f "$mpath" ]]; then
    sqlite3 "$METRICS_DB" "DELETE FROM memories WHERE id='$mid';" 2>/dev/null || true
    hook_log "memory-consolidate: removed orphaned entry $mid ($mpath)"
  fi
done

# --- 3. Decay old memories ---
MEM_DECAY_RATE=$(get_threshold "memory_decay_rate" "$MODEL_FAMILY")
MEM_DECAY_DAYS=$(get_threshold "memory_decay_window_days" "$MODEL_FAMILY")
MEM_DECAY_DAYS=${MEM_DECAY_DAYS%.*}

sqlite3 "$METRICS_DB" \
  "UPDATE memories SET confidence = confidence * ${MEM_DECAY_RATE}
   WHERE last_accessed < datetime('now', '-${MEM_DECAY_DAYS} days')
   AND last_accessed IS NOT NULL
   AND confidence > 0.1;" 2>/dev/null || true

# --- 4. Prune very low confidence, rarely accessed memories ---
sqlite3 "$METRICS_DB" \
  "DELETE FROM memories WHERE confidence < 0.05 AND access_count < 2 AND source != 'human';" 2>/dev/null || true

# --- 5. Regenerate MEMORY.md ---
# Query top-N memories by composite score
TOP_MEMORIES=$(sqlite3 "$METRICS_DB" -separator '|' \
  "SELECT file_path, name, description, type,
          ROUND(confidence * 0.6 + MIN(CAST(access_count AS REAL)/10.0, 0.4), 3) as score
   FROM memories
   WHERE file_path IS NOT NULL AND confidence > 0.1
   ORDER BY score DESC, created_at DESC
   LIMIT 40;" 2>/dev/null || true)

if [[ -z "$TOP_MEMORIES" ]]; then
  hook_log "memory-consolidate: no memories to write to MEMORY.md"
  exit 0
fi

# Build new MEMORY.md content
{
  while IFS='|' read -r fpath fname fdesc ftype fscore; do
    [[ -z "$fpath" ]] && continue
    # Extract just the filename relative to memory/
    local_name=$(basename "$fpath")
    desc_part=""
    [[ -n "$fdesc" ]] && desc_part=" — $fdesc"
    echo "- [${local_name}](${local_name})${desc_part}"
  done <<< "$TOP_MEMORIES"
} > "${MEMORY_INDEX}.tmp" 2>/dev/null

# Only replace if we generated content and it's within the 180-line budget
LINE_COUNT=$(wc -l < "${MEMORY_INDEX}.tmp" 2>/dev/null || echo 0)
if [[ "$LINE_COUNT" -gt 0 && "$LINE_COUNT" -le 180 ]]; then
  mv "${MEMORY_INDEX}.tmp" "$MEMORY_INDEX"
  hook_log "memory-consolidate: regenerated MEMORY.md with $LINE_COUNT entries"
else
  rm -f "${MEMORY_INDEX}.tmp"
  hook_log "memory-consolidate: skipped MEMORY.md regen (lines=$LINE_COUNT)"
fi

hook_log "memory-consolidate: complete"
exit 0
