#!/bin/bash
# Validator: enforce-task-scope
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, FILE_PATH, MODEL_FAMILY
# Returns: 0 = in scope or no scope hints, 1 = warning (file outside inferred scope)
# Output: warning message written to stdout

validate_task_scope() {
  if [ -z "$FILE_PATH" ]; then
    return 0
  fi

  # Skip config/meta files — these are always in scope
  case "$FILE_PATH" in
    *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.csv)
      return 0
      ;;
    */.claude/*|*/.git/*|*/node_modules/*|*/.venv/*|*/venv/*)
      return 0
      ;;
  esac

  # Find active in_progress task and extract scope hints
  local TASK_DIR="$HOME/.claude/tasks"
  local TASK_SCOPE=""
  local TASK_SUBJECT=""

  if [ -d "$TASK_DIR" ]; then
    while IFS= read -r task_file; do
      [ -f "$task_file" ] || continue
      local STATUS
      STATUS=$(jq -r '.status // empty' "$task_file" 2>/dev/null || true)
      [ "$STATUS" != "in_progress" ] && continue

      TASK_SUBJECT=$(jq -r '.subject // empty' "$task_file" 2>/dev/null || true)
      local DESCRIPTION
      DESCRIPTION=$(jq -r '.description // empty' "$task_file" 2>/dev/null || true)
      local COMBINED="$TASK_SUBJECT $DESCRIPTION"

      # Extract explicit directory scope from task description
      # Look for patterns like "in src/", "modify src/routes/", "only touch tests/"
      # Also look for "files_in_scope" or explicit path mentions
      local SCOPE_DIRS
      SCOPE_DIRS=$(echo "$COMBINED" | grep -oE '(src|lib|tests|test|app|pages|components|routes|scripts|config|public|client|server|api|utils|helpers|services|models|controllers|views|hooks|styles|assets)/[^ ]*' | sed 's|/[^/]*$||' | sort -u || true)

      # Also extract top-level directory mentions like "only modify src/"
      local TOP_DIRS
      TOP_DIRS=$(echo "$COMBINED" | grep -oE '\b(src|lib|tests|test|app|pages|components|routes|scripts|config|public|client|server|api|plugin)/\b' | sort -u || true)

      TASK_SCOPE=$(printf '%s\n%s' "$SCOPE_DIRS" "$TOP_DIRS" | sed '/^$/d' | sort -u)
      break
    done < <(find "$TASK_DIR" -name "*.json" -type f 2>/dev/null)
  fi

  # No active task or no scope hints → allow
  if [ -z "$TASK_SCOPE" ]; then
    return 0
  fi

  # Check if the file path falls within any scoped directory
  local FILE_DIR
  FILE_DIR=$(dirname "$FILE_PATH")
  local IN_SCOPE=false

  while IFS= read -r scope_dir; do
    [ -z "$scope_dir" ] && continue
    # Check if file path starts with or contains the scope directory
    if echo "$FILE_PATH" | grep -q "^${scope_dir}\|/${scope_dir}" 2>/dev/null; then
      IN_SCOPE=true
      break
    fi
    # Also check if the file is in a subdirectory of scope
    if echo "$FILE_DIR" | grep -q "^${scope_dir}\|/${scope_dir}" 2>/dev/null; then
      IN_SCOPE=true
      break
    fi
  done <<< "$TASK_SCOPE"

  if [ "$IN_SCOPE" = true ]; then
    record_hook_outcome "enforce-task-scope" "PreToolUse" "allow" "" "" "" "$MODEL_FAMILY"
    return 0
  fi

  # File is outside scope — warn (not block, since scope inference is heuristic)
  local BASENAME_VAR
  BASENAME_VAR=$(basename "$FILE_PATH")
  local WARNING="File '${BASENAME_VAR}' appears outside the task scope. Task '${TASK_SUBJECT}' seems scoped to: $(echo "$TASK_SCOPE" | tr '\n' ', ' | sed 's/,$//'). If this file change is needed, continue. If not, focus on files within scope."

  record_hook_outcome "enforce-task-scope" "PreToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  echo "$WARNING"
  return 1
}
