#!/usr/bin/env bash
# memory-extract-fast.sh — Stop hook (async)
# Deterministic extraction of memory candidates from session transcript.
# Zero external deps. Appends candidates to memory-candidates.jsonl.

set -euo pipefail

source "$(dirname "$0")/hook-log.sh"

INPUT=$(cat 2>/dev/null || true)

PLUGIN_DATA="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/data"
mkdir -p "$PLUGIN_DATA" 2>/dev/null || true
CANDIDATES_FILE="$PLUGIN_DATA/memory-candidates.jsonl"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Need a transcript to extract from
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  hook_log "memory-extract-fast: no transcript found"
  exit 0
fi

hook_log "memory-extract-fast: processing $TRANSCRIPT"

# Read last ~100 lines of transcript (most recent messages)
TAIL_CONTENT=$(tail -100 "$TRANSCRIPT" 2>/dev/null || true)
if [[ -z "$TAIL_CONTENT" ]]; then
  exit 0
fi

# Helper: append a candidate to the JSONL file
emit_candidate() {
  local ctype="$1"
  local desc="$2"
  # Escape for JSON: backslashes, quotes, newlines
  desc=$(printf '%s' "$desc" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 200)
  echo "{\"type\":\"$ctype\",\"description\":\"$desc\",\"source\":\"stop-extract\",\"session_id\":\"$SESSION_ID\",\"timestamp\":\"$TIMESTAMP\"}" >> "$CANDIDATES_FILE"
}

# --- Extract user corrections ---
# Look for user messages with correction indicators
echo "$TAIL_CONTENT" | jq -r '
  select(.role == "human" or .role == "user") |
  .content // .message // "" |
  if type == "array" then map(select(type == "string" or .type == "text") | if type == "string" then . else .text end) | join(" ") else . end
' 2>/dev/null | while IFS= read -r msg; do
  [[ -z "$msg" ]] && continue
  # Check for correction patterns
  if echo "$msg" | grep -qiE '\b(no[, ]+not|don'\''t|do not|instead[, ]+use|actually[, ]|stop doing|wrong|shouldn'\''t|that'\''s not)'; then
    emit_candidate "correction" "$msg"
  fi
done

# --- Extract error patterns ---
# Look for tool failures or error messages in assistant responses
echo "$TAIL_CONTENT" | jq -r '
  select(.role == "assistant") |
  .content // "" |
  if type == "array" then map(select(.type == "tool_result" or .type == "text") |
    if .type == "tool_result" then (.content // "") else (.text // "") end) | join(" ")
  else . end
' 2>/dev/null | grep -iE '(error|exception|failed|traceback|panic|ENOENT|EACCES|permission denied)' 2>/dev/null | head -5 | while IFS= read -r err; do
  [[ -z "$err" ]] && continue
  emit_candidate "error" "$err"
done

# --- Detect file churn ---
# Count how many times each file was edited
EDIT_COUNTS=$(echo "$TAIL_CONTENT" | jq -r '
  select(.role == "assistant") | .content // [] |
  if type == "array" then .[] else empty end |
  select(.type == "tool_use" and (.name == "Edit" or .name == "Write")) |
  .input.file_path // .input.path // empty
' 2>/dev/null | sort | uniq -c | sort -rn || true)

if [[ -n "$EDIT_COUNTS" ]]; then
  echo "$EDIT_COUNTS" | while read -r count filepath; do
    if [[ "$count" -ge 3 && -n "$filepath" ]]; then
      emit_candidate "churn" "File edited $count times in session: $filepath"
    fi
  done
fi

CANDIDATE_COUNT=$(wc -l < "$CANDIDATES_FILE" 2>/dev/null || echo 0)
hook_log "memory-extract-fast: extracted candidates (total in file: $CANDIDATE_COUNT)"
exit 0
