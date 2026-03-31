#!/bin/bash
# inject-prompt-context.sh — UserPromptSubmit hook
# Minimal context injection. Only outputs when there's something actionable.
# Everything here costs context tokens — keep it SHORT.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# --- User STOP detection ---
# Extract the user's message text
USER_TEXT=$(echo "$INPUT" | jq -r '
  if (.content | type) == "array" then
    [.content[] | if type == "string" then . elif .type == "text" then .text else "" end] | join(" ")
  elif (.content | type) == "string" then .content
  else ""
  end
' 2>/dev/null || true)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[[ -z "$SESSION_ID" ]] && SESSION_ID="$PPID"
STOP_FLAG="/tmp/claude-user-stop-${SESSION_ID}"

# Check if user message is a stop command (case-insensitive, with frustration variants)
if echo "$USER_TEXT" | grep -qiE '^\s*(stop|STOP|stop it|i said stop|can you stop|please stop|fucking stop|just stop)\s*[.!?]*\s*$'; then
  touch "$STOP_FLAG"
  echo "User requested STOP. All tool calls are blocked until you receive a new non-stop instruction." >&2
  exit 0
fi

# If user sends a non-stop message, clear the flag
if [[ -f "$STOP_FLAG" ]] && [[ -n "$USER_TEXT" ]]; then
  rm -f "$STOP_FLAG"
fi

# --- Skill intent classification (Tier 1: deterministic) ---
source "$(dirname "$0")/lib/skill-router.sh"
USER_TEXT=$(echo "$INPUT" | jq -r '
  if (.content | type) == "array" then
    [.content[] | select(.type == "text") | .text] | join(" ")
  else
    .content // ""
  end' 2>/dev/null || true)

MATCHED_CMD=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_CMD" ]; then
  WORKFLOW_CTX=$(format_workflow_context "$MATCHED_CMD")
  echo "$WORKFLOW_CTX"
  # Track skill invocation for usage analytics
  source "$(dirname "$0")/lib/telemetry.sh"
  emit_skill_invocation "$MATCHED_CMD" "$SESSION_ID" "keyword" 2>/dev/null || true
fi

# --- Agent mesh inbox (only if messages waiting) ---
MESH_CLI="$(dirname "$(dirname "$0")")/agent-mesh/cli.js"
if [[ -f "$MESH_CLI" ]]; then
  _MESH_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [[ -z "$_MESH_SID" ]] && _MESH_SID="$PPID"
  MESSAGES=$(node "$MESH_CLI" inbox --id "$_MESH_SID" --ack 2>/dev/null) || true
  if [[ -n "$MESSAGES" ]]; then
    echo "[mesh] $MESSAGES"
  fi
  { node "$MESH_CLI" heartbeat --id "$_MESH_SID" 2>/dev/null || true; } &
fi

exit 0
