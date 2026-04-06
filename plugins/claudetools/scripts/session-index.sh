#!/usr/bin/env bash
# SubagentStart / ConfigChange / WorktreeCreate hook: index the project and output a project map
# Also called indirectly on SessionStart via session-start-dispatcher.sh.
# This script runs when a session or subagent starts, building/updating the
# codebase index and injecting a compact project map into the agent's context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read stdin unconditionally (before LOG_SCRIPT check — stdin must be consumed first)
INPUT=$(cat 2>/dev/null || true)

# Source shared logging and telemetry
PLUGIN_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_SCRIPT="$PLUGIN_ROOT/scripts/hook-log.sh"
if [[ -f "$LOG_SCRIPT" ]]; then
  source "$LOG_SCRIPT"
fi
TELEM_SCRIPT="$PLUGIN_ROOT/scripts/lib/telemetry.sh"
if [[ -f "$TELEM_SCRIPT" ]]; then
  source "$TELEM_SCRIPT" 2>/dev/null || true
fi

# Determine project root from CWD (Claude Code sets this to the project)
PROJECT_ROOT="${SRCPILOT_PROJECT_ROOT:-$(pwd)}"

# ── Session registration (always — independent of srcpilot availability) ──────
# guard-context-reread, track-file-reads, and blind-edit all depend on
# .srcpilot/session-ids and /tmp/srcpilot-reads-{id}.jsonl existing.
# Register unconditionally before any early-exit so these hooks work in
# every project regardless of whether srcpilot is installed or indexed.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$$"
fi
INDEX_DIR="$PROJECT_ROOT/.srcpilot"
mkdir -p "$INDEX_DIR" 2>/dev/null || true
# Determine hook event type
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)

# On SessionStart: prune stale sessions and append ours atomically
# On SubagentStart: append to existing file
if [ "$HOOK_EVENT" = "SessionStart" ] || [ "$HOOK_EVENT" = "WorktreeCreate" ]; then
  (
    flock -w 2 200 || true
    # Keep existing valid session IDs, add ours
    tmp_ids=$(mktemp)
    if [ -f "$INDEX_DIR/session-ids" ]; then
      # Keep lines that aren't our session ID
      grep -vxF "$SESSION_ID" "$INDEX_DIR/session-ids" > "$tmp_ids" 2>/dev/null || true
    fi
    echo "$SESSION_ID" >> "$tmp_ids"
    mv "$tmp_ids" "$INDEX_DIR/session-ids"
  ) 200>"$INDEX_DIR/session-ids.lock"
  : > "/tmp/srcpilot-reads-${SESSION_ID}.jsonl" 2>/dev/null || true
else
  if ! grep -qxF "$SESSION_ID" "$INDEX_DIR/session-ids" 2>/dev/null; then
    (
      flock -w 2 200 || true
      if ! grep -qxF "$SESSION_ID" "$INDEX_DIR/session-ids" 2>/dev/null; then
        echo "$SESSION_ID" >> "$INDEX_DIR/session-ids"
      fi
    ) 200>"$INDEX_DIR/session-ids.lock"
  fi
fi

# ── srcpilot: required for indexing + map output (not for session tracking) ───
if ! command -v srcpilot &>/dev/null && [[ ! -f "${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/srcpilot" ]]; then
  hook_log "srcpilot: not found — install with: npm install -g srcpilot" 2>/dev/null || true
  emit_event "srcpilot" "not_installed" "warn" 2>/dev/null || true
  echo "[srcpilot] not installed — run: npm install -g srcpilot"
  exit 0
fi
# shellcheck source=lib/resolve-srcpilot.sh
source "${BASH_SOURCE[0]%/*}/lib/resolve-srcpilot.sh"

# Skip indexing if no source files exist or project is too large
MAX_FILES=10000
SOURCE_COUNT=$(find "$PROJECT_ROOT" -maxdepth 5 \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/__pycache__/*" -not -path "*/.venv/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.next/*" 2>/dev/null | head -$((MAX_FILES + 1)) | wc -l)
if [[ "$SOURCE_COUNT" -eq 0 ]]; then
  hook_log "srcpilot: no source files in $PROJECT_ROOT, skipping" 2>/dev/null || true
  emit_event "srcpilot" "no_source_files" "allow" 2>/dev/null || true
  exit 0
fi
if [[ "$SOURCE_COUNT" -gt "$MAX_FILES" ]]; then
  hook_log "srcpilot: project too large (>${MAX_FILES} source files), skipping" 2>/dev/null || true
  emit_event "srcpilot" "index_skipped_too_large" "warn" 2>/dev/null || true
  exit 0
fi

# Incremental indexing: skip full rebuild if index is recent (< 1 hour)
INDEX_DB="$PROJECT_ROOT/.srcpilot/db.sqlite"
SKIP_FULL_INDEX=0

if [ -f "$INDEX_DB" ]; then
  INDEX_AGE=$(( $(date +%s) - $(stat -c %Y "$INDEX_DB" 2>/dev/null || stat -f %m "$INDEX_DB" 2>/dev/null || echo 0) ))
  if [ "$INDEX_AGE" -lt 3600 ]; then
    CHANGED_SINCE=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~3 HEAD 2>/dev/null | head -50 || true)
    if [ -n "$CHANGED_SINCE" ]; then
      hook_log "srcpilot: incremental reindex (${INDEX_AGE}s old, $(echo "$CHANGED_SINCE" | wc -l) files changed)" 2>/dev/null || true
      echo "$CHANGED_SINCE" | while IFS= read -r f; do
        [ -f "$PROJECT_ROOT/$f" ] && "$SRCPILOT" index-file "$PROJECT_ROOT/$f" 2>/dev/null || true
      done
    else
      hook_log "srcpilot: index fresh and no changes — skipping" 2>/dev/null || true
    fi
    SKIP_FULL_INDEX=1
  fi
fi

# Run the indexer — capture stderr so we get the actual error in telemetry
_idx_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)} 2>/dev/null || true
_idx_ok=1
if [ "$SKIP_FULL_INDEX" -eq 0 ]; then
  IDX_OUTPUT=$("$SRCPILOT" index "$PROJECT_ROOT" 2>&1) || _idx_ok=0
  if [[ "$_idx_ok" -eq 0 ]]; then
    IDX_ERR_SHORT="${IDX_OUTPUT:0:200}"
    hook_log "srcpilot: indexing FAILED for $PROJECT_ROOT: $IDX_ERR_SHORT" 2>/dev/null || true
    emit_event "srcpilot" "index_failed" "error" 2>/dev/null || true
  else
    _idx_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)} 2>/dev/null || true
    _idx_ms=$(awk "BEGIN {printf \"%d\", ($_idx_end - $_idx_start) * 1000}" 2>/dev/null || echo 0)
    emit_event "srcpilot" "index_success" "allow" "$_idx_ms" 2>/dev/null || true
  fi
fi

# Determine injection flags before any output is produced.
# WorktreeCreate: no output (stdout corruption).
# SubagentStart: skip map and memories (parent already has them; saves ~1,500 tokens).
_inject_context=1
_inject_map=1
_inject_memories=1
if [[ "$HOOK_EVENT" == "WorktreeCreate" ]] || [[ "$HOOK_EVENT" == "ConfigChange" ]]; then
  _inject_context=0
  _inject_map=0
  _inject_memories=0
elif [[ "$HOOK_EVENT" == "SubagentStart" ]]; then
  _inject_map=0       # subagent has its task — full map is noise
  _inject_memories=0  # parent session already has memories
fi

# Output the project map to stdout (injected as context for the agent)
# Only attempt map if indexing succeeded
MAP_OUTPUT=""
if [[ "$_idx_ok" -eq 1 ]] && [[ "$_inject_map" -eq 1 ]]; then
  MAP_ERR=""
  MAP_OUTPUT=$("$SRCPILOT" map "$PROJECT_ROOT" 2>/tmp/srcpilot-map-err-$$.txt) || true
  MAP_ERR=$(head -c 200 /tmp/srcpilot-map-err-$$.txt 2>/dev/null || true)
  rm -f /tmp/srcpilot-map-err-$$.txt 2>/dev/null || true
  if [[ -z "$MAP_OUTPUT" ]]; then
    hook_log "srcpilot: map generation returned empty for $PROJECT_ROOT${MAP_ERR:+: $MAP_ERR}" 2>/dev/null || true
    emit_event "srcpilot" "map_empty" "warn" 2>/dev/null || true
  fi
fi

# Byte budget: cap map output to prevent context bloat on large projects
MAX_MAP_BYTES=2048
if [[ "$HOOK_EVENT" == "SubagentStart" ]]; then
  MAX_MAP_BYTES=1024
fi
if [[ ${#MAP_OUTPUT} -gt $MAX_MAP_BYTES ]]; then
  MAP_OUTPUT="${MAP_OUTPUT:0:$MAX_MAP_BYTES}
... (truncated — use srcpilot map for full output)"
fi

if [[ "$_inject_context" -eq 1 ]] && [[ "$_inject_map" -eq 1 ]] && [[ -n "$MAP_OUTPUT" ]]; then
  echo "--- Codebase Index (auto-generated) ---"
  echo "$MAP_OUTPUT"
  echo "--- End Codebase Index ---"
fi

# --- Task-aware context injection (skip on WorktreeCreate) ---
# On SubagentStart, extract key terms from the agent's task/prompt and inject
# relevant symbols + file locations so the agent doesn't waste inference searching.
if [[ "$_inject_context" -eq 0 ]]; then
  exit 0
fi

DB_PATH=""
for d in "$PROJECT_ROOT" "$PROJECT_ROOT/.srcpilot"; do
  [[ -f "$d/db.sqlite" ]] && DB_PATH="$d/db.sqlite" && break
done

if [[ -n "$DB_PATH" ]] && command -v sqlite3 &>/dev/null; then
  # Extract the agent's prompt/task description from hook input
  TASK_TEXT=$(echo "$INPUT" | jq -r '(.tool_input.prompt // .tool_input.description // .prompt // "") | .[0:2000]' 2>/dev/null || true)

  if [[ -n "$TASK_TEXT" && ${#TASK_TEXT} -gt 10 ]]; then
    # Extract potential identifiers: PascalCase, camelCase, snake_case words (3+ chars)
    TERMS=$(echo "$TASK_TEXT" | grep -oE '\b[A-Z][a-zA-Z0-9]{2,}\b|\b[a-z][a-zA-Z0-9]{2,}[A-Z][a-zA-Z0-9]*\b|\b[a-z_]{3,}\b' | sort -u | head -15)

    if [[ -n "$TERMS" ]]; then
      CONTEXT_HITS=""
      while IFS= read -r term; do
        [[ -z "$term" ]] && continue
        # Query index for this term — use parameterized query to prevent SQL injection
        HITS=$(sqlite3 "$DB_PATH" -cmd ".parameter set :term $term" \
          "SELECT s.kind, s.name, f.path, s.line FROM symbols s JOIN files f ON s.file_id = f.id WHERE s.name = :term LIMIT 5;" 2>/dev/null || true)
        if [[ -n "$HITS" ]]; then
          while IFS='|' read -r kind name path line; do
            CONTEXT_HITS="${CONTEXT_HITS}  ${kind} ${name} → ${path}:${line}\n"
          done <<< "$HITS"
        fi
      done <<< "$TERMS"

      if [[ -n "$CONTEXT_HITS" ]]; then
        echo ""
        echo "--- Task-Relevant Symbols (auto-resolved) ---"
        printf '%b' "$CONTEXT_HITS"

        # Also find files importing these symbols
        IMPORT_HITS=""
        while IFS= read -r term; do
          [[ -z "$term" ]] && continue
          # Use parameterized query with LIKE — build the pattern safely
          like_pattern="%${term}%"
          IMPORTS=$(sqlite3 "$DB_PATH" -cmd ".parameter set :pattern $like_pattern" \
            "SELECT f.path FROM imports i JOIN files f ON i.file_id = f.id WHERE i.symbols LIKE :pattern LIMIT 5;" 2>/dev/null || true)
          if [[ -n "$IMPORTS" ]]; then
            while IFS= read -r ipath; do
              IMPORT_HITS="${IMPORT_HITS}  ${ipath} imports ${term}\n"
            done <<< "$IMPORTS"
          fi
        done <<< "$TERMS"

        if [[ -n "$IMPORT_HITS" ]]; then
          echo ""
          echo "Related files (via imports):"
          printf '%b' "$IMPORT_HITS" | sort -u | head -15
        fi

        echo "--- End Task Context ---"
      fi
    fi
  fi
fi

# --- Subagent capabilities injection (SubagentStart only) ---
# On SessionStart, the main session already has CLAUDE.md with tool listings.
# Only inject subagent-context.md for subagents where it's the primary reference.
# Memory injection is owned by inject-session-context.sh — not duplicated here.
if [[ "$HOOK_EVENT" == "SubagentStart" ]]; then
  SUBAGENT_CONTEXT="$PLUGIN_ROOT/assets/subagent-context.md"
  if [[ -f "$SUBAGENT_CONTEXT" ]]; then
    echo ""
    echo "--- Plugin Context (auto-injected) ---"
    cat "$SUBAGENT_CONTEXT"
    echo "--- End Plugin Context ---"
  fi
fi

exit 0
