#!/usr/bin/env bash
# SessionStart / SubagentStart hook: index the project and output a project map
# This script runs when a session or subagent starts, building/updating the
# codebase index and injecting a compact project map into the agent's context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PILOT_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PILOT_DIR/dist/cli.js"

# Read stdin unconditionally (before LOG_SCRIPT check — stdin must be consumed first)
INPUT=$(cat 2>/dev/null || true)

# Source shared logging and telemetry
PLUGIN_ROOT="$(dirname "$PILOT_DIR")"
LOG_SCRIPT="$PLUGIN_ROOT/scripts/hook-log.sh"
if [[ -f "$LOG_SCRIPT" ]]; then
  source "$LOG_SCRIPT"
fi
TELEM_SCRIPT="$PLUGIN_ROOT/scripts/lib/telemetry.sh"
if [[ -f "$TELEM_SCRIPT" ]]; then
  source "$TELEM_SCRIPT" 2>/dev/null || true
fi

# Determine project root from CWD (Claude Code sets this to the project)
PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"

# Auto-install dependencies if missing (one-time setup)
# Skip entirely if dist/cli.js exists — deps may already be bundled or pre-installed
if [[ ! -d "$PILOT_DIR/node_modules" ]]; then
  if [[ -f "$CLI" ]]; then
    # CLI is built; try running it to see if it works without node_modules
    if node "$CLI" --help &>/dev/null 2>&1 || node -e "require('$PILOT_DIR/dist/cli.js')" &>/dev/null 2>&1; then
      hook_log "codebase-pilot: node_modules missing but CLI works, skipping npm install" 2>/dev/null || true
    else
      # CLI exists but can't run — fall through to npm install
      :
    fi
  fi
  # Only attempt npm install if node_modules still doesn't exist (skip re-check allows the above block to be a no-op)
  if [[ ! -d "$PILOT_DIR/node_modules" ]]; then
    if command -v npm &>/dev/null; then
      hook_log "codebase-pilot: npm install (first run)" 2>/dev/null || true
      NPM_ERR=$(cd "$PILOT_DIR" && npm install --production --no-audit --no-fund --legacy-peer-deps 2>&1) || {
        hook_log "codebase-pilot: npm install FAILED: ${NPM_ERR:0:200}" 2>/dev/null || true
        emit_event "codebase-pilot" "npm_install_failed" "error" 2>/dev/null || true
      }
    else
      hook_log "codebase-pilot: npm not available, cannot install deps" 2>/dev/null || true
      emit_event "codebase-pilot" "npm_not_found" "error" 2>/dev/null || true
    fi
  fi
fi

# Skip if CLI not built
if [[ ! -f "$CLI" ]]; then
  hook_log "codebase-pilot: CLI not built at $CLI, skipping" 2>/dev/null || true
  emit_event "codebase-pilot" "cli_not_built" "error" 2>/dev/null || true
  exit 0
fi

# Skip if no source files exist in project (now includes .py)
# Also skip if project is too large (>10000 source files)
MAX_FILES=10000
SOURCE_COUNT=$(find "$PROJECT_ROOT" -maxdepth 5 \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/__pycache__/*" -not -path "*/.venv/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.next/*" 2>/dev/null | head -$((MAX_FILES + 1)) | wc -l)
if [[ "$SOURCE_COUNT" -eq 0 ]]; then
  hook_log "codebase-pilot: no source files in $PROJECT_ROOT, skipping" 2>/dev/null || true
  emit_event "codebase-pilot" "no_source_files" "allow" 2>/dev/null || true
  exit 0
fi
if [[ "$SOURCE_COUNT" -gt "$MAX_FILES" ]]; then
  hook_log "codebase-pilot: project too large (>${MAX_FILES} source files), skipping" 2>/dev/null || true
  emit_event "codebase-pilot" "index_skipped_too_large" "warn" 2>/dev/null || true
  exit 0
fi

# Persist session_id for CLI tools to find the reads file
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$$"
fi
INDEX_DIR="$PROJECT_ROOT/.codeindex"
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
  : > "/tmp/codebase-pilot-reads-${SESSION_ID}.jsonl" 2>/dev/null || true
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

# Run the indexer — capture stderr so we get the actual error in telemetry
_idx_start=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)} 2>/dev/null || true
_idx_ok=1
IDX_OUTPUT=$(node "$CLI" index "$PROJECT_ROOT" 2>&1) || _idx_ok=0
if [[ "$_idx_ok" -eq 0 ]]; then
  IDX_ERR_SHORT="${IDX_OUTPUT:0:200}"
  hook_log "codebase-pilot: indexing FAILED for $PROJECT_ROOT: $IDX_ERR_SHORT" 2>/dev/null || true
  emit_event "codebase-pilot" "index_failed" "error" 2>/dev/null || true
else
  _idx_end=${EPOCHREALTIME:-$(date +%s.%N 2>/dev/null || echo 0)} 2>/dev/null || true
  _idx_ms=$(awk "BEGIN {printf \"%d\", ($_idx_end - $_idx_start) * 1000}" 2>/dev/null || echo 0)
  emit_event "codebase-pilot" "index_success" "allow" "$_idx_ms" 2>/dev/null || true
fi

# Output the project map to stdout (injected as context for the agent)
# Only attempt map if indexing succeeded
MAP_OUTPUT=""
if [[ "$_idx_ok" -eq 1 ]]; then
  MAP_ERR=""
  MAP_OUTPUT=$(node "$CLI" map "$PROJECT_ROOT" 2>/tmp/codebase-pilot-map-err-$$.txt) || true
  MAP_ERR=$(head -c 200 /tmp/codebase-pilot-map-err-$$.txt 2>/dev/null || true)
  rm -f /tmp/codebase-pilot-map-err-$$.txt 2>/dev/null || true
  if [[ -z "$MAP_OUTPUT" ]]; then
    hook_log "codebase-pilot: map generation returned empty for $PROJECT_ROOT${MAP_ERR:+: $MAP_ERR}" 2>/dev/null || true
    emit_event "codebase-pilot" "map_empty" "warn" 2>/dev/null || true
  fi
fi

if [[ -n "$MAP_OUTPUT" ]]; then
  echo "--- Codebase Index (auto-generated) ---"
  echo "$MAP_OUTPUT"
  echo "--- End Codebase Index ---"
fi

# --- Task-aware context injection ---
# On SubagentStart, extract key terms from the agent's task/prompt and inject
# relevant symbols + file locations so the agent doesn't waste inference searching.
DB_PATH=""
for d in "$PROJECT_ROOT" "$PROJECT_ROOT/.codeindex"; do
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

# --- Subagent memory + capabilities injection ---
PLUGIN_ROOT_DIR="$(dirname "$PILOT_DIR")"
SUBAGENT_CONTEXT="$PLUGIN_ROOT_DIR/assets/subagent-context.md"
METRICS_DB_PATH="$PLUGIN_ROOT_DIR/data/metrics.db"

# Inject static capabilities doc
if [[ -f "$SUBAGENT_CONTEXT" ]]; then
  echo ""
  echo "--- Plugin Context (auto-injected) ---"
  cat "$SUBAGENT_CONTEXT"
fi

# Inject relevant memories for this agent's task
if command -v sqlite3 &>/dev/null && [[ -f "$METRICS_DB_PATH" ]]; then
  MEM_COUNT=$(sqlite3 "$METRICS_DB_PATH" "SELECT COUNT(*) FROM memories;" 2>/dev/null || echo "0")
  if [[ "$MEM_COUNT" -gt 0 ]]; then
    # Always inject top feedback-type memories (behavioral rules)
    FEEDBACK_MEMS=$(sqlite3 "$METRICS_DB_PATH" \
      "SELECT type, description FROM memories WHERE type='feedback' AND confidence > 0.3
       ORDER BY confidence DESC, access_count DESC LIMIT 3;" 2>/dev/null || true)

    # Also inject task-relevant memories via FTS5
    TASK_TEXT=$(echo "${INPUT:-}" | jq -r '(.tool_input.prompt // .tool_input.description // .prompt // "") | .[0:2000]' 2>/dev/null || true)
    FTS_MEMS=""
    if [[ -n "$TASK_TEXT" && ${#TASK_TEXT} -gt 10 ]]; then
      FTS_TERMS=$(echo "$TASK_TEXT" | \
        grep -oE '\b[A-Z][a-zA-Z0-9]{2,}\b|\b[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*\b|\b[a-z_]{4,}\b' | \
        tr '[:upper:]' '[:lower:]' | \
        grep -vE '^(this|that|with|from|have|been|will|would|could|should|there|their|about|which|when|what|make|just|more|also|than|them|then|these|those|each|into|some|like|over|such|only|after|before|other|your|does|were|being|here|very|most|much|need|want|help|please|using|file|code)$' | \
        sort -u | head -6)
      if [[ -n "$FTS_TERMS" ]]; then
        FTS_QUERY=$(echo "$FTS_TERMS" | tr '\n' ' ' | sed 's/ *$//' | sed 's/ / OR /g')
        # Composite ranking: FTS relevance + confidence + usage frequency
        FTS_MEMS=$(sqlite3 "$METRICS_DB_PATH" \
          "SELECT m.type, m.description FROM memories m
           INNER JOIN (
             SELECT rowid, rank FROM memories_fts WHERE memories_fts MATCH '$FTS_QUERY'
           ) fts ON m.rowid = fts.rowid
           WHERE m.confidence > 0.3 AND m.type != 'feedback'
           ORDER BY (fts.rank * -1.0 + m.confidence * 5.0 + MIN(m.access_count, 10) * 0.5) DESC
           LIMIT 3;" 2>/dev/null || true)
      fi
    fi

    if [[ -n "$FEEDBACK_MEMS" || -n "$FTS_MEMS" ]]; then
      echo ""
      if [[ -n "$FEEDBACK_MEMS" ]]; then
        echo "$FEEDBACK_MEMS" | while IFS='|' read -r mtype mdesc; do
          [[ -z "$mdesc" ]] && continue
          echo "[memory:${mtype}] ${mdesc}"
        done
      fi
      if [[ -n "$FTS_MEMS" ]]; then
        echo "$FTS_MEMS" | while IFS='|' read -r mtype mdesc; do
          [[ -z "$mdesc" ]] && continue
          echo "[memory:${mtype}] ${mdesc}"
        done
      fi
    fi
  fi
  echo "--- End Plugin Context ---"
elif [[ -f "$SUBAGENT_CONTEXT" ]]; then
  echo "--- End Plugin Context ---"
fi

echo ""
echo "Use codebase-pilot tools: find_symbol, find_usages, file_overview, related_files, navigate for code navigation."

# --- Agent mesh registration ---
MESH_CLI="$PLUGIN_ROOT/agent-mesh/cli.js"
if [[ -f "$MESH_CLI" ]]; then
  AGENT_NAME="${AGENT_MESH_NAME:-agent-${SESSION_ID}}"
  BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
  node "$MESH_CLI" register \
    --id "$SESSION_ID" \
    --name "$AGENT_NAME" \
    --worktree "$PROJECT_ROOT" \
    --branch "$BRANCH" \
    --pid "$PPID" 2>/dev/null || true

  # NOTE: Deregistration is handled by session-end-dispatcher.sh (SessionEnd hook).
  # Do NOT add an EXIT/INT/TERM trap here — this script runs as a short-lived hook
  # process, so traps fire immediately when the script exits, not when the Claude
  # session ends. That was the original bug that broke the entire mesh.

  OTHERS=$(node "$MESH_CLI" list --exclude "$SESSION_ID" --brief 2>/dev/null || true)
  if [[ -n "$OTHERS" ]]; then
    echo ""
    echo "[agent-mesh] Other agents active in this repo:"
    echo "$OTHERS"
  fi
fi

exit 0
