#!/usr/bin/env bash
# PostToolUse:Read hook — tracks which files and line ranges Claude reads
# Records {"path":"...","ts":N,"event":"read","offset":O,"limit":L} to per-session JSONL.
# Fast (<50ms) — single jq parse + append. Always exits 0.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# Single jq call to extract all fields (avoids 4 separate forks)
eval "$(echo "$INPUT" | jq -r '
  @sh "FILE_PATH=\(.tool_input.file_path // "")",
  @sh "SESSION_ID=\(.session_id // "")",
  @sh "OFFSET=\(.tool_input.offset // 1)",
  @sh "LIMIT=\(.tool_input.limit // 2000)"
' 2>/dev/null)" || { FILE_PATH=""; SESSION_ID=""; OFFSET=1; LIMIT=2000; }

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$PPID"
fi

READS_FILE="/tmp/codebase-pilot-reads-${SESSION_ID}.jsonl"
TS=$(date +%s)

# Use jq for proper JSON encoding (handles quotes, backslashes, unicode in paths)
jq -nc \
  --arg p "$FILE_PATH" \
  --argjson t "$TS" \
  --argjson o "$OFFSET" \
  --argjson l "$LIMIT" \
  '{"path":$p,"ts":$t,"event":"read","offset":$o,"limit":$l}' \
  >> "$READS_FILE" 2>/dev/null || true

exit 0
