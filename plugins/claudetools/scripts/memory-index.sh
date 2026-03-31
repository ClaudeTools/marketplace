#!/usr/bin/env bash
# memory-index.sh — PostToolUse hook (Write|Edit matcher)
# Indexes native memory/ files into SQLite memories table + FTS5
# Only fires on writes to */memory/* paths. Async, exits 0 always.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/telemetry.sh" 2>/dev/null || true

INPUT=$(cat 2>/dev/null || true)

# Extract file_path from hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)

# Only process writes to memory/ directories
if [[ "$FILE_PATH" != */memory/* ]]; then
  exit 0
fi

# Skip MEMORY.md index file itself
BASENAME=$(basename "$FILE_PATH")
if [[ "$BASENAME" == "MEMORY.md" ]]; then
  exit 0
fi

# Skip non-markdown files
if [[ "$FILE_PATH" != *.md ]]; then
  exit 0
fi

# Verify file exists and is readable
if [[ ! -f "$FILE_PATH" ]]; then
  hook_log "memory-index: file not found: $FILE_PATH"
  exit 0
fi

# sqlite3 required
if ! command -v sqlite3 &>/dev/null; then
  exit 0
fi

ensure_metrics_db 2>/dev/null || exit 0

hook_log "memory-index: indexing $FILE_PATH"

# Parse YAML frontmatter
# Format:
# ---
# name: ...
# description: ...
# type: ...
# ---
# <body content>

IN_FRONTMATTER=0
PAST_FRONTMATTER=0
MEM_NAME=""
MEM_DESC=""
MEM_TYPE=""
BODY=""

while IFS= read -r line; do
  if [[ "$IN_FRONTMATTER" -eq 0 && "$PAST_FRONTMATTER" -eq 0 && "$line" == "---" ]]; then
    IN_FRONTMATTER=1
    continue
  fi
  if [[ "$IN_FRONTMATTER" -eq 1 && "$line" == "---" ]]; then
    IN_FRONTMATTER=0
    PAST_FRONTMATTER=1
    continue
  fi
  if [[ "$IN_FRONTMATTER" -eq 1 ]]; then
    # Parse frontmatter key-value pairs
    case "$line" in
      name:*)    MEM_NAME=$(echo "$line" | sed 's/^name:[[:space:]]*//' | sed 's/^["'\'']//' | sed 's/["'\'']$//') ;;
      description:*) MEM_DESC=$(echo "$line" | sed 's/^description:[[:space:]]*//' | sed 's/^["'\'']//' | sed 's/["'\'']$//') ;;
      type:*)    MEM_TYPE=$(echo "$line" | sed 's/^type:[[:space:]]*//' | sed 's/^["'\'']//' | sed 's/["'\'']$//') ;;
    esac
    continue
  fi
  # Accumulate body content
  if [[ "$PAST_FRONTMATTER" -eq 1 ]]; then
    if [[ -n "$BODY" ]]; then
      BODY="${BODY}
${line}"
    else
      BODY="$line"
    fi
  fi
done < "$FILE_PATH"

# If no frontmatter parsed, use filename as name and full content as body
if [[ -z "$MEM_NAME" ]]; then
  MEM_NAME="${BASENAME%.md}"
fi
if [[ -z "$MEM_TYPE" ]]; then
  MEM_TYPE="unknown"
fi
if [[ -z "$BODY" ]]; then
  BODY=$(cat "$FILE_PATH")
fi

# Generate deterministic ID from file path (stable across content changes)
MEM_ID=$(printf '%s' "$FILE_PATH" | sha256sum 2>/dev/null | head -c 16 || printf '%s' "$FILE_PATH" | shasum -a 256 2>/dev/null | head -c 16 || echo "$RANDOM$RANDOM")

# Escape single quotes for SQL
sql_escape() {
  echo "$1" | sed "s/'/''/g"
}

E_NAME=$(sql_escape "$MEM_NAME")
E_DESC=$(sql_escape "$MEM_DESC")
E_TYPE=$(sql_escape "$MEM_TYPE")
E_BODY=$(sql_escape "$BODY")
E_PATH=$(sql_escape "$FILE_PATH")

# UPSERT into memories table
sqlite3 "$METRICS_DB" "INSERT INTO memories (id, content, type, name, description, source, file_path, created_at)
  VALUES ('$MEM_ID', '$E_BODY', '$E_TYPE', '$E_NAME', '$E_DESC', 'human', '$E_PATH', datetime('now'))
  ON CONFLICT(id) DO UPDATE SET
    content = excluded.content,
    type = excluded.type,
    name = excluded.name,
    description = excluded.description,
    file_path = excluded.file_path;" 2>/dev/null || {
  hook_log "memory-index: sqlite3 upsert failed for $FILE_PATH"
  exit 0
}

hook_log "memory-index: indexed $MEM_NAME (type=$MEM_TYPE, id=$MEM_ID)"
emit_event "memory" "memory_indexed" "allow" "0" "$(printf '{"name":"%s","type":"%s","file":"%s"}' "$MEM_NAME" "$MEM_TYPE" "$BASENAME")" 2>/dev/null || true
exit 0
