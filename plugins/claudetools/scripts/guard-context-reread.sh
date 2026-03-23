#!/usr/bin/env bash
# PreToolUse:Read hook — prevents wasteful re-reads with context-aware guidance
# Checks session reads JSONL + file mtime to determine if a read is redundant.
#
# Four context states:
#   1. [in context]         — file read, unchanged since → warn: don't re-read
#   2. [in context, edited] — file read, then Claude-edited → soft hint
#   3. [was read]           — read before compaction → allow (content compacted out)
#   4. (no state)           — never read or externally modified → allow silently
#
# Exit 2 = block redundant full-file re-reads. Exit 0 = allow.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# Single jq call to extract all needed fields
eval "$(echo "$INPUT" | jq -r '
  @sh "FILE_PATH=\(.tool_input.file_path // "")",
  @sh "REQ_OFFSET=\(.tool_input.offset // 1)",
  @sh "REQ_LIMIT=\(.tool_input.limit // 2000)"
' 2>/dev/null)" || { FILE_PATH=""; REQ_OFFSET=1; REQ_LIMIT=2000; }

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Find session IDs file
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$CWD}"
SESSION_IDS_FILE="$PROJECT_ROOT/.codeindex/session-ids"

if [ ! -f "$SESSION_IDS_FILE" ]; then
  exit 0
fi

# Collect entries into temp file (avoids O(n²) string concatenation)
ENTRIES_FILE=$(mktemp 2>/dev/null || echo "/tmp/codebase-pilot-guard-$$")
trap "rm -f '$ENTRIES_FILE'" EXIT

while IFS= read -r sid; do
  [ -z "$sid" ] && continue
  READS_FILE="/tmp/codebase-pilot-reads-${sid}.jsonl"
  [ -f "$READS_FILE" ] || continue
  # File-specific entries + compact events
  grep -F "$FILE_PATH" "$READS_FILE" >> "$ENTRIES_FILE" 2>/dev/null || true
  grep -F '"event":"compact"' "$READS_FILE" >> "$ENTRIES_FILE" 2>/dev/null || true
done < "$SESSION_IDS_FILE"

# No entries → first read, allow
if [ ! -s "$ENTRIES_FILE" ]; then
  exit 0
fi

# Single jq call to compute all needed values
REQ_END=$((REQ_OFFSET + REQ_LIMIT))
ANALYSIS=$(jq -R -s --arg p "$FILE_PATH" --argjson ro "$REQ_OFFSET" --argjson re "$REQ_END" '
  split("\n") | map(select(length > 0) | (fromjson? // empty)) |
  {
    last_read_ts: [.[] | select(.path == $p and (.event == "read" or .event == null)) | .ts] | max // 0,
    last_edit_ts: [.[] | select(.path == $p and .event == "edit") | .ts] | max // 0,
    last_compact_ts: [.[] | select(.event == "compact") | .ts] | max // 0,
    has_covering_read: ([.[] | select(
      .path == $p and (.event == "read" or .event == null) and
      ((.offset // 1) <= $ro) and (((.offset // 1) + (.limit // 2000)) >= $re)
    )] | length > 0)
  }
' "$ENTRIES_FILE" 2>/dev/null || echo '{}')

LAST_READ_TS=$(echo "$ANALYSIS" | jq -r '.last_read_ts // 0' 2>/dev/null || echo "0")
LAST_EDIT_TS=$(echo "$ANALYSIS" | jq -r '.last_edit_ts // 0' 2>/dev/null || echo "0")
LAST_COMPACT_TS=$(echo "$ANALYSIS" | jq -r '.last_compact_ts // 0' 2>/dev/null || echo "0")
HAS_COVERING=$(echo "$ANALYSIS" | jq -r '.has_covering_read // false' 2>/dev/null || echo "false")

if [ "$LAST_READ_TS" = "0" ]; then
  exit 0
fi

# Cross-platform file mtime (seconds since epoch)
# Linux: stat -c %Y, macOS: stat -f %m
FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || stat -f %m "$FILE_PATH" 2>/dev/null || echo "0")

BASENAME=$(basename "$FILE_PATH")

# --- Symbol hints from SQLite index (appended to warnings) ---
SYMBOL_HINTS=""
DB_PATH="$PROJECT_ROOT/.codeindex/db.sqlite"
if command -v sqlite3 &>/dev/null && [ -f "$DB_PATH" ]; then
  # Convert absolute path to relative for index lookup
  REL_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
  # Parameterized query — no path interpolation into SQL
  RAW_SYMBOLS=$(sqlite3 "$DB_PATH" -separator '|' \
    -cmd ".parameter set :path $REL_PATH" \
    "SELECT s.name, s.line, s.end_line FROM symbols s JOIN files f ON s.file_id = f.id WHERE f.path = :path AND s.exported = 1 AND s.kind IN ('function','method','class') ORDER BY s.line LIMIT 5" \
    2>/dev/null || true)
  if [ -n "$RAW_SYMBOLS" ]; then
    # Format: "handleFoo (L20-45), handleBar (L60-90)"
    HINTS_LIST=""
    while IFS='|' read -r sname sline send_line; do
      [ -z "$sname" ] && continue
      if [ -n "$send_line" ] && [ "$send_line" != "" ]; then
        HINTS_LIST="${HINTS_LIST}${HINTS_LIST:+, }${sname} (L${sline}-${send_line})"
      else
        HINTS_LIST="${HINTS_LIST}${HINTS_LIST:+, }${sname} (L${sline})"
      fi
    done <<< "$RAW_SYMBOLS"
    [ -n "$HINTS_LIST" ] && SYMBOL_HINTS=" Key symbols: ${HINTS_LIST}."
  fi
fi

# --- Decision tree ---

# State 3: Read before compaction → allow (content compacted out)
if [ "$LAST_COMPACT_TS" -gt 0 ] 2>/dev/null && [ "$LAST_READ_TS" -lt "$LAST_COMPACT_TS" ] 2>/dev/null; then
  exit 0
fi

# File modified since last read?
if [ "$FILE_MTIME" -gt "$LAST_READ_TS" ] 2>/dev/null; then
  # State 2: Claude edited it
  if [ "$LAST_EDIT_TS" -gt 0 ] 2>/dev/null && [ "$LAST_EDIT_TS" -ge "$LAST_READ_TS" ] 2>/dev/null; then
    jq -nc --arg b "$BASENAME" --arg h "$SYMBOL_HINTS" \
      '{"systemMessage": ("You edited \u0027" + $b + "\u0027 since you last read it. If verifying your changes, read only the changed section with offset/limit." + $h)}'
    exit 0
  fi
  # State 4: Externally modified → allow silently
  exit 0
fi

# State 1: File unchanged since last read → check range overlap
if [ "$HAS_COVERING" = "true" ]; then
  if [ "$REQ_OFFSET" -le 1 ] 2>/dev/null && [ "$REQ_LIMIT" -ge 2000 ] 2>/dev/null; then
    # Full-file re-read of unchanged file — hard block to save context
    echo "'${BASENAME}' is unchanged and already in context. Use offset/limit to read a specific section.${SYMBOL_HINTS}" >&2
    exit 2
  else
    jq -nc --arg b "$BASENAME" --argjson s "$REQ_OFFSET" --argjson e "$REQ_END" --arg h "$SYMBOL_HINTS" \
      '{"systemMessage": ("Lines " + ($s|tostring) + "-" + ($e|tostring) + " of \u0027" + $b + "\u0027 are already in context. Use your existing knowledge." + $h)}'
  fi
  exit 0
fi

# Requested range not covered → allow (new section)
exit 0
