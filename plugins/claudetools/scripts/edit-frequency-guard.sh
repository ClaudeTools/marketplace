#!/usr/bin/env bash
# PostToolUse:Edit|Write hook — tracks per-file edit frequency and warns on repeated edits
# After 3+ edits to the same file, warns the agent to stop guessing and add diagnostics.
# Exit 1 for warning (soft), exit 0 for normal edits.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the edited file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Skip if no file path (shouldn't happen, but be safe)
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip non-code files — repeated edits to config/docs are fine
case "$FILE_PATH" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.csv)
    exit 0
    ;;
  */.claude/*)
    exit 0
    ;;
esac

# Track edit counts in a temp file keyed by parent process (session)
COUNTER_FILE="/tmp/claude-edit-counts-${PPID}"

# Initialize counter file if it doesn't exist
if [ ! -f "$COUNTER_FILE" ]; then
  echo "{}" > "$COUNTER_FILE"
fi

# Read-modify-write under advisory lock to prevent race conditions
(
  flock -x 200

  # Read current count for this file
  CURRENT_COUNT=$(jq -r --arg file "$FILE_PATH" '.[$file] // 0' "$COUNTER_FILE" 2>/dev/null || echo "0")
  NEW_COUNT=$((CURRENT_COUNT + 1))

  # Update counter file atomically
  TEMP_COUNTER=$(mktemp)
  jq --arg file "$FILE_PATH" --argjson count "$NEW_COUNT" '.[$file] = $count' "$COUNTER_FILE" > "$TEMP_COUNTER" 2>/dev/null && mv "$TEMP_COUNTER" "$COUNTER_FILE" || rm -f "$TEMP_COUNTER"
) 200>"${COUNTER_FILE}.lock"

# Re-read the count from the updated file (subshell variables don't propagate)
NEW_COUNT=$(jq -r --arg file "$FILE_PATH" '.[$file] // 0' "$COUNTER_FILE" 2>/dev/null || echo "0")

hook_log "file=$FILE_PATH edit_count=$NEW_COUNT"

# Read adaptive threshold (model-aware)
EDIT_THRESHOLD=$(get_threshold "edit_frequency_limit" "$MODEL_FAMILY")
EDIT_THRESHOLD=${EDIT_THRESHOLD%.*}

# Warn after threshold edits to the same file
if [ "$NEW_COUNT" -ge "$EDIT_THRESHOLD" ]; then
  FILENAME=$(basename "$FILE_PATH")
  echo "THREE-STRIKE WARNING: You've edited '${FILENAME}' ${NEW_COUNT} times this session." >&2
  echo "Stop guessing. Add diagnostic logging, read the output, get evidence, THEN make your next edit." >&2
  echo "If this is the 4th+ edit, consider whether a focused rewrite would be more effective than incremental patches." >&2
  HOOK_DECISION="warn"; HOOK_REASON="file ${FILENAME} edited ${NEW_COUNT} times"
  record_hook_outcome "edit-frequency-guard" "PostToolUse" "warn" "Edit" "edit_frequency_limit" "$EDIT_THRESHOLD" "$MODEL_FAMILY"
  exit 1
fi

record_hook_outcome "edit-frequency-guard" "PostToolUse" "allow" "Edit" "" "" "$MODEL_FAMILY"
exit 0
