#!/usr/bin/env bash
# PostToolUse:Edit|Write hook — tracks per-file edit frequency with progressive disclosure
# Uses 3 escalation tiers to give increasingly specific guidance as edit count grows:
#   Tier 1 (threshold):    Brief nudge — mention the count, suggest diagnostics
#   Tier 2 (threshold+2):  Detailed — explain the churn pattern, suggest rewrite
#   Tier 3 (threshold+4):  Full escalation — concrete recovery steps
# Exit 1 for warning (soft), exit 0 for normal edits.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
source "$(dirname "$0")/lib/worktree.sh"
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

# Track edit counts in a temp file keyed by session
COUNTER_FILE=$(session_tmp_path "edit-counts")

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

# --- Progressive disclosure: escalating warnings based on edit count ---
# Tier 1 (threshold):    Brief nudge — mention the count, suggest diagnostics
# Tier 2 (threshold+2):  Detailed — explain the churn pattern, suggest rewrite
# Tier 3 (threshold+4):  Full escalation — concrete recovery steps
TIER2_THRESHOLD=$((EDIT_THRESHOLD + 2))
TIER3_THRESHOLD=$((EDIT_THRESHOLD + 4))

if [ "$NEW_COUNT" -ge "$EDIT_THRESHOLD" ]; then
  FILENAME=$(basename "$FILE_PATH")
  HOOK_DECISION="warn"; HOOK_REASON="file ${FILENAME} edited ${NEW_COUNT} times (tier $([ "$NEW_COUNT" -ge "$TIER3_THRESHOLD" ] && echo 3 || ([ "$NEW_COUNT" -ge "$TIER2_THRESHOLD" ] && echo 2 || echo 1)))"

  if [ "$NEW_COUNT" -ge "$TIER3_THRESHOLD" ]; then
    # Tier 3: Full escalation with concrete recovery steps
    echo "EDIT CHURN CRITICAL: '${FILENAME}' edited ${NEW_COUNT} times this session." >&2
    echo "Repeated edits to the same file indicate a fix-by-guessing loop. Each guess costs time and may introduce new bugs." >&2
    echo "Recovery steps: (1) Read the file from scratch with the Read tool. (2) Run the code and capture actual output. (3) Diff the output against expected behavior. (4) Fix the root cause in one targeted edit, or rewrite the function entirely." >&2
  elif [ "$NEW_COUNT" -ge "$TIER2_THRESHOLD" ]; then
    # Tier 2: Explain the pattern, suggest rewrite
    echo "EDIT CHURN WARNING: '${FILENAME}' edited ${NEW_COUNT} times this session." >&2
    echo "This pattern usually means incremental patches are not converging. Add diagnostic logging or print statements, read the actual output, then make one informed edit. If the function is tangled, a focused rewrite is faster than more patches." >&2
  else
    # Tier 1: Brief nudge
    echo "Edit frequency notice: '${FILENAME}' edited ${NEW_COUNT} times this session. Pause and add diagnostics before the next edit." >&2
  fi

  record_hook_outcome "edit-frequency-guard" "PostToolUse" "warn" "Edit" "edit_frequency_limit" "$EDIT_THRESHOLD" "$MODEL_FAMILY"
  exit 1
fi

record_hook_outcome "edit-frequency-guard" "PostToolUse" "allow" "Edit" "" "" "$MODEL_FAMILY"
exit 0
