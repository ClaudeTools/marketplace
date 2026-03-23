#!/bin/bash
# Validator: uncommitted changes detection
# SHARED: used by task-completion-gate.sh AND TeammateIdle
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Calls: get_threshold, record_hook_outcome
# Returns: 0 = clean, 2 = block (uncommitted changes)

validate_git_commits() {
  local CWD
  CWD=$(hook_get_field '.cwd' || echo ".")
  [ -z "$CWD" ] && CWD="."

  # Only check in git repos
  if ! git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null; then
    return 0
  fi

  # Check for uncommitted changes to tracked files
  local UNCOMMITTED STAGED
  UNCOMMITTED=$(git -C "$CWD" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

  # If staged but not committed — they forgot to commit
  if [ "$STAGED" -gt 0 ]; then
    record_hook_outcome "enforce-git-commits" "TaskCompleted" "block" "" "" "" "$MODEL_FAMILY"
    cat >&2 <<EOF
You have ${STAGED} staged files that are not committed.
Uncommitted work is lost during context compaction and is invisible to teammates.

Run: git commit -m "feat: <description>"
EOF
    return 2
  fi

  # If modified tracked files — they forgot to stage and commit
  local UNCOMMITTED_LIMIT
  UNCOMMITTED_LIMIT=$(get_threshold "uncommitted_file_limit")
  UNCOMMITTED_LIMIT=${UNCOMMITTED_LIMIT%.*}
  if [ "$UNCOMMITTED" -gt "$UNCOMMITTED_LIMIT" ]; then
    record_hook_outcome "enforce-git-commits" "TaskCompleted" "block" "" "uncommitted_file_limit" "$UNCOMMITTED_LIMIT" "$MODEL_FAMILY"
    cat >&2 <<EOF
You have ${UNCOMMITTED} modified files that are not committed.
Uncommitted work is lost during context compaction and is invisible to teammates.

Stage and commit:
  git add <specific files you changed>
  git commit -m "feat: <description>"
EOF
    return 2
  fi

  record_hook_outcome "enforce-git-commits" "TaskCompleted" "allow" "" "" "" "$MODEL_FAMILY"
  return 0
}
