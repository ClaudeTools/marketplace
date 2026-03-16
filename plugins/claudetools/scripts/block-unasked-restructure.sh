#!/bin/bash
# PreToolUse:Bash hook — blocks file restructuring/renaming unless the task explicitly asks for it
# Enforces: no-shortcuts.md "Don't rename files, restructure directories, or add dependencies unless that's the task"
# Exit 0 with JSON block = prevent action, Exit 0 without JSON = allow

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the bash command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Detect restructure/rename patterns
IS_RESTRUCTURE=false
RESTRUCTURE_REASON=""

# File moves/renames
if echo "$COMMAND" | grep -qE '^\s*(mv|git mv)\s+' 2>/dev/null; then
  # Allow mv within the same directory (renaming a single file to fix a typo is fine)
  # Block cross-directory moves that indicate restructuring
  if echo "$COMMAND" | grep -qE '(mv|git mv)\s+\S+/\S+\s+\S+/' 2>/dev/null; then
    IS_RESTRUCTURE=true
    RESTRUCTURE_REASON="Cross-directory file move detected"
  fi
fi

# Bulk directory creation (new structure)
if echo "$COMMAND" | grep -qE 'mkdir\s+(-p\s+)?\S+/\S+/\S+' 2>/dev/null; then
  IS_RESTRUCTURE=true
  RESTRUCTURE_REASON="Deep directory structure creation detected"
fi

# Bulk find-and-move
if echo "$COMMAND" | grep -qE 'find\s.*-exec\s+(mv|cp)' 2>/dev/null; then
  IS_RESTRUCTURE=true
  RESTRUCTURE_REASON="Bulk file move/copy via find detected"
fi

# xargs mv/cp
if echo "$COMMAND" | grep -qE 'xargs\s+(mv|cp)' 2>/dev/null; then
  IS_RESTRUCTURE=true
  RESTRUCTURE_REASON="Bulk file move/copy via xargs detected"
fi

if [ "$IS_RESTRUCTURE" = false ]; then
  exit 0
fi

# Check if the active task authorizes restructuring
TASK_DIR="$HOME/.claude/tasks"
AUTHORIZED=false

if [ -d "$TASK_DIR" ]; then
  # Find in_progress tasks and check their descriptions
  for task_file in "$TASK_DIR"/*.json; do
    [ -f "$task_file" ] || continue
    STATUS=$(jq -r '.status // empty' "$task_file" 2>/dev/null || true)
    [ "$STATUS" != "in_progress" ] && continue

    SUBJECT=$(jq -r '.subject // empty' "$task_file" 2>/dev/null || true)
    DESCRIPTION=$(jq -r '.description // empty' "$task_file" 2>/dev/null || true)
    COMBINED="$SUBJECT $DESCRIPTION"

    # Check for restructure-related keywords
    if echo "$COMBINED" | grep -qiE 'restructur|reorganiz|rename|move files|refactor.*structure|directory.*layout|folder.*structure|migration|relocat'; then
      AUTHORIZED=true
      break
    fi
  done
fi

if [ "$AUTHORIZED" = true ]; then
  hook_log "restructure authorized by task"
  record_hook_outcome "block-unasked-restructure" "PreToolUse" "allow" "Bash" "" ""
  exit 0
fi

# Block the restructure
BLOCKED="${RESTRUCTURE_REASON}. Rule: Don't rename files, restructure directories, or add dependencies unless that's the task (no-shortcuts.md). Your current task does not mention restructuring. If restructuring is needed, update the task description first or ask the user."
HOOK_DECISION="block" HOOK_REASON="$BLOCKED"

record_hook_outcome "block-unasked-restructure" "PreToolUse" "block" "Bash" "" ""
jq -n \
  --arg reason "$BLOCKED" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'

exit 0
