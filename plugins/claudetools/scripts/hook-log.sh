#!/bin/bash
# Shared hook logging — source this from every hook
# Usage: source "$(dirname "$0")/hook-log.sh"
# Then call: hook_log "message"
# Logs to <plugin>/logs/hooks.log with timestamp, hook name, agent info

_HOOK_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$_HOOK_LOG_DIR"
HOOK_LOG_FILE="$_HOOK_LOG_DIR/hooks.log"
HOOK_NAME="$(basename "${BASH_SOURCE[1]:-$0}")"

hook_log() {
  local msg="$1"
  # Log rotation: if hooks.log exceeds 5MB, rotate to hooks.log.old
  if [ -f "$HOOK_LOG_FILE" ]; then
    local size
    size=$(stat -f%z "$HOOK_LOG_FILE" 2>/dev/null || stat -c%s "$HOOK_LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 5242880 ]; then
      mv -f "$HOOK_LOG_FILE" "${HOOK_LOG_FILE}.old"
    fi
  fi
  local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local agent_id=$(echo "$INPUT" | jq -r '.agent_id // "main"' 2>/dev/null || echo "unknown")
  local agent_type=$(echo "$INPUT" | jq -r '.agent_type // "main"' 2>/dev/null || echo "unknown")
  local tool=$(echo "$INPUT" | jq -r '.tool_name // "none"' 2>/dev/null || echo "unknown")
  echo "${ts} | ${HOOK_NAME} | agent=${agent_id} type=${agent_type} tool=${tool} | ${msg}" >> "$HOOK_LOG_FILE"
}

hook_log_result() {
  local exit_code="$1"
  local decision="${2:-allow}"
  local reason="${3:-}"
  local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local agent_id=$(echo "$INPUT" | jq -r '.agent_id // "main"' 2>/dev/null || echo "unknown")
  local agent_type=$(echo "$INPUT" | jq -r '.agent_type // "main"' 2>/dev/null || echo "unknown")
  local tool=$(echo "$INPUT" | jq -r '.tool_name // "none"' 2>/dev/null || echo "unknown")
  echo "${ts} | ${HOOK_NAME} | agent=${agent_id} type=${agent_type} tool=${tool} | decision=${decision} exit=${exit_code} reason=${reason}" >> "$HOOK_LOG_FILE"
}

# jq dependency guard — hooks skip gracefully on fresh installs without jq
require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "claudetools: jq not found, hook skipped" >&2
    exit 0
  fi
}

# Auto-check jq when sourced — every hook that sources this file gets the guard
require_jq
