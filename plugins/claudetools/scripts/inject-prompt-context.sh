#!/bin/bash
# inject-prompt-context.sh — UserPromptSubmit hook
# Minimal context injection. Only outputs when there's something actionable.
# Everything here costs context tokens — keep it SHORT.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

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
