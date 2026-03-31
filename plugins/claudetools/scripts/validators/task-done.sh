#!/bin/bash
# Validator: task completion verification — checks that work actually matches the task
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = verified done or skipped, 2 = block (not done)

validate_task_done() {
  # Extract task info from hook input
  local TASK_ID TASK_SUBJECT TASK_DESCRIPTION TRANSCRIPT_PATH CWD TEAMMATE TEAM
  TASK_ID=$(hook_get_field '.task_id')
  TASK_SUBJECT=$(hook_get_field '.task_subject')
  TASK_DESCRIPTION=$(hook_get_field '.task_description')
  TRANSCRIPT_PATH=$(hook_get_field '.transcript_path')
  CWD=$(hook_get_field '.cwd' || echo ".")
  TEAMMATE=$(hook_get_field '.teammate_name' || echo "unknown")
  TEAM=$(hook_get_field '.team_name')

  [ -z "$CWD" ] && CWD="."

  # If no task subject, skip (can't verify without knowing the task)
  if [ -z "$TASK_SUBJECT" ]; then
    return 0
  fi

  # --- Deterministic checks first ---

  # 1. Were ANY files actually changed?
  local CHANGED=""
  local CHANGED_COUNT=0
  if git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
    CHANGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
    local UNTRACKED
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
    CHANGED=$(printf '%s\n%s' "$CHANGED" "$UNTRACKED" | sort -u | sed '/^$/d')
    CHANGED_COUNT=$(echo "$CHANGED" | grep -c . 2>/dev/null || echo "0")
  fi

  # If zero files changed and task isn't a research/audit task, block
  if [ "$CHANGED_COUNT" -eq 0 ]; then
    case "$TASK_SUBJECT" in
      *[Rr]esearch*|*[Aa]udit*|*[Pp]lan*|*[Rr]eview*|*[Ii]nvestigat*|*[Aa]nalyz*)
        return 0
        ;;
      *)
        cat >&2 <<EOF
No files were changed for this task.

Task: ${TASK_SUBJECT}
Description: ${TASK_DESCRIPTION:-N/A}

Git shows zero changed files. If the work is done, commit your changes first.
If not, implement the task before marking it complete.
EOF
        return 2
        ;;
    esac
  fi

  # 2. Deterministic verification — check file relevance without AI
  local CODE_CHANGED ONLY_CONFIG HAS_TEST_FILES
  CODE_CHANGED=$(echo "$CHANGED" | grep -cE '\.(ts|tsx|js|jsx|py|go|rs|rb|java|sh)$' 2>/dev/null || true)
  CODE_CHANGED=$(echo "$CODE_CHANGED" | tr -d '[:space:]')
  CODE_CHANGED="${CODE_CHANGED:-0}"
  ONLY_CONFIG=$([ "$CODE_CHANGED" -eq 0 ] && echo "true" || echo "false")
  HAS_TEST_FILES=$(echo "$CHANGED" | grep -cE '\.(test|spec)\.' 2>/dev/null || true)
  HAS_TEST_FILES=$(echo "$HAS_TEST_FILES" | tr -d '[:space:]')
  HAS_TEST_FILES="${HAS_TEST_FILES:-0}"

  # Block: implementation task with only config/doc changes
  case "$TASK_SUBJECT" in
    *[Ii]mplement*|*[Aa]dd*|*[Ff]ix*|*[Bb]uild*|*[Cc]reate*|*[Rr]efactor*)
      if [ "$ONLY_CONFIG" = "true" ]; then
        cat >&2 <<EOF
Task requires code changes but only config/doc files were modified.

Task: ${TASK_SUBJECT}
Files changed: ${CHANGED_COUNT} (0 code files)

Implement the feature in source code before marking complete.
EOF
        return 2
      fi
      ;;
  esac

  # 3. Check for staged but uncommitted work
  if git -C "$CWD" diff --cached --name-only 2>/dev/null | grep -q .; then
    cat >&2 <<EOF
Staged but uncommitted files detected.

Task: ${TASK_SUBJECT}

Commit your staged changes before marking the task complete.
EOF
    return 2
  fi

  # 4. Passed deterministic checks — allow completion
  return 0
}
