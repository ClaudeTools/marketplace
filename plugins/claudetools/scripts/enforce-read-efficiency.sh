#!/bin/bash
# PreToolUse:Read hook — blocks wasteful full-file reads on large files
# Enforces offset/limit usage for files over a threshold to save context tokens.
# Only fires on Read tool (not Edit/Write — they need full context).
# Exit 0 always — blocking done via JSON stdout with permissionDecision "block"

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
source "$(dirname "$0")/lib/telemetry.sh" 2>/dev/null || true
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Only apply to Read tool — Edit/Write need full file context
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
if [ "$TOOL_NAME" != "Read" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Check if offset or limit was specified
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty' 2>/dev/null || true)
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null || true)

# If offset or limit is set, the agent is already being targeted — allow
if [ -n "$OFFSET" ] || [ -n "$LIMIT" ]; then
  exit 0
fi

# Skip binary files, images, PDFs — size check doesn't apply
case "$FILE_PATH" in
  *.png|*.jpg|*.jpeg|*.gif|*.ico|*.svg|*.woff*|*.ttf|*.eot|*.pdf|*.zip|*.tar*|*.gz)
    exit 0 ;;
esac

# Count lines in the file
LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null || echo "0")
LINE_COUNT=${LINE_COUNT// /}
BASENAME=$(basename "$FILE_PATH")

# Thresholds
WARN_THRESHOLD=500
BLOCK_THRESHOLD=2000

if [ "$LINE_COUNT" -gt "$BLOCK_THRESHOLD" ]; then
  BLOCKED="File '${BASENAME}' has ${LINE_COUNT} lines. Reading the entire file wastes context tokens. Use offset and limit parameters to read the section you need, or use Grep to find the specific lines first."
  HOOK_DECISION="block" HOOK_REASON="large file read without offset/limit (${LINE_COUNT} lines)"
  record_hook_outcome "enforce-read-efficiency" "PreToolUse" "block" "Read" "" "" "$MODEL_FAMILY"
  emit_event "enforce-read-efficiency" "large_read_blocked" "block" "0" "{\"lines\":${LINE_COUNT}}" 2>/dev/null || true
  jq -n --arg reason "$BLOCKED" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
  exit 0
fi

if [ "$LINE_COUNT" -gt "$WARN_THRESHOLD" ]; then
  # Warn but don't block — medium files
  echo "{\"systemMessage\":\"File '${BASENAME}' has ${LINE_COUNT} lines. Consider using offset/limit parameters to read only the section you need — saves context tokens.\"}"
  HOOK_DECISION="warn" HOOK_REASON="medium file read without offset/limit (${LINE_COUNT} lines)"
  record_hook_outcome "enforce-read-efficiency" "PreToolUse" "warn" "Read" "" "" "$MODEL_FAMILY"
  emit_event "enforce-read-efficiency" "medium_read_warned" "warn" "0" "{\"lines\":${LINE_COUNT}}" 2>/dev/null || true
  exit 0
fi

record_hook_outcome "enforce-read-efficiency" "PreToolUse" "allow" "Read" "" "" "$MODEL_FAMILY"
exit 0
