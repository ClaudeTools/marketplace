#!/bin/bash
# enforce-native-task-hygiene.sh — PreToolUse hook for Edit|Write|Agent
# Reads the native task shadow state and enforces task discipline:
#
# Rule 1 (SOFT WARN): Tasks exist but none are in_progress — nudge to call TaskUpdate
# Rule 2 (SOFT WARN): A task has been in_progress for 20+ tool calls without update
#
# DESIGN DECISIONS:
# - No hard blocks (exit 2) — task hygiene should guide, not lock out
# - Only fires on Edit|Write|Agent — NOT Bash (too many diagnostic Bash calls)
# - Opt-in model: only activates after tasks have been created
# - Fail-open: ANY error in this hook → exit 0 (allow). A corrupted state file
#   must NEVER prevent work.
# - Counter increments are best-effort — if the write fails, we skip it
#
# Exit 0 = allow
# Exit 1 = soft warning (message shown to Claude, tool still proceeds)

# No set -e — this hook must NEVER crash in a way that blocks the session.
# Every path that could fail has explicit fallback to exit 0.

# Quiet mode: skip non-safety hooks
[[ "${CLAUDE_HOOKS_QUIET:-}" = "1" ]] && exit 0

INPUT=$(cat 2>/dev/null || true)
[[ -z "$INPUT" ]] && exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
STATE_FILE="/tmp/claude-native-tasks-${SESSION_ID}.json"

# No state file = no tasks created yet = nothing to enforce
[[ ! -f "$STATE_FILE" ]] && exit 0

# Validate state file is parseable — if corrupted, bail out silently
if ! jq empty "$STATE_FILE" 2>/dev/null; then
  # Corrupted state file — remove it so the tracker re-initializes on next TaskCreate
  rm -f "$STATE_FILE" 2>/dev/null
  exit 0
fi

# --- Stale session detection ---
# If the state file is from a different session (>6h old), ignore it
SESSION_START=$(jq -r '.session_start // 0' "$STATE_FILE" 2>/dev/null || echo "0")
NOW=$(date +%s)
AGE=$(( NOW - ${SESSION_START:-0} ))
if [[ "$AGE" -gt 21600 ]]; then
  # State file is >6 hours old — likely from a previous session
  rm -f "$STATE_FILE" 2>/dev/null
  exit 0
fi

# --- Read task state (all with safe defaults) ---
TASK_COUNT=$(jq '.tasks | length' "$STATE_FILE" 2>/dev/null || echo "0")
TASK_COUNT=${TASK_COUNT:-0}

# No tasks = nothing to enforce
[[ "$TASK_COUNT" -eq 0 ]] 2>/dev/null && exit 0

PENDING=$(jq '[.tasks[] | select(.status == "pending")] | length' "$STATE_FILE" 2>/dev/null || echo "0")
PENDING=${PENDING:-0}
IN_PROGRESS=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$STATE_FILE" 2>/dev/null || echo "0")
IN_PROGRESS=${IN_PROGRESS:-0}

# Active = pending + in_progress (not completed/deleted)
ACTIVE=$(( ${PENDING:-0} + ${IN_PROGRESS:-0} )) 2>/dev/null || ACTIVE=0

# All tasks finished = nothing to enforce
[[ "$ACTIVE" -eq 0 ]] 2>/dev/null && exit 0

# --- Increment tool call counter (best-effort) ---
# If this write fails, we just skip staleness tracking — not critical
jq '.tool_calls_since_update = (.tool_calls_since_update + 1) | .total_tool_calls = (.total_tool_calls + 1)' \
   "$STATE_FILE" > "${STATE_FILE}.tmp.$$" 2>/dev/null \
   && jq empty "${STATE_FILE}.tmp.$$" 2>/dev/null \
   && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null \
   || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null

CALLS_SINCE_UPDATE=$(jq '.tool_calls_since_update' "$STATE_FILE" 2>/dev/null || echo "0")
CALLS_SINCE_UPDATE=${CALLS_SINCE_UPDATE:-0}

# --- Rule 1: Nudge when tasks exist but none are in_progress ---
# Soft warn only — Claude can proceed but gets a reminder
if [[ "${IN_PROGRESS:-0}" -eq 0 && "${PENDING:-0}" -gt 0 ]] 2>/dev/null; then
  PENDING_LIST=$(jq -r '[.tasks | to_entries[] | select(.value.status == "pending") | "#\(.key): \(.value.subject)"] | join(", ")' "$STATE_FILE" 2>/dev/null || echo "(unknown)")

  cat >&2 <<EOF
TASK HYGIENE: You have ${PENDING} pending task(s) but none are marked in_progress. Consider calling TaskUpdate to mark the relevant task as in_progress: ${PENDING_LIST}
EOF
  exit 1
fi

# --- Rule 2: Stale in_progress tasks ---
STALE_THRESHOLD=20
if [[ "${CALLS_SINCE_UPDATE:-0}" -ge "$STALE_THRESHOLD" && "${IN_PROGRESS:-0}" -gt 0 ]] 2>/dev/null; then
  STALE_LIST=$(jq -r '[.tasks | to_entries[] | select(.value.status == "in_progress") | "#\(.key): \(.value.subject)"] | join(", ")' "$STATE_FILE" 2>/dev/null || echo "(unknown)")

  cat >&2 <<EOF
TASK HYGIENE: ${CALLS_SINCE_UPDATE} tool calls since last task update. Still in_progress: ${STALE_LIST}. Consider marking completed tasks done or updating with progress.
EOF
  # Reset counter so we don't spam every call
  jq '.tool_calls_since_update = 0' \
     "$STATE_FILE" > "${STATE_FILE}.tmp.$$" 2>/dev/null \
     && jq empty "${STATE_FILE}.tmp.$$" 2>/dev/null \
     && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null \
     || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null
  exit 1
fi

exit 0
