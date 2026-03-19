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

# Adaptive thresholds (tunable via /tune-thresholds)
WARN_THRESHOLD=$(get_threshold "read_warn_lines" "$MODEL_FAMILY")
WARN_THRESHOLD=${WARN_THRESHOLD%.*}
BLOCK_THRESHOLD=$(get_threshold "read_block_lines" "$MODEL_FAMILY")
BLOCK_THRESHOLD=${BLOCK_THRESHOLD%.*}

if [ "$LINE_COUNT" -gt "$BLOCK_THRESHOLD" ]; then
  BLOCKED="File '${BASENAME}' is ${LINE_COUNT} lines — too large to read in full.
To read a specific section: Read with offset=100 limit=50 (reads lines 100-150).
To find what you need: use Grep to locate the relevant lines first, then Read that range."
  HOOK_DECISION="block" HOOK_REASON="large file read without offset/limit (${LINE_COUNT} lines)"
  record_hook_outcome "enforce-read-efficiency" "PreToolUse" "block" "Read" "read_block_lines" "$BLOCK_THRESHOLD" "$MODEL_FAMILY"
  emit_event "enforce-read-efficiency" "large_read_blocked" "block" "0" "{\"lines\":${LINE_COUNT}}" 2>/dev/null || true
  jq -n --arg reason "$BLOCKED" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
  exit 0
fi

if [ "$LINE_COUNT" -gt "$WARN_THRESHOLD" ]; then
  echo "{\"systemMessage\":\"File '${BASENAME}' is ${LINE_COUNT} lines. Read a targeted section with offset and limit parameters instead of the full file.\"}"
  HOOK_DECISION="warn" HOOK_REASON="medium file read without offset/limit (${LINE_COUNT} lines)"
  record_hook_outcome "enforce-read-efficiency" "PreToolUse" "warn" "Read" "read_warn_lines" "$WARN_THRESHOLD" "$MODEL_FAMILY"
  emit_event "enforce-read-efficiency" "medium_read_warned" "warn" "0" "{\"lines\":${LINE_COUNT}}" 2>/dev/null || true
  exit 0
fi

record_hook_outcome "enforce-read-efficiency" "PreToolUse" "allow" "Read" "" "" "$MODEL_FAMILY"
exit 0
