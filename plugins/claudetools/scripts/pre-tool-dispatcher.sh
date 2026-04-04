#!/bin/bash
# pre-tool-dispatcher.sh — Universal PreToolUse dispatcher
#
# Replaces 10 individual PreToolUse hook entries with a single entry that
# routes by tool name. All validators still execute — just registered through
# one hooks.json entry.
#
# PreToolUse protocol:
#   - Block via JSON stdout: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block",...}}
#   - Warn via JSON stdout: {"systemMessage":"..."}
#   - Exit 0 always (JSON on stdout carries the decision, not exit code)
#   - Exception: enforce-user-stop uses exit 2 for hard-block (handled here)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read stdin once — all sub-scripts receive $INPUT via env
INPUT=$(cat 2>/dev/null || true)
export INPUT

# Extract tool name from input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# Helper: run a sub-script that reads from stdin, passing $INPUT via pipe.
# Returns the exit code of the sub-script.
run_hook() {
  local script="$1"
  echo "$INPUT" | bash "$SCRIPT_DIR/$script"
}

# Helper: run a sub-script and forward its stdout (JSON) to our stdout.
# If the sub-script exits 2, emit a block JSON and exit 0 immediately.
run_pretool_hook() {
  local script="$1"
  local output rc=0
  output=$(echo "$INPUT" | bash "$SCRIPT_DIR/$script" 2>/dev/null) || rc=$?

  if [ "$rc" -eq 2 ]; then
    # Hard block from sub-script — emit block JSON and stop
    jq -n --arg reason "${output:-Blocked by ${script}}" \
      '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
    exit 0
  fi

  # Forward any JSON output (block or systemMessage) to our stdout
  if [ -n "$output" ]; then
    echo "$output"
    # If the output is a block decision, stop processing immediately
    local decision
    decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
    if [ "$decision" = "block" ]; then
      exit 0
    fi
  fi
}

# ─── Phase 1: Always — enforce-user-stop (inlined for performance) ─────
# Check for user stop flag. SESSION_ID from input, fallback to PPID.
_STOP_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[[ -z "$_STOP_SID" ]] && _STOP_SID="$PPID"
if [[ -f "/tmp/claude-user-stop-${_STOP_SID}" ]]; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"BLOCKED: User said STOP. Do not make any tool calls. Wait for new instructions."}}'
  exit 0
fi

# ─── Phase 2: Route by tool name ────────────────────────────────────────────

case "$TOOL_NAME" in

  Bash)
    # enforce-memory-preferences (Edit|Write|Bash)
    run_pretool_hook "enforce-memory-preferences.sh"
    # pre-bash-gate (Bash only) — may emit block or systemMessage
    run_pretool_hook "pre-bash-gate.sh"
    ;;

  Read)
    # guard-sensitive-files (Read|Edit|Write)
    run_pretool_hook "guard-sensitive-files.sh"
    # enforce-read-efficiency (Read|Edit|Write — internally filters to Read only)
    run_pretool_hook "enforce-read-efficiency.sh"
    # guard-context-reread (Read only)
    run_pretool_hook "guard-context-reread.sh"
    ;;

  Edit|Write)
    # guard-sensitive-files (Read|Edit|Write)
    run_pretool_hook "guard-sensitive-files.sh"
    # enforce-read-efficiency (Read|Edit|Write — internally no-ops for Edit/Write)
    run_pretool_hook "enforce-read-efficiency.sh"
    # enforce-memory-preferences (Edit|Write|Bash)
    run_pretool_hook "enforce-memory-preferences.sh"
    # pre-edit-gate (Edit|Write)
    run_pretool_hook "pre-edit-gate.sh"
    # enforce-native-task-hygiene (Edit|Write|Agent)
    run_pretool_hook "enforce-native-task-hygiene.sh"
    ;;

  Agent)
    # enforce-team-usage (Agent only)
    run_pretool_hook "enforce-team-usage.sh"
    # enforce-native-task-hygiene (Edit|Write|Agent)
    run_pretool_hook "enforce-native-task-hygiene.sh"
    ;;

  Grep)
    # intercept-grep (Grep only)
    run_pretool_hook "intercept-grep.sh"
    ;;

  *)
    # Unknown tool — allow through (no validators apply)
    ;;

esac

exit 0
