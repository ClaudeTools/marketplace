#!/usr/bin/env bash
# SessionStart / SubagentStart hook: index the project and output a project map
# This script runs when a session or subagent starts, building/updating the
# codebase index and injecting a compact project map into the agent's context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PILOT_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PILOT_DIR/dist/cli.js"

# Source shared logging if available
PLUGIN_ROOT="$(dirname "$PILOT_DIR")"
LOG_SCRIPT="$PLUGIN_ROOT/scripts/hook-log.sh"
if [[ -f "$LOG_SCRIPT" ]]; then
  source "$LOG_SCRIPT"
fi

# Determine project root from CWD (Claude Code sets this to the project)
PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"

# Auto-install dependencies if missing (one-time setup)
if [[ ! -d "$PILOT_DIR/node_modules" ]]; then
  if command -v npm &>/dev/null; then
    (cd "$PILOT_DIR" && npm install --production --no-audit --no-fund 2>/dev/null) || true
  fi
fi

# Skip if CLI not built
if [[ ! -f "$CLI" ]]; then
  exit 0
fi

# Skip if no source files exist in project
SOURCE_COUNT=$(find "$PROJECT_ROOT" -maxdepth 3 \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -5 | wc -l)
if [[ "$SOURCE_COUNT" -eq 0 ]]; then
  if [[ "$(type -t log_hook 2>/dev/null)" == "function" ]]; then
    log_hook "codebase-pilot" "skip" "No source files found in $PROJECT_ROOT"
  fi
  exit 0
fi

# Run the indexer (output goes to stderr)
node "$CLI" index "$PROJECT_ROOT" 2>/dev/null || true

# Output the project map to stdout (injected as context for the agent)
MAP_OUTPUT=$(node "$CLI" map "$PROJECT_ROOT" 2>/dev/null) || true

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

echo ""
echo "Use MCP tools project_map, find_symbol, find_usages, file_overview, related_files for detailed navigation."

exit 0
