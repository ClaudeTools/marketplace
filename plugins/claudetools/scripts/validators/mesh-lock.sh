#!/usr/bin/env bash
# Validator: mesh lock check — warns if another agent holds a lock on the target file
# Sourced by pre-edit-gate.sh after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY, SCRIPT_DIR
# Returns: 0 = no conflict, 1 = warning (another agent has lock)

validate_mesh_lock() {
  local FILE_PATH
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  [[ -z "$FILE_PATH" ]] && return 0

  # Find mesh locks directory
  local GIT_COMMON REPO_ROOT MESH_LOCKS
  GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  REPO_ROOT="${GIT_COMMON%/.git}"
  MESH_LOCKS="$REPO_ROOT/.claude/mesh/locks"
  [[ -d "$MESH_LOCKS" ]] || return 0

  # Hash file path to find lock file (must match cli.js hashPath — sha256, first 16 chars)
  local LOCK_HASH LOCK_FILE
  LOCK_HASH=$(printf '%s' "$FILE_PATH" | sha256sum 2>/dev/null | head -c 16)
  [[ -z "$LOCK_HASH" ]] && LOCK_HASH=$(printf '%s' "$FILE_PATH" | shasum -a 256 2>/dev/null | head -c 16)
  LOCK_FILE="$MESH_LOCKS/${LOCK_HASH}.json"
  [[ -f "$LOCK_FILE" ]] || return 0

  # Read lock owner
  local LOCK_AGENT_ID
  LOCK_AGENT_ID=$(jq -r '.agent_id // empty' "$LOCK_FILE" 2>/dev/null || true)

  # Get our session ID
  local OUR_SID
  OUR_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "$PPID")

  # Skip if we own the lock
  [[ "$LOCK_AGENT_ID" == "$OUR_SID" ]] && return 0

  # Check if lock owner PID is still alive (clean stale locks)
  local LOCK_PID
  LOCK_PID=$(jq -r '.pid // empty' "$LOCK_FILE" 2>/dev/null || true)
  if [[ -n "$LOCK_PID" ]] && ! kill -0 "$LOCK_PID" 2>/dev/null; then
    rm -f "$LOCK_FILE"
    hook_log "mesh-lock: cleaned stale lock for PID $LOCK_PID on $FILE_PATH"
    return 0
  fi

  local LOCK_AGENT_NAME LOCK_REASON
  LOCK_AGENT_NAME=$(jq -r '.agent_name // "unknown agent"' "$LOCK_FILE" 2>/dev/null || echo "unknown agent")
  LOCK_REASON=$(jq -r '.reason // ""' "$LOCK_FILE" 2>/dev/null || true)

  echo "[agent-mesh] $(basename "$FILE_PATH") is locked by $LOCK_AGENT_NAME${LOCK_REASON:+ ($LOCK_REASON)}. Coordinate before editing."
  return 1
}
