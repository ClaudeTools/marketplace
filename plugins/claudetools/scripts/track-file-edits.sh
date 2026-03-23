#!/usr/bin/env bash
# PostToolUse:Edit|Write hook — records edit events to session JSONL (sync)
# Must run BEFORE any async hooks so the guard can see edits immediately.
# Fast (<50ms) — single jq parse + append. Always exits 0.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# Single jq call to extract all fields
eval "$(echo "$INPUT" | jq -r '
  @sh "FILE_PATH=\(.tool_input.file_path // "")",
  @sh "SESSION_ID=\(.session_id // "")"
' 2>/dev/null)" || { FILE_PATH=""; SESSION_ID=""; }

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$PPID"
fi

READS_FILE="/tmp/codebase-pilot-reads-${SESSION_ID}.jsonl"
TS=$(date +%s)

# Record edit event (all file types — context tracking isn't limited to source code)
jq -nc \
  --arg p "$FILE_PATH" \
  --argjson t "$TS" \
  '{"path":$p,"ts":$t,"event":"edit"}' \
  >> "$READS_FILE" 2>/dev/null || true

exit 0
