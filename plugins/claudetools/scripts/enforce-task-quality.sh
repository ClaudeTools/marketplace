#!/bin/bash
# TaskCompleted + TeammateIdle hook — prevents task completion or idle with violations
# Exit 2 = reject completion / keep working (stderr fed back as instructions)
# Exit 0 = allow completion / allow idle
#
# Delegates shared validation logic to validators/task-quality.sh (single source of truth).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INPUT=$(cat 2>/dev/null || true)
source "$SCRIPT_DIR/hook-log.sh"

# --- TeammateIdle cooldown: suppress repeated idle notifications within 60s ---
TEAMMATE_ID=$(echo "$INPUT" | jq -r '.teammate_id // .agent_id // "unknown"' 2>/dev/null || echo "unknown")
COOLDOWN_FILE="/tmp/claude-teammate-cooldown-task-quality-${TEAMMATE_ID}"
if [ -f "$COOLDOWN_FILE" ]; then
  COOLDOWN_AGE=$(( $(date +%s) - $(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || echo 0) ))
  if [ "$COOLDOWN_AGE" -lt 60 ]; then
    exit 0
  fi
fi
touch "$COOLDOWN_FILE" 2>/dev/null || true

hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# --- Bootstrap the shared validator infrastructure ---
# hook_init parses INPUT and provides hook_get_field, which validators/task-quality.sh uses.
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init <<< "$INPUT"

# Source the shared validator
source "$SCRIPT_DIR/validators/task-quality.sh"

# --- Run the shared validator ---
HOOK_DECISION="allow"
HOOK_REASON=""
RC=0
validate_task_quality 2>&1 || RC=$?

if [ "$RC" -ge 2 ]; then
  HOOK_DECISION="reject"
  HOOK_REASON="quality gate failed"
  exit 2
elif [ "$RC" -eq 1 ]; then
  # Soft warnings — pass through but don't block
  exit 1
fi

exit 0
