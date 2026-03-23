#!/bin/bash
# PostToolUseFailure hook - detects repeated failures for the same tool+error pattern
# and hard-blocks after 3+ identical failures to force a rethink.

source "$(dirname "$0")/hook-log.sh"

INPUT=$(cat 2>/dev/null || true)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
ERROR=$(echo "$INPUT" | jq -r '.error // .tool_response.stderr // empty' | head -c 200)

FAILURE_LOG="/tmp/claude-failures-${SESSION_ID:-$$}.jsonl"

# Create a normalised error key (first 80 chars, stripped of paths and line numbers)
ERROR_KEY=$(echo "$ERROR" | head -c 80 | sed 's|/[^ ]*||g; s|line [0-9]*||g; s|[0-9]\{4,\}||g' | tr -d '"')

# Append failure record with error_key for pattern matching
jq -cn --arg tool "$TOOL_NAME" --arg error "$ERROR" --arg key "$ERROR_KEY" --arg time "$(date -Iseconds)" \
  '{tool: $tool, error: $error, error_key: $key, time: $time}' >> "$FAILURE_LOG"

# Count failures for this tool+error pattern (not just tool name)
PATTERN_COUNT=0
TOOL_TOTAL=0
if [ -f "$FAILURE_LOG" ]; then
  PATTERN_COUNT=$(jq -r --arg tool "$TOOL_NAME" --arg key "$ERROR_KEY" \
    'select(.tool == $tool and .error_key == $key)' "$FAILURE_LOG" 2>/dev/null | grep -c '{' || true)
  TOOL_TOTAL=$(jq -r --arg tool "$TOOL_NAME" \
    'select(.tool == $tool)' "$FAILURE_LOG" 2>/dev/null | grep -c '{' || true)
fi
[ -z "$PATTERN_COUNT" ] && PATTERN_COUNT=0
[ -z "$TOOL_TOTAL" ] && TOOL_TOTAL=0

source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
source "$(dirname "$0")/lib/telemetry.sh" 2>/dev/null || true

# Emit error telemetry for every failure
local _error_class
_error_class=$(echo "$ERROR_KEY" | tr ' ' '_' | head -c 40)
emit_error "$TOOL_NAME" "$_error_class" "failure-pattern-detector" "false" 2>/dev/null || true

# Read adaptive threshold (model-aware)
FAILURE_LIMIT=$(get_threshold "failure_loop_limit")
FAILURE_LIMIT=${FAILURE_LIMIT%.*}

hook_log "tool=$TOOL_NAME pattern_count=$PATTERN_COUNT tool_total=$TOOL_TOTAL limit=$FAILURE_LIMIT error_key=$(echo "$ERROR_KEY" | head -c 40)"

if [ "$PATTERN_COUNT" -ge "$FAILURE_LIMIT" ]; then
  echo "STOP: $TOOL_NAME has failed $PATTERN_COUNT times with the same error pattern this session." >&2
  echo "Error pattern: $ERROR_KEY" >&2
  echo "Step back and rethink your approach. Review error messages, check documentation, or try a different strategy." >&2
  hook_log_result 2 "block" "repeated-failure: $TOOL_NAME same-pattern failed $PATTERN_COUNT times"
  record_hook_outcome "failure-pattern-detector" "PostToolUseFailure" "block" "$TOOL_NAME" "failure_loop_limit" "$FAILURE_LIMIT" "$MODEL_FAMILY"
  exit 2
fi

# Also warn (but don't block) if tool has many diverse failures
DIVERSE_WARN=$(get_threshold "diverse_failure_total_warn")
DIVERSE_WARN=${DIVERSE_WARN%.*}
if [ "$TOOL_TOTAL" -ge "$DIVERSE_WARN" ]; then
  echo "WARNING: $TOOL_NAME has failed $TOOL_TOTAL times total this session (across different error types). Consider whether this tool is the right approach." >&2
  hook_log_result 1 "warn" "high-failure-count: $TOOL_NAME total=$TOOL_TOTAL"
  record_hook_outcome "failure-pattern-detector" "PostToolUseFailure" "warn" "$TOOL_NAME" "diverse_failure_total_warn" "$DIVERSE_WARN" "$MODEL_FAMILY"
  exit 1
fi

record_hook_outcome "failure-pattern-detector" "PostToolUseFailure" "allow" "$TOOL_NAME" "" "" "$MODEL_FAMILY"
exit 0
