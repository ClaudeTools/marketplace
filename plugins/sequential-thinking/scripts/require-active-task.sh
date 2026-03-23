#!/usr/bin/env bash
# PreToolUse:Edit|Write hook — blocks code edits unless an in_progress task exists
# Ensures all code changes are tracked against a task for accountability.
# Exit 0 always — blocking done via JSON stdout with permissionDecision "block"

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract file path to check if this is a code file worth gating
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Skip non-code files — allow edits to docs, config, and task files without a task
if [ -n "$FILE_PATH" ]; then
  case "$FILE_PATH" in
    *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.csv)
      exit 0
      ;;
    */.claude/*)
      exit 0
      ;;
  esac
fi

# Check for in_progress tasks in Claude's task system
# Tasks are stored as JSON in ~/.claude/tasks/*/
TASK_DIR="$HOME/.claude/tasks"
FOUND_ACTIVE=false

if [ -d "$TASK_DIR" ]; then
  # Search all task JSON files for status: "in_progress"
  while IFS= read -r task_file; do
    [ ! -f "$task_file" ] && continue
    STATUS=$(jq -r '.status // empty' "$task_file" 2>/dev/null || true)
    if [ "$STATUS" = "in_progress" ]; then
      FOUND_ACTIVE=true
      break
    fi
  done < <(find "$TASK_DIR" -name "*.json" -type f 2>/dev/null)
fi

if [ "$FOUND_ACTIVE" = true ]; then
  # Active task exists — allow the edit
  record_hook_outcome "require-active-task" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
  exit 0
fi

# No active task found — block the edit
BLOCKED="No active task. Create a task with TaskCreate and set it to in_progress before editing code. Without a task, changes are untracked and cannot be reviewed or verified at completion."

HOOK_DECISION="block"; HOOK_REASON="$BLOCKED"

record_hook_outcome "require-active-task" "PreToolUse" "block" "" "" "" "$MODEL_FAMILY"
jq -n \
  --arg reason "$BLOCKED" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "block",
      permissionDecisionReason: $reason
    }
  }'

exit 0
