#!/bin/bash
# Validator: enforce memory capture before session stop
# Blocks sessions that had meaningful work but saved zero memories.
# Sourced by session-stop-dispatcher after hook_init().
# Returns: 0 = pass (memories saved or session too short), 1 = warn (save memories)

validate_memory_check() {
  local CWD
  CWD=$(hook_get_field '.cwd' || echo ".")
  [ -z "$CWD" ] && CWD="."

  local SESSION_ID
  SESSION_ID=$(hook_get_field '.session_id' || echo "")

  # Skip if no session ID (can't check session duration)
  [ -z "$SESSION_ID" ] && return 0

  # Skip if session start marker doesn't exist (inject-session-context creates this)
  local START_MARKER="/tmp/.claude-session-start-${SESSION_ID}"
  [ -f "$START_MARKER" ] || return 0

  # Check session age — skip if <5 minutes old (too short for meaningful learnings)
  local START_TIME NOW_TIME SESSION_AGE_MIN
  START_TIME=$(stat -c '%Y' "$START_MARKER" 2>/dev/null || stat -f '%m' "$START_MARKER" 2>/dev/null || echo 0)
  NOW_TIME=$(date +%s)
  SESSION_AGE_MIN=$(( (NOW_TIME - START_TIME) / 60 ))
  [ "$SESSION_AGE_MIN" -lt 5 ] && return 0

  # Check memory directory for files created AFTER session start
  local MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
  [ -d "$MEMORY_DIR" ] || return 0

  local NEW_MEMORIES=0
  if [ -f "$START_MARKER" ]; then
    NEW_MEMORIES=$(find "$MEMORY_DIR" -name "*.md" -newer "$START_MARKER" -not -name "MEMORY.md" -not -name "auto_session_summary.md" 2>/dev/null | wc -l | tr -d ' ')
  fi

  # If memories were saved this session, all good
  if [ "$NEW_MEMORIES" -gt 0 ]; then
    emit_event "memory-check" "memories_found" "allow" "0" "{\"count\":${NEW_MEMORIES},\"session_min\":${SESSION_AGE_MIN}}" 2>/dev/null || true
    return 0
  fi

  # Session had meaningful duration but no memories — warn
  echo "No new memories saved this session (${SESSION_AGE_MIN} min)." >&2
  echo "Save what you learned: feedback corrections, project decisions, useful patterns, or reference information." >&2
  echo "Write memory files to: ${MEMORY_DIR}/" >&2
  emit_event "memory-check" "no_memories" "warn" "0" "{\"session_min\":${SESSION_AGE_MIN}}" 2>/dev/null || true
  record_hook_outcome "memory-check" "Stop" "warn" "" "" "" "${MODEL_FAMILY:-unknown}"
  return 1
}
