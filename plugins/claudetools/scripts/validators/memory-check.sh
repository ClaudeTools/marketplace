#!/bin/bash
# Validator: enforce memory capture before session stop
# BLOCKS sessions that had meaningful work but saved zero memories.
# Forces the agent through a structured reflection before it can stop.
# Sourced by session-stop-dispatcher after hook_init().
# Returns: 0 = pass (memories saved or session too short), 2 = block (reflect and save)

validate_memory_check() {
  local CWD
  CWD=$(hook_get_field '.cwd' || echo ".")
  [ -z "$CWD" ] && CWD="."

  local SESSION_ID
  SESSION_ID=$(hook_get_field '.session_id' || echo "")

  # Skip if no session ID
  [ -z "$SESSION_ID" ] && return 0

  # Skip if re-evaluation after blocking (prevent infinite loop)
  local STOP_HOOK_ACTIVE
  STOP_HOOK_ACTIVE=$(hook_get_field '.stop_hook_active')
  [ "$STOP_HOOK_ACTIVE" = "true" ] && return 0

  # Skip if session start marker doesn't exist
  local START_MARKER="/tmp/.claude-session-start-${SESSION_ID}"
  [ -f "$START_MARKER" ] || return 0

  # Skip if session <5 minutes old
  local START_TIME NOW_TIME SESSION_AGE_MIN
  START_TIME=$(stat -c '%Y' "$START_MARKER" 2>/dev/null || stat -f '%m' "$START_MARKER" 2>/dev/null || echo 0)
  NOW_TIME=$(date +%s)
  SESSION_AGE_MIN=$(( (NOW_TIME - START_TIME) / 60 ))
  [ "$SESSION_AGE_MIN" -lt 5 ] && return 0

  # Check memory directory for files created AFTER session start
  local MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
  [ -d "$MEMORY_DIR" ] || mkdir -p "$MEMORY_DIR" 2>/dev/null || return 0

  local NEW_MEMORIES=0
  NEW_MEMORIES=$(find "$MEMORY_DIR" -name "*.md" -newer "$START_MARKER" -not -name "MEMORY.md" -not -name "auto_session_summary.md" 2>/dev/null | wc -l | tr -d ' ')

  # If memories were saved this session, pass
  if [ "$NEW_MEMORIES" -gt 0 ]; then
    emit_event "memory-check" "memories_found" "allow" "0" "{\"count\":${NEW_MEMORIES},\"session_min\":${SESSION_AGE_MIN}}" 2>/dev/null || true
    return 0
  fi

  # BLOCK — force structured memory reflection
  cat >&2 <<REFLECT
Before stopping, reflect on what you learned this session (${SESSION_AGE_MIN} min).

Think through each category and save anything worth remembering:

1. FEEDBACK: Did the user correct your approach? ("don't do X", "always do Y")
   → Save as type: feedback — include Why: and How to apply: lines

2. PROJECT: Were architectural decisions, constraints, or deadlines discussed?
   → Save as type: project — include Why: and How to apply: lines

3. REFERENCE: Did you encounter external systems, URLs, configs, or tools?
   → Save as type: reference

4. USER: Did you learn about the user's role, preferences, or expertise?
   → Save as type: user

HOW TO SAVE (two steps — both required):

Step 1: Write the memory file using the Write tool:
  Path: ${MEMORY_DIR}/<type>_<short_name>.md
  Content:
    ---
    name: Human-readable title
    description: One-line summary used for relevance matching
    type: feedback|project|reference|user
    ---
    Body content. For feedback/project types, structure as:
    rule/fact, then **Why:** and **How to apply:** lines.

Step 2: Add a link to MEMORY.md index using the Edit tool:
  Path: ${MEMORY_DIR}/MEMORY.md
  Add line: - [<filename>.md](<filename>.md) — <one-line description>

If genuinely nothing new was learned, write an auto_session_summary.md instead.
REFLECT

  emit_event "memory-check" "reflection_forced" "block" "0" "{\"session_min\":${SESSION_AGE_MIN}}" 2>/dev/null || true
  record_hook_outcome "memory-check" "Stop" "block" "" "" "" "${MODEL_FAMILY:-unknown}"
  return 2
}
