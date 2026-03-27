#!/bin/bash
# track-native-tasks.sh — PostToolUse hook for TaskCreate|TaskUpdate|TaskList
# Shadows native task state to a temp file so PreToolUse hooks can enforce hygiene.
#
# State file: /tmp/claude-native-tasks-${SESSION_ID}.json
# Format: { "tasks": { "<id>": {...} }, "tool_calls_since_update": N, "last_task_tool_at": N, "session_start": N }
#
# Exit 0 always — this is a passive tracker, never blocks.
# All jq operations are guarded — a corrupted state file is silently re-initialized.

# No set -e — this hook must NEVER fail in a way that affects the session.
# Every operation has explicit error handling.

# Quiet mode: skip non-safety hooks
[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

INPUT=$(cat 2>/dev/null || true)
[[ -z "$INPUT" ]] && exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
STATE_FILE="/tmp/claude-native-tasks-${SESSION_ID}.json"
NOW=$(date +%s)

# --- State file initialization & validation ---

init_state_file() {
  echo "{\"tasks\":{},\"tool_calls_since_update\":0,\"last_task_tool_at\":0,\"total_tool_calls\":0,\"session_start\":${NOW}}" > "$STATE_FILE" 2>/dev/null
}

# Validate existing state file is parseable JSON
validate_state_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    init_state_file
    return
  fi
  # Try to parse — if it fails, re-init
  if ! jq empty "$STATE_FILE" 2>/dev/null; then
    init_state_file
  fi
}

# Safe jq write: validates output before replacing the original
safe_jq_update() {
  local expr="$1"
  local tmp="${STATE_FILE}.tmp.$$"
  if jq "$@" "$STATE_FILE" > "$tmp" 2>/dev/null && jq empty "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
    # Don't re-init — just skip this update
  fi
}

validate_state_file

case "$TOOL_NAME" in
  TaskCreate)
    # PostToolUse provides: tool_response.task.id and tool_response.task.subject
    # Primary: extract structured ID from tool_response object
    TASK_ID=$(echo "$INPUT" | jq -r '.tool_response.task.id // .tool_response.id // ""' 2>/dev/null || echo "")

    # Fallback: try tool_response as a string containing "Task #N"
    if [[ -z "$TASK_ID" ]]; then
      TASK_RESULT=$(echo "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
      TASK_ID=$(echo "$TASK_RESULT" | grep -o '#[0-9]*' | head -1 | tr -d '#' || echo "")
    fi

    # No ID found — tool likely failed, skip to avoid phantom tasks
    if [[ -z "$TASK_ID" ]]; then
      exit 0
    fi

    # Subject from response (confirmed) or input (fallback)
    SUBJECT=$(echo "$INPUT" | jq -r '.tool_response.task.subject // .tool_input.subject // "unknown"' 2>/dev/null || echo "unknown")
    DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
    # Add the task to state
    jq --arg id "$TASK_ID" \
       --arg subject "$SUBJECT" \
       --arg desc "$DESCRIPTION" \
       --argjson now "$NOW" \
       '.tasks[$id] = {
          "subject": $subject,
          "description": $desc,
          "status": "pending",
          "created_at": $now,
          "updated_at": $now
        } |
        .tool_calls_since_update = 0 |
        .last_task_tool_at = $now' \
       "$STATE_FILE" > "${STATE_FILE}.tmp.$$" 2>/dev/null \
       && jq empty "${STATE_FILE}.tmp.$$" 2>/dev/null \
       && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null \
       || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null
    ;;

  TaskUpdate)
    TASK_ID=$(echo "$INPUT" | jq -r '.tool_input.taskId // ""' 2>/dev/null || echo "")
    NEW_STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // ""' 2>/dev/null || echo "")

    if [[ -n "$TASK_ID" ]]; then
      # Guard: only update tasks that exist in shadow state
      TASK_EXISTS=$(jq -r --arg id "$TASK_ID" '.tasks[$id] // empty' "$STATE_FILE" 2>/dev/null || echo "")
      if [[ -z "$TASK_EXISTS" ]]; then
        # Task not in shadow state — it was created before the hook was installed,
        # or the tracker missed it. Create a stub entry so future updates work.
        jq --arg id "$TASK_ID" \
           --arg status "${NEW_STATUS:-unknown}" \
           --argjson now "$NOW" \
           '.tasks[$id] = {"subject":"(untracked)","description":"","status":$status,"created_at":$now,"updated_at":$now} |
            .tool_calls_since_update = 0 | .last_task_tool_at = $now' \
           "$STATE_FILE" > "${STATE_FILE}.tmp.$$" 2>/dev/null \
           && jq empty "${STATE_FILE}.tmp.$$" 2>/dev/null \
           && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null \
           || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null
      else
        # Task exists — update it
        if [[ -n "$NEW_STATUS" ]]; then
          UPDATE_EXPR='.tasks[$id].status = $status | .tasks[$id].updated_at = $now | .tool_calls_since_update = 0 | .last_task_tool_at = $now'
        else
          UPDATE_EXPR='.tasks[$id].updated_at = $now | .tool_calls_since_update = 0 | .last_task_tool_at = $now'
        fi

        jq --arg id "$TASK_ID" \
           --arg status "$NEW_STATUS" \
           --argjson now "$NOW" \
           "$UPDATE_EXPR" \
           "$STATE_FILE" > "${STATE_FILE}.tmp.$$" 2>/dev/null \
           && jq empty "${STATE_FILE}.tmp.$$" 2>/dev/null \
           && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null \
           || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null
      fi
    fi
    ;;

  TaskList)
    # TaskList is informational — just reset the staleness counter
    jq --argjson now "$NOW" \
       '.last_task_tool_at = $now | .tool_calls_since_update = 0' \
       "$STATE_FILE" > "${STATE_FILE}.tmp.$$" 2>/dev/null \
       && jq empty "${STATE_FILE}.tmp.$$" 2>/dev/null \
       && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null \
       || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null
    ;;
esac

exit 0
