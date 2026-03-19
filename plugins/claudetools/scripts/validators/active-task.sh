#!/bin/bash
# Validator: require-active-task
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, FILE_PATH
# Returns: 0 = active task found (allow), 2 = no active task (block)
# Output: block message written to stdout

validate_active_task() {
  # Skip non-code files — allow edits to docs, config, and task files without a task
  if [ -n "$FILE_PATH" ]; then
    case "$FILE_PATH" in
      *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.csv)
        return 0
        ;;
      */.claude/*)
        return 0
        ;;
    esac
  fi

  # Check for in_progress tasks in Claude's task system
  # Tasks are stored as JSON in ~/.claude/tasks/*/
  local TASK_DIR="$HOME/.claude/tasks"
  local FOUND_ACTIVE=false

  if [ -d "$TASK_DIR" ]; then
    # Search all task JSON files for status: "in_progress"
    while IFS= read -r task_file; do
      [ ! -f "$task_file" ] && continue
      local STATUS
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
    return 0
  fi

  # No active task found — block the edit
  local BLOCKED="No active task. Create a task with TaskCreate and set it to in_progress before editing code. Without a task, changes are untracked and cannot be reviewed or verified at completion."

  record_hook_outcome "require-active-task" "PreToolUse" "block" "" "" "" "$MODEL_FAMILY"
  echo "$BLOCKED"
  return 2
}
