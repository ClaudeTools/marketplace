#!/bin/bash
# post-tool-dispatcher.sh — Universal PostToolUse dispatcher
#
# Replaces 12 individual PostToolUse hook entries with a single entry that
# routes by tool name. All validators still execute — just registered through
# one hooks.json entry.
#
# PostToolUse protocol:
#   - Findings reported on stderr
#   - Exit with max exit code of all validators
#   - No stdout JSON (unlike PreToolUse)
#   - async scripts are fire-and-forget — we background them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read stdin once — all sub-scripts receive INPUT via pipe
INPUT=$(cat 2>/dev/null || true)
export INPUT

# Extract tool name from input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

MAX_EXIT=0

# Helper: run a sub-script synchronously, tracking max exit code
run_post_hook() {
  local script="$1"
  local rc=0
  echo "$INPUT" | bash "$SCRIPT_DIR/$script" || rc=$?
  if [ "$rc" -gt "$MAX_EXIT" ]; then
    MAX_EXIT=$rc
  fi
}

# Helper: run a sub-script asynchronously (fire-and-forget, matches async:true in hooks.json)
run_post_hook_async() {
  local script="$1"
  echo "$INPUT" | bash "$SCRIPT_DIR/$script" &
  disown 2>/dev/null || true
}

# ─── Phase 1: Route by tool name ────────────────────────────────────────────

case "$TOOL_NAME" in

  TaskCreate|TaskUpdate|TaskList)
    run_post_hook "track-native-tasks.sh"
    ;;

  Read)
    run_post_hook "track-file-reads.sh"
    ;;

  Edit|Write)
    run_post_hook "validate-content.sh"
    run_post_hook "edit-frequency-guard.sh"
    run_post_hook "doc-manager.sh"
    run_post_hook "track-file-edits.sh"
    run_post_hook_async "memory-index.sh"
    run_post_hook_async "reindex-on-edit.sh"
    ;;

  Bash)
    run_post_hook "post-bash-gate.sh"
    ;;

  Agent)
    run_post_hook "post-agent-gate.sh"
    ;;

  *)
    # No tool-specific validators for this tool
    ;;

esac

# ─── Phase 2: Always — run for ALL tools ────────────────────────────────────
run_post_hook "browser-circuit-breaker.sh"
run_post_hook "capture-outcome.sh"

exit "$MAX_EXIT"
