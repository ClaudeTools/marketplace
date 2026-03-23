#!/bin/bash
# PreToolUse hook — hard-blocks ALL tool calls when user has said "stop"
# The stop flag is set by inject-prompt-context.sh (UserPromptSubmit hook)
# and cleared when the user sends a new non-stop message.
#
# Exit 2 = hard block. Exit 0 = allow.

INPUT=$(cat 2>/dev/null || true)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[[ -z "$SESSION_ID" ]] && SESSION_ID="$PPID"
STOP_FLAG="/tmp/claude-user-stop-${SESSION_ID}"

if [[ -f "$STOP_FLAG" ]]; then
  echo "BLOCKED: User said STOP. Do not make any tool calls. Wait for new instructions." >&2
  exit 2
fi

exit 0
